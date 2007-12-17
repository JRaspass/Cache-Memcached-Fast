/*
  Copyright (C) 2007 Tomash Brechko.  All rights reserved.

  This library is free software; you can redistribute it and/or modify
  it under the same terms as Perl itself, either Perl version 5.8.8
  or, at your option, any later version of Perl 5 you may have
  available.
*/

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


#include "src/client.h"
#include <stdlib.h>
#include <string.h>


typedef struct client Cache_Memcached_Fast;
typedef SV *Ref_SV;


static
void
add_server(Cache_Memcached_Fast *memd, SV *addr_sv, double weight)
{
  static const int delim = ':';
  const char *host, *port;
  size_t host_len, port_len;
  STRLEN len;
  int res;

  if (weight <= 0.0)
    croak("Server weight should be positive");

  host = SvPV(addr_sv, len);
  /*
    NOTE: here we relay on the fact that host is zero-terminated.
  */
  port = strrchr(host, delim);
  if (port)
    {
      host_len = port - host;
      ++port;
      port_len = len - host_len - 1;
      res = client_add_server(memd, host, host_len, port, port_len, weight);
    }
  else
    {
      res = client_add_server(memd, host, len, NULL, 0, weight);
    }
  if (res != MEMCACHED_SUCCESS)
    croak("Not enough memory");
}


static
void
parse_server(Cache_Memcached_Fast *memd, SV *sv)
{
  if (! SvROK(sv))
    {
      add_server(memd, sv, 1.0);
    }
  else
    {
      switch (SvTYPE(SvRV(sv)))
        {
        case SVt_PVHV:
          {
            HV *hv = (HV *) SvRV(sv);
            SV **addr_sv, **weight_sv;
            double weight = 1.0;

            addr_sv = hv_fetch(hv, "address", 7, 0);
            if (! addr_sv)
              croak("server should have { address => $addr }");
            weight_sv = hv_fetch(hv, "weight", 6, 0);
            if (weight_sv)
              weight = SvNV(*weight_sv);
            add_server(memd, *addr_sv, weight);
          }
          break;

        case SVt_PVAV:
          {
            AV *av = (AV *) SvRV(sv);
            SV **addr_sv, **weight_sv;
            double weight = 1.0;

            addr_sv = av_fetch(av, 0, 0);
            if (! addr_sv)
              croak("server should be [$addr, $weight]");
            weight_sv = av_fetch(av, 1, 0);
            if (weight_sv)
              weight = SvNV(*weight_sv);
            add_server(memd, *addr_sv, weight);
          }
          break;

        default:
          croak("Not a hash or array reference");
          break;
        }
    }
}


static
void
parse_config(Cache_Memcached_Fast *memd, HV *conf)
{
  SV **ps;

  ps = hv_fetch(conf, "ketama_points", 13, 0);
  if (ps)
    {
      int res = client_set_ketama_points(memd, SvIV(*ps));
      if (res != MEMCACHED_SUCCESS)
        croak("client_set_ketama() failed");
    }

  ps = hv_fetch(conf, "servers", 7, 0);
  if (ps)
    {
      AV *a;
      int max_index, i;

      if (! SvROK(*ps) || SvTYPE(SvRV(*ps)) != SVt_PVAV)
        croak("Not an array reference");
      a = (AV *) SvRV(*ps);
      max_index = av_len(a);
      for (i = 0; i <= max_index; ++i)
        {
          ps = av_fetch(a, i, 0);
          if (! ps)
            continue;

          parse_server(memd, *ps);
        }
    }

  ps = hv_fetch(conf, "namespace", 9, 0);
  if (ps)
    {
      const char *ns;
      STRLEN len;
      ns = SvPV(*ps, len);
      if (client_set_prefix(memd, ns, len) != MEMCACHED_SUCCESS)
        croak("Not enough memory");
    }

  ps = hv_fetch(conf, "connect_timeout", 15, 0);
  if (ps)
    {
      client_set_connect_timeout(memd, SvNV(*ps) * 1000.0);
    }

  ps = hv_fetch(conf, "io_timeout", 10, 0);
  if (ps)
    {
      client_set_io_timeout(memd, SvNV(*ps) * 1000.0);
    }

  /* For compatibility with Cache::Memcached.  */
  ps = hv_fetch(conf, "select_timeout", 14, 0);
  if (ps)
    {
      client_set_io_timeout(memd, SvNV(*ps) * 1000.0);
    }

  ps = hv_fetch(conf, "max_failures", 12, 0);
  if (ps)
    {
      client_set_max_failures(memd, SvIV(*ps));
    }

  ps = hv_fetch(conf, "failure_timeout", 15, 0);
  if (ps)
    {
      client_set_failure_timeout(memd, SvIV(*ps));
    }

  ps = hv_fetch(conf, "close_on_error", 14, 0);
  if (ps)
    {
      client_set_close_on_error(memd, SvTRUE(*ps));
    }

  ps = hv_fetch(conf, "noreply", 7, 0);
  if (ps)
    {
      /* This may set 'close_on_error'.  */
      client_set_noreply(memd, SvTRUE(*ps));
    }
}


