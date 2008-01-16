/*
  Copyright (C) 2007-2008 Tomash Brechko.  All rights reserved.

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


#define F_STORABLE  0x1
#define F_COMPRESS  0x2
#define F_UTF8      0x4


struct xs_state
{
  struct client *c;
  AV *servers;
  int compress_threshold;
  double compress_ratio;
  SV *compress_method;
  SV *uncompress_method;
  SV *nfreeze_method;
  SV *thaw_method;
  int utf8;
};

typedef struct xs_state Cache_Memcached_Fast;


static
void
add_server(Cache_Memcached_Fast *memd, SV *addr_sv, double weight, int noreply)
{
  struct client *c = memd->c;
  static const int delim = ':';
  const char *host, *port;
  size_t host_len, port_len;
  STRLEN len;
  int res;

  av_push(memd->servers, newSVsv(addr_sv));

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
      res = client_add_server(c, host, host_len, port, port_len,
                              weight, noreply);
    }
  else
    {
      res = client_add_server(c, host, len, NULL, 0, weight, noreply);
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
      add_server(memd, sv, 1.0, 0);
    }
  else
    {
      switch (SvTYPE(SvRV(sv)))
        {
        case SVt_PVHV:
          {
            HV *hv = (HV *) SvRV(sv);
            SV **addr_sv, **ps;
            double weight = 1.0;
            int noreply = 0;

            addr_sv = hv_fetch(hv, "address", 7, 0);
            if (! addr_sv)
              croak("server should have { address => $addr }");
            ps = hv_fetch(hv, "weight", 6, 0);
            if (ps && SvOK(*ps))
              weight = SvNV(*ps);
            ps = hv_fetch(hv, "noreply", 7, 0);
            if (ps && SvOK(*ps))
              noreply = SvTRUE(*ps);
            add_server(memd, *addr_sv, weight, noreply);
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
            add_server(memd, *addr_sv, weight, 0);
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
parse_serialize(Cache_Memcached_Fast *memd, HV *conf)
{
  SV **ps;
  CV *cv;

  memd->utf8 = 0;

  ps = hv_fetch(conf, "utf8", 4, 0);
  if (ps && SvOK(*ps))
    memd->utf8 = SvTRUE(*ps);

  cv = get_cv("Storable::nfreeze", 0);
  if (! cv)
    croak("Can't locate Storable::nfreeze method");
  memd->nfreeze_method = (SV *) cv;

  cv = get_cv("Storable::thaw", 0);
  if (! cv)
    croak("Can't locate Storable::thaw method");
  memd->thaw_method = (SV *) cv;
}


static
void
parse_compress(Cache_Memcached_Fast *memd, HV *conf)
{
  SV **ps;

  memd->compress_threshold = -1;
  memd->compress_ratio = 0.8;
  memd->compress_method = NULL;
  memd->uncompress_method = NULL;

  ps = hv_fetch(conf, "compress_threshold", 18, 0);
  if (ps && SvOK(*ps))
    memd->compress_threshold = SvIV(*ps);

  ps = hv_fetch(conf, "compress_ratio", 14, 0);
  if (ps && SvOK(*ps))
    memd->compress_ratio = SvNV(*ps);

  ps = hv_fetch(conf, "compress_methods", 16, 0);
  if (ps && SvOK(*ps))
    {
      AV *av = (AV *) SvRV(*ps);
      memd->compress_method = newSVsv(*av_fetch(av, 0, 0));
      memd->uncompress_method = newSVsv(*av_fetch(av, 1, 0));
    }
  else if (memd->compress_threshold > 0)
    {
      warn("Compression module was not found, disabling compression");
      memd->compress_threshold = -1;
    }
}


static
void
parse_config(Cache_Memcached_Fast *memd, HV *conf)
{
  struct client *c = memd->c;
  SV **ps;

  memd->servers = newAV();

  ps = hv_fetch(conf, "ketama_points", 13, 0);
  if (ps && SvOK(*ps))
    {
      int res = client_set_ketama_points(c, SvIV(*ps));
      if (res != MEMCACHED_SUCCESS)
        croak("client_set_ketama() failed");
    }

  ps = hv_fetch(conf, "servers", 7, 0);
  if (ps && SvOK(*ps))
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
  if (ps && SvOK(*ps))
    {
      const char *ns;
      STRLEN len;
      ns = SvPV(*ps, len);
      if (client_set_prefix(c, ns, len) != MEMCACHED_SUCCESS)
        croak("Not enough memory");
    }

  ps = hv_fetch(conf, "connect_timeout", 15, 0);
  if (ps && SvOK(*ps))
    client_set_connect_timeout(c, SvNV(*ps) * 1000.0);

  ps = hv_fetch(conf, "io_timeout", 10, 0);
  if (ps && SvOK(*ps))
    client_set_io_timeout(c, SvNV(*ps) * 1000.0);

  /* For compatibility with Cache::Memcached.  */
  ps = hv_fetch(conf, "select_timeout", 14, 0);
  if (ps && SvOK(*ps))
    client_set_io_timeout(c, SvNV(*ps) * 1000.0);

  ps = hv_fetch(conf, "max_failures", 12, 0);
  if (ps && SvOK(*ps))
    client_set_max_failures(c, SvIV(*ps));

  ps = hv_fetch(conf, "failure_timeout", 15, 0);
  if (ps && SvOK(*ps))
    client_set_failure_timeout(c, SvIV(*ps));

  ps = hv_fetch(conf, "close_on_error", 14, 0);
  if (ps && SvOK(*ps))
    client_set_close_on_error(c, SvTRUE(*ps));

  ps = hv_fetch(conf, "nowait", 6, 0);
  if (ps && SvOK(*ps))
    client_set_nowait(c, SvTRUE(*ps));

  parse_compress(memd, conf);
  parse_serialize(memd, conf);
}