struct xs_skey_result
{
  SV *sv;
  flags_type flags;
  cas_type cas;
};


static
void *
skey_alloc(void *arg, value_size_type value_size)
{
  struct xs_skey_result *skey_res;
  char *res;

  skey_res = (struct xs_skey_result *) arg;

  skey_res->sv = newSVpvn("", 0);
  res = SvGROW(skey_res->sv, value_size + 1); /* FIXME: check OOM.  */
  res[value_size] = '\0';
  SvCUR_set(skey_res->sv, value_size);

  return (void *) res;
}


static
void
skey_store(void *arg, int key_index, flags_type flags,
           int use_cas, cas_type cas)
{
  struct xs_skey_result *skey_res;

  /* Suppress warning about unused key_index and use_cas.  */
  if (key_index || use_cas) {}

  skey_res = (struct xs_skey_result *) arg;

  skey_res->flags = flags;
  skey_res->cas = cas;
}


static
void
skey_free(void *arg)
{
  struct xs_skey_result *skey_res;

  skey_res = (struct xs_skey_result *) arg;

  SvREFCNT_dec(skey_res->sv);
  skey_res->sv = NULL;
}


struct xs_mkey_result
{
  SV *sv;
  AV *key_val;
  AV *flags;
  I32 ax;
  int stack_offset;
};


static
char *
get_key(void *arg, int key_index, size_t *key_len)
{
  I32 ax;
  struct xs_mkey_result *mkey_res;
  SV *key_sv;
  char *res;
  STRLEN len;

  mkey_res = (struct xs_mkey_result *) arg;

  ax = mkey_res->ax;
  key_sv = ST(mkey_res->stack_offset + key_index);
  res = SvPV(key_sv, len);
  *key_len = len;

  return res;
}


static
void *
mkey_alloc(void *arg, value_size_type value_size)
{
  struct xs_mkey_result *mkey_res;
  char *res;

  mkey_res = (struct xs_mkey_result *) arg;

  mkey_res->sv = newSVpvn("", 0);
  res = SvGROW(mkey_res->sv, value_size + 1); /* FIXME: check OOM.  */
  res[value_size] = '\0';
  SvCUR_set(mkey_res->sv, value_size);

  return (void *) res;
}


static
void
mkey_store(void *arg, int key_index, flags_type flags,
           int use_cas, cas_type cas)
{
  I32 ax;
  struct xs_mkey_result *mkey_res;
  SV *key_sv;

  mkey_res = (struct xs_mkey_result *) arg;

  ax = mkey_res->ax;
  key_sv = ST(mkey_res->stack_offset + key_index);
  SvREFCNT_inc(key_sv);
  av_push(mkey_res->key_val, key_sv);
  if (! use_cas)
    {
      av_push(mkey_res->key_val, newRV_noinc(mkey_res->sv));
    }
  else
    {
      AV *cas_val = newAV();
      av_extend(cas_val, 1);
      av_push(cas_val, newSVuv(cas));
      av_push(cas_val, newRV_noinc(mkey_res->sv));
      av_push(mkey_res->key_val, newRV_noinc((SV *) cas_val));
    }

  av_push(mkey_res->flags, newSVuv(flags));
}


static
void
mkey_free(void *arg)
{
  struct xs_mkey_result *mkey_res;

  mkey_res = (struct xs_mkey_result *) arg;

  SvREFCNT_dec(mkey_res->sv);
}