static inline
SV *
compress(Cache_Memcached_Fast *memd, SV *sv, flags_type *flags)
{
  if (memd->compress_threshold > 0)
    {
      STRLEN len = sv_len(sv);
      SV *csv, *bsv;
      int count;
      dSP;

      if (len < (STRLEN) memd->compress_threshold)
        return sv;

      csv = newSV(0);

      PUSHMARK(SP);
      XPUSHs(sv_2mortal(newRV(sv)));
      XPUSHs(sv_2mortal(newRV_noinc(csv)));
      PUTBACK;

      count = call_sv(memd->compress_method, G_SCALAR);

      SPAGAIN;

      if (count != 1)
        croak("Compress method returned nothing");

      bsv = POPs;
      if (SvTRUE(bsv) && sv_len(csv) <= len * memd->compress_ratio)
        {
          sv = csv;
          *flags |= F_COMPRESS;
        }

      PUTBACK;
    }

  return sv;
}


static inline
int
uncompress(Cache_Memcached_Fast *memd, SV *sv, flags_type flags)
{
  int res = 1;

  if (flags & F_COMPRESS)
    {
      SV *rsv, *bsv;
      int count;
      dSP;

      rsv = newSV(0);

      PUSHMARK(SP);
      XPUSHs(sv_2mortal(newRV(sv)));
      XPUSHs(sv_2mortal(newRV_noinc(rsv)));
      PUTBACK;

      count = call_sv(memd->uncompress_method, G_SCALAR);

      SPAGAIN;

      if (count != 1)
        croak("Uncompress method returned nothing");

      bsv = POPs;
      if (SvTRUE(bsv))
        SvSetSV(sv, rsv);
      else
        res = 0;

      PUTBACK;
    }

  return res;
}


static inline
SV *
serialize(Cache_Memcached_Fast *memd, SV *sv, flags_type *flags)
{
  if (SvROK(sv))
    {
      int count;
      dSP;

      PUSHMARK(SP);
      XPUSHs(sv);
      PUTBACK;

      count = call_sv(memd->nfreeze_method, G_SCALAR);

      SPAGAIN;

      if (count != 1)
        croak("Serialize::nfreeze returned nothing");

      sv = POPs;
      *flags |= F_STORABLE;

      PUTBACK;
    }
  else if (memd->utf8 && SvUTF8(sv))
    {
      /* Copy the value because we will modify it in place.  */
      sv = sv_2mortal(newSVsv(sv));
      sv_utf8_encode(sv);
      *flags |= F_UTF8;
    }

  return sv;
}


static inline
int
deserialize(Cache_Memcached_Fast *memd, SV *sv, flags_type flags)
{
  int res = 1;

  if (flags & F_STORABLE)
    {
      SV *rsv;
      int count;
      dSP;

      PUSHMARK(SP);
      XPUSHs(sv);
      PUTBACK;

      count = call_sv(memd->thaw_method, G_SCALAR | G_EVAL);

      SPAGAIN;

      if (count != 1)
        croak("Storable::thaw method returned nothing");

      rsv = POPs;
      if (! SvTRUE(ERRSV))
        SvSetSV(sv, rsv);
      else
        res = 0;

      PUTBACK;
    }
  else if ((flags & F_UTF8) && memd->utf8)
    {
      res = sv_utf8_decode(sv);
    }
   
  return res;
}


static
void *
alloc_value(value_size_type value_size, void **opaque)
{
  SV *sv;
  char *res;

  sv = newSVpvn("", 0);
  res = SvGROW(sv, value_size + 1); /* FIXME: check OOM.  */
  res[value_size] = '\0';
  SvCUR_set(sv, value_size);

  *opaque = sv;

  return (void *) res;
}


static
void
free_value(void *opaque)
{
  SV *sv = (SV *) opaque;

  SvREFCNT_dec(sv);
}


struct xs_value_result
{
  Cache_Memcached_Fast *memd;  
  AV *vals;
};


static
void
value_store(void *arg, void *opaque, int key_index, void *meta)
{
  SV *value_sv = (SV *) opaque;
  struct xs_value_result *value_res = (struct xs_value_result *) arg;
  struct meta_object *m = (struct meta_object *) meta;

  if (! uncompress(value_res->memd, value_sv, m->flags)
      || ! deserialize(value_res->memd, value_sv, m->flags))
    {
      free_value(value_sv);
      return;
    }

  if (! m->use_cas)
    {
      av_store(value_res->vals, key_index, value_sv);
    }
  else
    {
      AV *cas_val = newAV();
      av_extend(cas_val, 1);
      av_push(cas_val, newSVuv(m->cas));
      av_push(cas_val, value_sv);
      av_store(value_res->vals, key_index, newRV_noinc((SV *) cas_val));
    }
}


static
void
result_store(void *arg, void *opaque, int key_index, void *meta)
{
  AV *av = (AV *) arg;
  int res = (int) opaque;

  /* Suppress warning about unused opaque and meta.  */
  if (meta) {}

  if (res)
    av_store(av, key_index, newSViv(res));
  else
    av_store(av, key_index, newSVpvn("", 0));
}