static
void *
embedded_alloc(void *arg, value_size_type value_size)
{
  AV *av;
  SV *sv;
  char *res;

  av = (AV *) arg;

  sv = newSVpvn("", 0);
  res = SvGROW(sv, value_size + 1); /* FIXME: check OOM.  */
  res[value_size] = '\0';
  SvCUR_set(sv, value_size);
  av_push(av, sv);

  return (void *) res;
}


MODULE = Cache::Memcached::Fast		PACKAGE = Cache::Memcached::Fast::_xs


Cache_Memcached_Fast *
new(class, conf)
        char *                  class
        SV *                    conf
    PROTOTYPE: $$
    PREINIT:
        Cache_Memcached_Fast *memd;
    CODE:
        memd = client_init();
        if (! memd)
          croak("Not enough memory");
        if (! SvROK(conf) || SvTYPE(SvRV(conf)) != SVt_PVHV)
          croak("Not a hash reference");
        parse_config(memd, (HV *) SvRV(conf));
        RETVAL = memd;
    OUTPUT:
        RETVAL


void
DESTROY(memd)
        Cache_Memcached_Fast *  memd
    PROTOTYPE: $
    CODE:
        client_destroy(memd);


bool
set(memd, skey, sval, flags, ...)
        Cache_Memcached_Fast *  memd
        SV *                    skey
        Ref_SV                  sval
        U32                     flags
    ALIAS:
        add      =  CMD_ADD
        replace  =  CMD_REPLACE
        append   =  CMD_APPEND
        prepend  =  CMD_PREPEND
    PROTOTYPE: $$$$;$
    PREINIT:
        const char *key;
        STRLEN key_len;
        const void *buf;
        STRLEN buf_len;
        exptime_type exptime = 0;
        int noreply, res;
    CODE:
        if (items > 4 && SvOK(ST(4)))
          exptime = SvIV(ST(4));
        key = SvPV(skey, key_len);
        buf = (void *) SvPV(sval, buf_len);
        noreply = (GIMME_V == G_VOID);
        res = client_set(memd, ix, key, key_len, flags, exptime,
                         buf, buf_len, noreply);
        /* FIXME: use XSRETURN_{YES|NO} or even TARG.  */
        RETVAL = (res == MEMCACHED_SUCCESS);
    OUTPUT:
        RETVAL


bool
cas(memd, skey, cas, sval, flags, ...)
        Cache_Memcached_Fast *  memd
        SV *                    skey
        U32                     cas
        Ref_SV                  sval
        U32                     flags
    PROTOTYPE: $$$$$;$
    PREINIT:
        const char *key;
        STRLEN key_len;
        const void *buf;
        STRLEN buf_len;
        exptime_type exptime = 0;
        int noreply, res;
    CODE:
        if (items > 4 && SvOK(ST(4)))
          exptime = SvIV(ST(4));
        key = SvPV(skey, key_len);
        buf = (void *) SvPV(sval, buf_len);
        noreply = (GIMME_V == G_VOID);
        res = client_cas(memd, key, key_len, cas, flags, exptime,
                         buf, buf_len, noreply);
        /* FIXME: use XSRETURN_{YES|NO} or even TARG.  */
        RETVAL = (res == MEMCACHED_SUCCESS);
    OUTPUT:
        RETVAL


void
get(memd, skey)
        Cache_Memcached_Fast *  memd
        SV *                    skey
    ALIAS:
        gets  =  CMD_GETS
    PROTOTYPE: $$
    PREINIT:
        const char *key;
        STRLEN key_len;
        struct xs_skey_result skey_res;
        struct value_object object =
            { skey_alloc, skey_store, skey_free, &skey_res };
    PPCODE:
        key = SvPV(skey, key_len);
        skey_res.sv = NULL;
        client_get(memd, ix, key, key_len, &object);
        if (skey_res.sv != NULL)
          {
            dXSTARG;

            if (ix == CMD_GET)
              {
                PUSHs(sv_2mortal(newRV_noinc(skey_res.sv)));
              }
            else
              {
                AV *cas_val = newAV();
                av_extend(cas_val, 1);
                av_push(cas_val, newSVuv(skey_res.cas));
                av_push(cas_val, newRV_noinc(skey_res.sv));
                PUSHs(sv_2mortal(newRV_noinc((SV *) cas_val)));
              }
            PUSHu(skey_res.flags);
            XSRETURN(2);
          }


void
mget(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        mgets  =  CMD_GETS
    PROTOTYPE: $@
    PREINIT:
        struct xs_mkey_result mkey_res;
        struct value_object object =
            { mkey_alloc, mkey_store, mkey_free, &mkey_res };
        int key_count;
    PPCODE:
        key_count = items - 1;
        mkey_res.ax = ax;
        mkey_res.stack_offset = 1;  
        mkey_res.key_val = newAV();
        mkey_res.flags = newAV();
        av_extend(mkey_res.key_val, key_count * 2);
        av_extend(mkey_res.flags, key_count);
        if (key_count > 0)
          client_mget(memd, ix, key_count, get_key, &object);
        EXTEND(SP, 2);
        PUSHs(sv_2mortal(newRV_noinc((SV *) mkey_res.key_val)));
        PUSHs(sv_2mortal(newRV_noinc((SV *) mkey_res.flags)));
        XSRETURN(2);


void
incr(memd, skey, ...)
        Cache_Memcached_Fast *  memd
        SV *                    skey
    ALIAS:
        decr  =  CMD_DECR
    PROTOTYPE: $$;$
    PREINIT:
        const char *key;
        STRLEN key_len;
        arith_type arg = 1, result;
        int noreply, res;
    PPCODE:
        if (items > 2 && SvOK(ST(2)))
          arg = SvUV(ST(2));
        key = SvPV(skey, key_len);
        noreply = (GIMME_V == G_VOID);
        res = client_arith(memd, ix, key, key_len, arg, &result, noreply);
        if (! noreply && res == MEMCACHED_SUCCESS)
          {
            dXSTARG;

            /*
               NOTE: arith_type is at least 64 bit, but Perl UV is 32
               bit.
            */
            PUSHu(result);
            XSRETURN(1);
          }


bool
delete(memd, skey, ...)
        Cache_Memcached_Fast *  memd
        SV *                    skey
    ALIAS:
        remove  =  1
    PROTOTYPE: $$;$
    PREINIT:
        const char *key;
        STRLEN key_len;
        delay_type delay = 0;
        int noreply, res;
    CODE:
        /* Suppress warning about unused ix.  */
        if (ix) {}
        if (items > 2 && SvOK(ST(2)))
          delay = SvUV(ST(2));
        key = SvPV(skey, key_len);
        noreply = (GIMME_V == G_VOID);
        res = client_delete(memd, key, key_len, delay, noreply);
        /* FIXME: use XSRETURN_{YES|NO} or even TARG.  */
        RETVAL = (res == MEMCACHED_SUCCESS);
    OUTPUT:
        RETVAL


bool
flush_all(memd, ...)
        Cache_Memcached_Fast *  memd
    PROTOTYPE: $;$
    PREINIT:
        delay_type delay = 0;
        int noreply, res;
    CODE:
        if (items > 1 && SvOK(ST(1)))
          delay = SvUV(ST(1));
        noreply = (GIMME_V == G_VOID);
        res = client_flush_all(memd, delay, noreply);
        /* FIXME: use XSRETURN_{YES|NO} or even TARG.  */
        RETVAL = (res == MEMCACHED_SUCCESS);
    OUTPUT:
        RETVAL


AV *
server_versions(memd)
        Cache_Memcached_Fast *  memd
    PROTOTYPE: $
    PREINIT:
        struct value_object object = { embedded_alloc, NULL, NULL, NULL };
    CODE:
        RETVAL = newAV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) RETVAL);
        object.arg = RETVAL;
        client_server_versions(memd, &object);
    OUTPUT:
        RETVAL


HV *
_rvav2rvhv(array)
        AV *                    array
    PROTOTYPE: $
    PREINIT:
        I32 max_index, i;
    CODE:
        RETVAL = newHV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) RETVAL);
        max_index = av_len(array);
        if ((max_index & 1) != 1)
          croak("Even sized list expected");
        i = 0;
        while (i <= max_index)
          {
            SV **pkey, **pval;
            HE *he;

            pkey = av_fetch(array, i++, 0);
            pval = av_fetch(array, i++, 0);
            if (! (pkey && pval))
              croak("Undefined values in the list");
            SvREFCNT_inc(*pval);
            he = hv_store_ent(RETVAL, *pkey, *pval, 0);
            if (! he)
              SvREFCNT_dec(*pval);
          }
    OUTPUT:
        RETVAL