static
void
embedded_store(void *arg, void *opaque, int key_index, void *meta)
{
  AV *av = (AV *) arg;
  SV *sv = (SV *) opaque;

  /* Suppress warning about unused meta.  */
  if (meta) {}

  av_store(av, key_index, sv);
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
        Newx(memd, 1, Cache_Memcached_Fast);
        memd->c = client_init();
        if (! memd->c)
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
        client_destroy(memd->c);
        if (memd->compress_method)
          {
            SvREFCNT_dec(memd->compress_method);
            SvREFCNT_dec(memd->uncompress_method);
          }
        SvREFCNT_dec(memd->servers);
        Safefree(memd);


void
enable_compress(memd, enable)
        Cache_Memcached_Fast *  memd
        bool                    enable
    PROTOTYPE: $$
    CODE:
        if (enable && ! memd->compress_method)
          warn("Compression module was not found, can't enable compression");
        else if ((memd->compress_threshold > 0) != enable)
          memd->compress_threshold = -memd->compress_threshold;


void
set(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        add      =  CMD_ADD
        replace  =  CMD_REPLACE
        append   =  CMD_APPEND
        prepend  =  CMD_PREPEND
        cas      =  CMD_CAS
    PROTOTYPE: $@
    PREINIT:
        int noreply;
        struct result_object object =
            { NULL, result_store, NULL, NULL };
        const char *key;
        STRLEN key_len;
        cas_type cas = 0;
        const void *buf;
        STRLEN buf_len;
        flags_type flags = 0;
        exptime_type exptime = 0;
        int arg = 1;
        SV *sv;
    PPCODE:
        object.arg = newAV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c);
        key = SvPV(ST(arg), key_len);
        ++arg;
        if (ix == CMD_CAS)
          {
            cas = SvUV(ST(arg));
            ++arg;
          }
        sv = ST(arg);
        ++arg;
        sv = serialize(memd, sv, &flags);
        sv = compress(memd, sv, &flags);
        buf = (void *) SvPV(sv, buf_len);
        if (items > arg)
          {
            /* exptime doesn't have to be defined.  */
            sv = ST(arg);
            if (SvOK(sv))
              exptime = SvIV(sv);
          }
        if (ix != CMD_CAS)
          {
            client_prepare_set(memd->c, ix, 0, key, key_len, flags,
                               exptime, buf, buf_len, &object, noreply);
          }
        else
          {
            client_prepare_cas(memd->c, 0, key, key_len, cas, flags,
                               exptime, buf, buf_len, &object, noreply);
          }
        client_execute(memd->c);
        if (! noreply)
          {
            SV **val = av_fetch(object.arg, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
          }

void
set_multi(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        add_multi      =  CMD_ADD
        replace_multi  =  CMD_REPLACE
        append_multi   =  CMD_APPEND
        prepend_multi  =  CMD_PREPEND
        cas_multi      =  CMD_CAS
    PROTOTYPE: $@
    PREINIT:
        int i, noreply;
        struct result_object object =
            { NULL, result_store, NULL, NULL };
    PPCODE:
        object.arg = newAV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c);
        for (i = 1; i < items; ++i)
          {
            SV *sv;
            AV *av;
            const char *key;
            STRLEN key_len;
            /*
              gcc-3.4.2 gives a warning about possibly uninitialized
              cas, so we set it to zero.
            */
            cas_type cas = 0;
            const void *buf;
            STRLEN buf_len;
            flags_type flags = 0;
            exptime_type exptime = 0;
            int arg = 0;

            sv = ST(i);
            if (! (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVAV))
              croak("Not an array reference");

            av = (AV *) SvRV(sv);
            /*
              The following values should be defined, so we do not do
              any additional checks for speed.
            */
            key = SvPV(*av_fetch(av, arg, 0), key_len);
            ++arg;
            if (ix == CMD_CAS)
              {
                cas = SvUV(*av_fetch(av, arg, 0));
                ++arg;
              }
            sv = *av_fetch(av, arg, 0);
            ++arg;
            sv = serialize(memd, sv, &flags);
            sv = compress(memd, sv, &flags);
            buf = (void *) SvPV(sv, buf_len);
            if (av_len(av) >= arg)
              {
                /* exptime doesn't have to be defined.  */
                SV **ps = av_fetch(av, arg, 0);
                if (ps && SvOK(*ps))
                  exptime = SvIV(*ps);
              }

            if (ix != CMD_CAS)
              {
                client_prepare_set(memd->c, ix, i - 1, key, key_len, flags,
                                   exptime, buf, buf_len, &object, noreply);
              }
            else
              {
                client_prepare_cas(memd->c, i - 1, key, key_len, cas, flags,
                                   exptime, buf, buf_len, &object, noreply);
              }
          }
        client_execute(memd->c);
        if (! noreply)
          {
            if (GIMME_V == G_SCALAR)
              {
                HV *hv = newHV();
                for (i = 0; i <= av_len(object.arg); ++i)
                  {
                    SV **val = av_fetch(object.arg, i, 0);
                    if (val && SvOK(*val))
                      {
                        SV *key = *av_fetch((AV *) SvRV(ST(i + 1)), 0, 0);
                        HE *he = hv_store_ent(hv, key,
                                              SvREFCNT_inc(*val), 0);
                        if (! he)
                          SvREFCNT_dec(*val);
                      }
                  }
                PUSHs(sv_2mortal(newRV_noinc((SV *) hv)));
                XSRETURN(1);
              }
            else
              {
                I32 max_index = av_len(object.arg);
                EXTEND(SP, max_index + 1);
                for (i = 0; i <= max_index; ++i)
                  {
                    SV **val = av_fetch(object.arg, i, 0);
                    if (val)
                      PUSHs(*val);
                    else
                      PUSHs(&PL_sv_undef);
                  }
                XSRETURN(max_index + 1);
              }
          }


void
get(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        gets        =  CMD_GETS
        get_multi   =  CMD_GET_MULTI
        gets_multi  =  CMD_GETS_MULTI
    PROTOTYPE: $@
    PREINIT:
        struct xs_value_result value_res;
        struct result_object object =
            { alloc_value, value_store, free_value, &value_res };
        int i, key_count;
    PPCODE:
        key_count = items - 1;
        value_res.memd = memd;
        value_res.vals = newAV();
        sv_2mortal((SV *) value_res.vals);
        av_extend(value_res.vals, key_count - 1);
        client_reset(memd->c);
        for (i = 0; i < key_count; ++i)
          {
            const char *key;
            STRLEN key_len;

            key = SvPV(ST(i + 1), key_len);
            client_prepare_get(memd->c, ix, i, key, key_len, &object);
          }
        client_execute(memd->c);
        if (ix == CMD_GET || ix == CMD_GETS)
          {
            SV **val = av_fetch(value_res.vals, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
          }
        else
          {
            HV *hv = newHV();
            for (i = 0; i <= av_len(value_res.vals); ++i)
              {
                SV **val = av_fetch(value_res.vals, i, 0);
                if (val && SvOK(*val))
                  {
                    SV *key = ST(i + 1);
                    HE *he = hv_store_ent(hv, key,
                                          SvREFCNT_inc(*val), 0);
                    if (! he)
                      SvREFCNT_dec(*val);
                  }
              }
            PUSHs(sv_2mortal(newRV_noinc((SV *) hv)));
            XSRETURN(1);
          }


void
incr(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        decr  =  CMD_DECR
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { alloc_value, embedded_store, NULL, NULL };
        int noreply;
        const char *key;
        STRLEN key_len;
        arith_type arg = 1;
    PPCODE:
        object.arg = newAV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c);
        key = SvPV(ST(1), key_len);
        if (items > 2)
          {
            /* increment doesn't have to be defined.  */
            SV *sv = ST(2);
            if (SvOK(sv))
              arg = SvUV(sv);
          }
        client_prepare_incr(memd->c, ix, 0, key, key_len, arg,
                            &object, noreply);
        client_execute(memd->c);
        if (! noreply)
          {
            SV **val = av_fetch(object.arg, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
          }


void
incr_multi(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        decr_multi  =  CMD_DECR
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { alloc_value, embedded_store, NULL, NULL };
        int i, noreply;
    PPCODE:
        object.arg = newAV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c);
        for (i = 1; i < items; ++i)
          {
            SV *sv;
            AV *av;
            const char *key;
            STRLEN key_len;
            arith_type arg = 1;

            sv = ST(i);
            if (! SvROK(sv))
              {
                key = SvPV(sv, key_len);
              }
            else
              {
                if (SvTYPE(SvRV(sv)) != SVt_PVAV)
                  croak("Not an array reference");

                av = (AV *) SvRV(sv);
                /*
                  The following values should be defined, so we do not
                  do any additional checks for speed.
                */
                key = SvPV(*av_fetch(av, 0, 0), key_len);
                if (av_len(av) >= 1)
                  {
                    /* increment doesn't have to be defined.  */
                    SV **ps = av_fetch(av, 1, 0);
                    if (ps && SvOK(*ps))
                      arg = SvUV(*ps);
                  }
              }
 
            client_prepare_incr(memd->c, ix, i - 1, key, key_len, arg,
                                &object, noreply);
          }
        client_execute(memd->c);
        if (! noreply)
          {
            if (GIMME_V == G_SCALAR)
              {
                HV *hv = newHV();
                for (i = 0; i <= av_len(object.arg); ++i)
                  {
                    SV **val = av_fetch(object.arg, i, 0);
                    if (val && SvOK(*val))
                      {
                        SV *key = *av_fetch((AV *) SvRV(ST(i + 1)), 0, 0);
                        HE *he = hv_store_ent(hv, key,
                                              SvREFCNT_inc(*val), 0);
                        if (! he)
                          SvREFCNT_dec(*val);
                      }
                  }
                PUSHs(sv_2mortal(newRV_noinc((SV *) hv)));
                XSRETURN(1);
              }
            else
              {
                I32 max_index = av_len(object.arg);
                EXTEND(SP, max_index + 1);
                for (i = 0; i <= max_index; ++i)
                  {
                    SV **val = av_fetch(object.arg, i, 0);
                    if (val)
                      PUSHs(*val);
                    else
                      PUSHs(&PL_sv_undef);
                  }
                XSRETURN(max_index + 1);
              }
          }


AV*
delete(memd, ...)
        Cache_Memcached_Fast *  memd
    ALIAS:
        remove  =  1
    PROTOTYPE: $@
    PREINIT:
        int i, noreply;
        struct result_object object =
            { NULL, result_store, NULL, NULL };
    CODE:
        /* Suppress warning about unused ix.  */
        if (ix) {}
        RETVAL = newAV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) RETVAL);
        object.arg = RETVAL;
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c);
        for (i = 1; i < items; ++i)
          {
            SV *sv;
            AV *av;
            const char *key;
            STRLEN key_len;
            delay_type delay = 0;

            sv = ST(i);
            if (! SvROK(sv))
              {
                key = SvPV(sv, key_len);
              }
            else
              {
                if (SvTYPE(SvRV(sv)) != SVt_PVAV)
                  croak("Not an array reference");

                av = (AV *) SvRV(sv);
                /*
                  The following values should be defined, so we do not
                  do any additional checks for speed.
                */
                key = SvPV(*av_fetch(av, 0, 0), key_len);
                if (av_len(av) >= 1)
                  {
                    /* exptime doesn't have to be defined.  */
                    SV **ps = av_fetch(av, 1, 0);
                    if (ps && SvOK(*ps))
                      delay = SvUV(*ps);
                  }
              }

            client_prepare_delete(memd->c, i - 1, key, key_len, delay,
                                  &object, noreply);
          }
        client_execute(memd->c);
    OUTPUT:
        RETVAL


HV *
flush_all(memd, ...)
        Cache_Memcached_Fast *  memd
    PROTOTYPE: $;$
    PREINIT:
        delay_type delay = 0;
        struct result_object object =
            { NULL, result_store, NULL, NULL };
        int noreply;
    CODE:
        RETVAL = newHV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) RETVAL);
        object.arg = sv_2mortal((SV *) newAV());
        if (items > 1 && SvOK(ST(1)))
          delay = SvUV(ST(1));
        noreply = (GIMME_V == G_VOID);
        client_flush_all(memd->c, delay, &object, noreply);
        if (! noreply)
          {
            int i;
            for (i = 0; i <= av_len(object.arg); ++i)
              {
                SV **server = av_fetch(memd->servers, i, 0);
                SV **version = av_fetch(object.arg, i, 0);
                if (version && SvOK(*version))
                  {
                    HE *he = hv_store_ent(RETVAL, *server,
                                          SvREFCNT_inc(*version), 0);
                    if (! he)
                      SvREFCNT_dec(*version);
                  }
              }
          }
    OUTPUT:
        RETVAL


void
nowait_push(memd)
        Cache_Memcached_Fast *  memd
    PROTOTYPE: $
    CODE:
        client_nowait_push(memd->c);


HV *
server_versions(memd)
        Cache_Memcached_Fast *  memd
    PROTOTYPE: $
    PREINIT:
        struct result_object object =
            { alloc_value, embedded_store, NULL, NULL };
        int i;
    CODE:
        RETVAL = newHV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) RETVAL);
        object.arg = sv_2mortal((SV *) newAV());
        client_server_versions(memd->c, &object);
        for (i = 0; i <= av_len(object.arg); ++i)
          {
            SV **server = av_fetch(memd->servers, i, 0);
            SV **version = av_fetch(object.arg, i, 0);
            if (version && SvOK(*version))
              {
                HE *he = hv_store_ent(RETVAL, *server,
                                      SvREFCNT_inc(*version), 0);
                if (! he)
                  SvREFCNT_dec(*version);
              }
          }
    OUTPUT:
        RETVAL


HV *
_rvav2rvhv(keys, vals)
        AV *                    keys
        AV *                    vals
    PROTOTYPE: $
    PREINIT:
        I32 max_index, i;
    CODE:
        RETVAL = newHV();
        /* Why sv_2mortal() is needed is explained in perlxs.  */
        sv_2mortal((SV *) RETVAL);
        max_index = av_len(vals);
        for (i = 0; i <= max_index; ++i)
          {
            SV **pkey, **pval;
            HE *he;

            pval = av_fetch(vals, i, 0);
            if (! (pval && SvOK(*pval)))
              continue;

            pkey = av_fetch(keys, i, 0);
            if (! pkey)
              croak("Undefined key in the list");

            he = hv_store_ent(RETVAL, *pkey, SvREFCNT_inc(*pval), 0);
            if (! he)
              SvREFCNT_dec(*pval);
          }
    OUTPUT:
        RETVAL
