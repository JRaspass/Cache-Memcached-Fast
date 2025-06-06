/*
  Copyright (C) 2007-2010 Tomash Brechko.  All rights reserved.

  This library is free software; you can redistribute it and/or modify
  it under the same terms as Perl itself, either Perl version 5.8.8
  or, at your option, any later version of Perl 5 you may have
  available.
*/

#define PERL_NO_GET_CONTEXT
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


typedef struct
{
  struct client *c;
  AV *servers;
  int compress_threshold;
  double compress_ratio;
  SV *compress_method;
  SV *decompress_method;
  SV *serialize_method;
  SV *deserialize_method;
  int utf8;
  size_t max_size;
} Cache_Memcached_Fast;

static inline
SV**
safe_av_fetch(pTHX_ AV *av, SSize_t key, I32 lval)
{
  SV ** v = av_fetch(av, key, lval);
  if ( !v || !SvOK(*v) )
    croak("undefined value passed to av_fetch");

  return v;
}

static
void
add_server(pTHX_ Cache_Memcached_Fast *memd, SV *addr_sv,
           double weight, int noreply)
{
  struct client *c = memd->c;
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
  port = strrchr(host, ':');
  if (port)
    {
      host_len = port++ - host;
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
parse_server(pTHX_ Cache_Memcached_Fast *memd, SV *sv)
{
  if (! SvROK(sv))
    {
      add_server(aTHX_ memd, sv, 1.0, 0);
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

            addr_sv = hv_fetchs(hv, "address", 0);
            if (addr_sv)
              SvGETMAGIC(*addr_sv);
            else
              croak("server should have { address => $addr }");
            ps = hv_fetchs(hv, "weight", 0);
            if (ps)
              SvGETMAGIC(*ps);
            if (ps && SvOK(*ps))
              weight = SvNV(*ps);
            ps = hv_fetchs(hv, "noreply", 0);
            if (ps)
              noreply = SvTRUE(*ps);
            add_server(aTHX_ memd, *addr_sv, weight, noreply);
          }
          break;

        case SVt_PVAV:
          {
            AV *av = (AV *) SvRV(sv);
            SV **addr_sv, **weight_sv;
            double weight = 1.0;

            addr_sv = av_fetch(av, 0, 0);
            if (addr_sv)
              SvGETMAGIC(*addr_sv);
            else
              croak("server should be [$addr, $weight]");
            weight_sv = av_fetch(av, 1, 0);
            if (weight_sv)
              weight = SvNV(*weight_sv);
            add_server(aTHX_ memd, *addr_sv, weight, 0);
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
parse_serialize(pTHX_ Cache_Memcached_Fast *memd, HV *conf)
{
  SV **ps;

  memd->utf8 = 0;
  memd->serialize_method = NULL;
  memd->deserialize_method = NULL;

  ps = hv_fetchs(conf, "utf8", 0);
  if (ps)
    memd->utf8 = SvTRUE(*ps);

  ps = hv_fetchs(conf, "serialize_methods", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    {
      AV *av = (AV *) SvRV(*ps);
      memd->serialize_method = newSVsv(*safe_av_fetch(aTHX_ av, 0, 0));
      memd->deserialize_method = newSVsv(*safe_av_fetch(aTHX_ av, 1, 0));
    }

  if (! memd->serialize_method)
    croak("Serialize method is not specified");

  if (! memd->deserialize_method)
    croak("Deserialize method is not specified");
}


static
void
parse_compress(pTHX_ Cache_Memcached_Fast *memd, HV *conf)
{
  SV **ps;

  memd->compress_threshold = -1;
  memd->compress_ratio = 0.8;
  memd->compress_method = NULL;
  memd->decompress_method = NULL;

  ps = hv_fetchs(conf, "compress_threshold", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    memd->compress_threshold = SvIV(*ps);

  ps = hv_fetchs(conf, "compress_ratio", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    memd->compress_ratio = SvNV(*ps);

  ps = hv_fetchs(conf, "compress_methods", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    {
      AV *av = (AV *) SvRV(*ps);
      memd->compress_method = newSVsv(*safe_av_fetch(aTHX_ av, 0, 0));
      memd->decompress_method = newSVsv(*safe_av_fetch(aTHX_ av, 1, 0));
    }
  else if (memd->compress_threshold > 0)
    {
      warn("Compression module was not found, disabling compression");
      memd->compress_threshold = -1;
    }
}


static
void
parse_config(pTHX_ Cache_Memcached_Fast *memd, HV *conf)
{
  struct client *c = memd->c;
  SV **ps;

  memd->servers = newAV();

  ps = hv_fetchs(conf, "ketama_points", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    {
      int res = client_set_ketama_points(c, SvIV(*ps));
      if (res != MEMCACHED_SUCCESS)
        croak("client_set_ketama() failed");
    }

  ps = hv_fetchs(conf, "hash_namespace", 0);
  if (ps)
    client_set_hash_namespace(c, SvTRUE(*ps));

  ps = hv_fetchs(conf, "servers", 0);
  if (ps)
    SvGETMAGIC(*ps);
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

          SvGETMAGIC(*ps);
          parse_server(aTHX_ memd, *ps);
        }
    }

  ps = hv_fetchs(conf, "namespace", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    {
      const char *ns;
      STRLEN len;
      ns = SvPV(*ps, len);
      if (client_set_prefix(c, ns, len) != MEMCACHED_SUCCESS)
        croak("Not enough memory");
    }

  ps = hv_fetchs(conf, "connect_timeout", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    client_set_connect_timeout(c, SvNV(*ps) * 1000.0);

  ps = hv_fetchs(conf, "io_timeout", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    client_set_io_timeout(c, SvNV(*ps) * 1000.0);

  /* For compatibility with Cache::Memcached.  */
  ps = hv_fetchs(conf, "select_timeout", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    client_set_io_timeout(c, SvNV(*ps) * 1000.0);

  ps = hv_fetchs(conf, "max_failures", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    client_set_max_failures(c, SvIV(*ps));

  ps = hv_fetchs(conf, "failure_timeout", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    client_set_failure_timeout(c, SvIV(*ps));

  ps = hv_fetchs(conf, "close_on_error", 0);
  if (ps)
    client_set_close_on_error(c, SvTRUE(*ps));

  ps = hv_fetchs(conf, "nowait", 0);
  if (ps)
    client_set_nowait(c, SvTRUE(*ps));

  ps = hv_fetchs(conf, "max_size", 0);
  if (ps)
    SvGETMAGIC(*ps);
  if (ps && SvOK(*ps))
    memd->max_size = SvUV(*ps);
  else
    memd->max_size = 1024 * 1024;

  parse_compress(aTHX_ memd, conf);
  parse_serialize(aTHX_ memd, conf);
}


static inline
SV *
compress(pTHX_ Cache_Memcached_Fast *memd, SV *sv, flags_type *flags)
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
      mXPUSHs(newRV_inc(sv));
      mXPUSHs(newRV_noinc(csv));
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
decompress(pTHX_ Cache_Memcached_Fast *memd, SV **sv, flags_type flags)
{
  int res = 1;

  if (flags & F_COMPRESS)
    {
      SV *rsv, *bsv;
      int count;
      dSP;

      rsv = newSV(0);

      PUSHMARK(SP);
      mXPUSHs(newRV_inc(*sv));
      mXPUSHs(newRV_inc(rsv));
      PUTBACK;

      count = call_sv(memd->decompress_method, G_SCALAR);

      SPAGAIN;

      if (count != 1)
        croak("Decompress method returned nothing");

      bsv = POPs;
      if (SvTRUE(bsv))
        {
          SvREFCNT_dec(*sv);
          *sv = rsv;
        }
      else
        {
          SvREFCNT_dec(rsv);
          res = 0;
        }

      PUTBACK;
    }

  return res;
}


static inline
SV *
serialize(pTHX_ Cache_Memcached_Fast *memd, SV *sv, flags_type *flags)
{
  if (SvROK(sv))
    {
      int count;
      dSP;

      PUSHMARK(SP);
      XPUSHs(sv);
      PUTBACK;

      count = call_sv(memd->serialize_method, G_SCALAR);

      SPAGAIN;

      if (count != 1)
        croak("Serialize method returned nothing");

      sv = POPs;
      *flags |= F_STORABLE;

      PUTBACK;
    }
  else if (SvUTF8(sv))
    {
      /* Copy the value because we will modify it in place.  */
      sv = sv_2mortal(newSVsv(sv));
      if (memd->utf8)
        {
          sv_utf8_encode(sv);
          *flags |= F_UTF8;
        }
      else
        {
          sv_utf8_downgrade(sv, 0);
        }
    }

  return sv;
}


static inline
int
deserialize(pTHX_ Cache_Memcached_Fast *memd, SV **sv, flags_type flags)
{
  int res = 1;

  if (flags & F_STORABLE)
    {
      SV *rsv;
      int count;
      dSP;

      PUSHMARK(SP);
      XPUSHs(*sv);
      PUTBACK;

      /* FIXME: do we need G_KEPEERR here?  */
      count = call_sv(memd->deserialize_method, G_SCALAR | G_EVAL);

      SPAGAIN;

      if (count != 1)
        croak("Deserialize method returned nothing");

      rsv = POPs;
      if (! SvTRUE(ERRSV))
        {
          SvREFCNT_dec(*sv);
          *sv = SvREFCNT_inc(rsv);
        }
      else
        {
          res = 0;
        }

      PUTBACK;
    }
  else if ((flags & F_UTF8) && memd->utf8)
    {
      res = sv_utf8_decode(*sv);
    }
   
  return res;
}


static
void *
alloc_value(value_size_type value_size, void **opaque)
{
  dTHX;
  SV *sv;
  char *res;

  sv = newSVpvs("");
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
  dTHX;
  SV *sv = (SV *) opaque;

  SvREFCNT_dec(sv);
}


struct xs_value_result
{
  Cache_Memcached_Fast *memd;  
  SV *vals;
};


static
void
svalue_store(void *arg, void *opaque, int key_index PERL_UNUSED_DECL, void *meta)
{
  dTHX;
  SV *value_sv = (SV *) opaque;
  struct xs_value_result *value_res = (struct xs_value_result *) arg;
  struct meta_object *m = (struct meta_object *) meta;

  if (! decompress(aTHX_ value_res->memd, &value_sv, m->flags)
      || ! deserialize(aTHX_ value_res->memd, &value_sv, m->flags))
    {
      free_value(value_sv);
      return;
    }

  if (! m->use_cas)
    {
      value_res->vals = value_sv;
    }
  else
    {
      AV *cas_val = newAV();
      av_extend(cas_val, 1);
      av_push(cas_val, newSVuv(m->cas));
      av_push(cas_val, value_sv);
      value_res->vals = newRV_noinc((SV *) cas_val);
    }
}


static
void
mvalue_store(void *arg, void *opaque, int key_index, void *meta)
{
  dTHX;
  SV *value_sv = (SV *) opaque;
  struct xs_value_result *value_res = (struct xs_value_result *) arg;
  struct meta_object *m = (struct meta_object *) meta;

  if (! decompress(aTHX_ value_res->memd, &value_sv, m->flags)
      || ! deserialize(aTHX_ value_res->memd, &value_sv, m->flags))
    {
      free_value(value_sv);
      return;
    }

  if (! m->use_cas)
    {
      av_store((AV *) value_res->vals, key_index, value_sv);
    }
  else
    {
      AV *cas_val = newAV();
      av_extend(cas_val, 1);
      av_push(cas_val, newSVuv(m->cas));
      av_push(cas_val, value_sv);
      av_store((AV *) value_res->vals, key_index, newRV_noinc((SV *) cas_val));
    }
}


static
void
result_store(void *arg, void *opaque, int key_index, void *meta PERL_UNUSED_DECL)
{
  dTHX;
  AV *av = (AV *) arg;
  int res = (ptrdiff_t) opaque;

  av_store(av, key_index, res ? newSViv(res) : newSVpvs(""));
}


static
void
embedded_store(void *arg, void *opaque, int key_index, void *meta PERL_UNUSED_DECL)
{
  dTHX;
  AV *av = (AV *) arg;
  SV *sv = (SV *) opaque;

  av_store(av, key_index, sv);
}


/*
  When SvPV() is called on a magic SV the result of mg_get() is cached
  in PV slot.  Since we pass around pointers to this storage we have
  to avoid value refetch and reallocation that would happen if
  mg_get() is called again.  Because any magic SV may be put to the
  argument list more than once we create a temporal copies of them,
  thus braking possible ties and ensuring that every argument is
  fetched exactly once.
*/
static inline
char *
SvPV_stable_storage(pTHX_ SV *sv, STRLEN *lp)
{
  if (SvGAMAGIC(sv))
    sv = sv_2mortal(newSVsv(sv));

  return SvPV(sv, *lp);
}


MODULE = Cache::Memcached::Fast		PACKAGE = Cache::Memcached::Fast


TYPEMAP: <<TYPEMAP
Cache_Memcached_Fast * T_CACHE_MEMCACHED_FAST

INPUT
T_CACHE_MEMCACHED_FAST
  $var = INT2PTR($type, SvIVX(SvRV($arg)));

OUTPUT
T_CACHE_MEMCACHED_FAST
  sv_setref_pv($arg, class, (void *) $var);

TYPEMAP


Cache_Memcached_Fast *
_new(char *class, SV *conf)
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
        parse_config(aTHX_ memd, (HV *) SvRV(conf));
        RETVAL = memd;
    OUTPUT:
        RETVAL


void
_destroy(Cache_Memcached_Fast *memd)
    PROTOTYPE: $
    CODE:
        client_destroy(memd->c);
        if (memd->compress_method)
          {
            SvREFCNT_dec(memd->compress_method);
            SvREFCNT_dec(memd->decompress_method);
          }
        if (memd->serialize_method)
          {
            SvREFCNT_dec(memd->serialize_method);
            SvREFCNT_dec(memd->deserialize_method);
          }
        SvREFCNT_dec(memd->servers);
        Safefree(memd);


void
_weaken(SV *sv)
    PROTOTYPE: $
    CODE:
        sv_rvweaken(sv);


void
enable_compress(Cache_Memcached_Fast *memd, bool enable)
    PROTOTYPE: $$
    CODE:
        if (enable && ! memd->compress_method)
          warn("Compression module was not found, can't enable compression");
        else if ((memd->compress_threshold > 0) != enable)
          memd->compress_threshold = -memd->compress_threshold;


void
set(Cache_Memcached_Fast *memd, ...)
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
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
        key = SvPV_stable_storage(aTHX_ ST(arg), &key_len);
        ++arg;
        if (ix == CMD_CAS)
          {
            cas = SvUV(ST(arg));
            ++arg;
          }
        sv = ST(arg);
        ++arg;
        sv = serialize(aTHX_ memd, sv, &flags);
        sv = compress(aTHX_ memd, sv, &flags);
        buf = (void *) SvPV_stable_storage(aTHX_ sv, &buf_len);
        if (buf_len > memd->max_size)
          XSRETURN_EMPTY;
        if (items > arg)
          {
            /* exptime doesn't have to be defined.  */
            sv = ST(arg);
            SvGETMAGIC(sv);
            if (SvOK(sv))
              exptime = SvIV(sv);
          }
        if (ix != CMD_CAS)
          {
            client_prepare_set(memd->c, ix, 0, key, key_len, flags,
                               exptime, buf, buf_len);
          }
        else
          {
            client_prepare_cas(memd->c, 0, key, key_len, cas, flags,
                               exptime, buf, buf_len);
          }
        client_execute(memd->c, 2);
        if (! noreply)
          {
            SV **val = av_fetch(object.arg, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
            XSRETURN_EMPTY;
          }


void
set_multi(Cache_Memcached_Fast *memd, ...)
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
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
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
            key = SvPV_stable_storage(aTHX_ *safe_av_fetch(aTHX_ av, arg, 0), &key_len);
            ++arg;
            if (ix == CMD_CAS)
              {
                cas = SvUV(*safe_av_fetch(aTHX_ av, arg, 0));
                ++arg;
              }
            sv = *safe_av_fetch(aTHX_ av, arg, 0);
            ++arg;
            sv = serialize(aTHX_ memd, sv, &flags);
            sv = compress(aTHX_ memd, sv, &flags);
            buf = (void *) SvPV_stable_storage(aTHX_ sv, &buf_len);
            if (buf_len > memd->max_size)
              continue;
            if (av_len(av) >= arg)
              {
                /* exptime doesn't have to be defined.  */
                SV **ps = av_fetch(av, arg, 0);
                if (ps)
                  SvGETMAGIC(*ps);
                if (ps && SvOK(*ps))
                  exptime = SvIV(*ps);
              }

            if (ix != CMD_CAS)
              {
                client_prepare_set(memd->c, ix, i - 1, key, key_len, flags,
                                   exptime, buf, buf_len);
              }
            else
              {
                client_prepare_cas(memd->c, i - 1, key, key_len, cas, flags,
                                   exptime, buf, buf_len);
              }
          }
        client_execute(memd->c, 2);
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
                mPUSHs(newRV_noinc((SV *) hv));
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
get(Cache_Memcached_Fast *memd, ...)
    ALIAS:
        gets        =  CMD_GETS
    PROTOTYPE: $@
    PREINIT:
        struct xs_value_result value_res;
        struct result_object object =
            { alloc_value, svalue_store, free_value, &value_res };
        const char *key;
        STRLEN key_len;
    PPCODE:
        value_res.memd = memd;
        value_res.vals = NULL;
        client_reset(memd->c, &object, 0);
        key = SvPV(ST(1), key_len);
        client_prepare_get(memd->c, ix, 0, key, key_len);
        client_execute(memd->c, 2);
        if (value_res.vals)
          {
            mPUSHs(value_res.vals);
            XSRETURN(1);
          }
        XSRETURN_EMPTY;


void
get_multi(Cache_Memcached_Fast *memd, ...)
    ALIAS:
        gets_multi  =  CMD_GETS
    PROTOTYPE: $@
    PREINIT:
        struct xs_value_result value_res;
        struct result_object object =
            { alloc_value, mvalue_store, free_value, &value_res };
        int i, key_count;
        HV *hv;
    PPCODE:
        key_count = items - 1;
        value_res.memd = memd;
        value_res.vals = (SV *) newAV();
        sv_2mortal(value_res.vals);
        av_extend((AV *) value_res.vals, key_count - 1);
        client_reset(memd->c, &object, 0);
        for (i = 0; i < key_count; ++i)
          {
            const char *key;
            STRLEN key_len;

            key = SvPV_stable_storage(aTHX_ ST(i + 1), &key_len);
            client_prepare_get(memd->c, ix, i, key, key_len);
          }
        client_execute(memd->c, 2);
        hv = newHV();
        for (i = 0; i <= av_len((AV *) value_res.vals); ++i)
          {
            SV **val = av_fetch((AV *) value_res.vals, i, 0);
            if (val && SvOK(*val))
              {
                SV *key = ST(i + 1);
                HE *he = hv_store_ent(hv, key,
                                      SvREFCNT_inc(*val), 0);
                if (! he)
                  SvREFCNT_dec(*val);
              }
          }
        mPUSHs(newRV_noinc((SV *) hv));
        XSRETURN(1);


void
gat(Cache_Memcached_Fast *memd, ...)
    ALIAS:
        gats = CMD_GATS
    PROTOTYPE: $@
    PREINIT:
        struct xs_value_result value_res;
        struct result_object object =
            { alloc_value, svalue_store, free_value, &value_res };
        const char *key;
        STRLEN key_len;
        const char *exptime = "0";
        STRLEN exptime_len = 1;
        SV *sv;
    PPCODE:
        value_res.memd = memd;
        value_res.vals = NULL;
        client_reset(memd->c, &object, 0);
        sv = ST(1);
        SvGETMAGIC(sv);
        if (SvOK(sv))
          exptime = SvPV(sv, exptime_len);
        key = SvPV(ST(2), key_len);
        client_prepare_gat(memd->c, ix, 0, key, key_len, exptime, exptime_len);
        client_execute(memd->c, 4);
        if (value_res.vals)
          {
            mPUSHs(value_res.vals);
            XSRETURN(1);
          }
        XSRETURN_EMPTY;

void
gat_multi(Cache_Memcached_Fast *memd, ...)
    ALIAS:
        gats_multi = CMD_GATS
    PROTOTYPE: $@
    PREINIT:
        struct xs_value_result value_res;
        struct result_object object =
            { alloc_value, mvalue_store, free_value, &value_res };
        int i, key_count;
        HV *hv;
        SV *sv;
        const char *exptime = "0";
        STRLEN exptime_len = 1;
    PPCODE:
        key_count = items - 2;
        value_res.memd = memd;
        value_res.vals = (SV *) newAV();
        sv_2mortal(value_res.vals);
        if (key_count > 1)
          av_extend((AV *) value_res.vals, key_count - 1);
        client_reset(memd->c, &object, 0);
        sv = ST(1);
        SvGETMAGIC(sv);
        if (SvOK(sv))
          exptime = SvPV(sv, exptime_len);
        for (i = 0; i < key_count; ++i)
          {
            const char *key;
            STRLEN key_len;
            key = SvPV_stable_storage(aTHX_ ST(i + 2), &key_len);
            client_prepare_gat(memd->c, ix, i, key, key_len, exptime, exptime_len);
          }
        client_execute(memd->c, 4);
        hv = newHV();
        for (i = 0; i <= av_len((AV *) value_res.vals); ++i)
          {
            SV **val = av_fetch((AV *) value_res.vals, i, 0);
            if (val && SvOK(*val))
              {
                SV *key = ST(i + 2);
                HE *he = hv_store_ent(hv, key,
                                      SvREFCNT_inc(*val), 0);
                if (! he)
                  SvREFCNT_dec(*val);
              }
          }
        mPUSHs(newRV_noinc((SV *) hv));
        XSRETURN(1);


void
incr(Cache_Memcached_Fast *memd, ...)
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
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
        key = SvPV_stable_storage(aTHX_ ST(1), &key_len);
        if (items > 2)
          {
            /* increment doesn't have to be defined.  */
            SV *sv = ST(2);
            SvGETMAGIC(sv);
            if (SvOK(sv))
              arg = SvUV(sv);
          }
        client_prepare_incr(memd->c, ix, 0, key, key_len, arg);
        client_execute(memd->c, 2);
        if (! noreply)
          {
            SV **val = av_fetch(object.arg, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
            XSRETURN_EMPTY;
          }


void
incr_multi(Cache_Memcached_Fast *memd, ...)
    ALIAS:
        decr_multi  =  CMD_DECR
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { alloc_value, embedded_store, NULL, NULL };
        int i, noreply;
    PPCODE:
        object.arg = newAV();
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
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
                key = SvPV_stable_storage(aTHX_ sv, &key_len);
              }
            else
              {
                if (SvTYPE(SvRV(sv)) != SVt_PVAV)
                  croak("Not an array reference");

                av = (AV *) SvRV(sv);
                key = SvPV_stable_storage(aTHX_ *safe_av_fetch(aTHX_ av, 0, 0), &key_len);
                if (av_len(av) >= 1)
                  {
                    /* increment doesn't have to be defined.  */
                    SV **ps = av_fetch(av, 1, 0);
                    if (ps)
                      SvGETMAGIC(*ps);
                    if (ps && SvOK(*ps))
                      arg = SvUV(*ps);
                  }
              }
 
            client_prepare_incr(memd->c, ix, i - 1, key, key_len, arg);
          }
        client_execute(memd->c, 2);
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
                        SV *key;
                        HE *he;

                        key = ST(i + 1);
                        if (SvROK(key))
                          key = *av_fetch((AV *) SvRV(key), 0, 0);

                        he = hv_store_ent(hv, key, SvREFCNT_inc(*val), 0);
                        if (! he)
                          SvREFCNT_dec(*val);
                      }
                  }
                mPUSHs(newRV_noinc((SV *) hv));
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
delete(Cache_Memcached_Fast *memd, ...)
    ALIAS:
        remove = CMD_REMOVE
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { NULL, result_store, NULL, NULL };
        int noreply;
        const char *key;
        STRLEN key_len;
    PPCODE:
        PERL_UNUSED_ARG(ix);
        object.arg = newAV();
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
        key = SvPV_stable_storage(aTHX_ ST(1), &key_len);
        if (items > 2)
          {
            /* Compatibility with old (key, delay) syntax.  */

            /* delay doesn't have to be defined.  */
            SV *sv = ST(2);
            SvGETMAGIC(sv);
            if (SvOK(sv) && SvUV(sv) != 0)
              warn("non-zero delete expiration time is ignored");
          }
        client_prepare_delete(memd->c, 0, key, key_len);
        client_execute(memd->c, 2);
        if (! noreply)
          {
            SV **val = av_fetch(object.arg, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
            XSRETURN_EMPTY;
          }


void
delete_multi(Cache_Memcached_Fast *memd, ...)
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { NULL, result_store, NULL, NULL };
        int i, noreply;
    PPCODE:
        object.arg = newAV();
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
        for (i = 1; i < items; ++i)
          {
            SV *sv;
            const char *key;
            STRLEN key_len;

            sv = ST(i);
            if (! SvROK(sv))
              {
                key = SvPV_stable_storage(aTHX_ sv, &key_len);
              }
            else
              {
                /* Compatibility with old [key, delay] syntax.  */

                AV *av;

                if (SvTYPE(SvRV(sv)) != SVt_PVAV)
                  croak("Not an array reference");

                av = (AV *) SvRV(sv);
                key = SvPV_stable_storage(aTHX_ *safe_av_fetch(aTHX_ av, 0, 0), &key_len);
                if (av_len(av) >= 1)
                  {
                    /* delay doesn't have to be defined.  */
                    SV **ps = av_fetch(av, 1, 0);
                    if (ps)
                      SvGETMAGIC(*ps);
                    if (ps && SvOK(*ps) && SvUV(*ps) != 0)
                      warn("non-zero delete expiration time is ignored");
                  }
              }
 
            client_prepare_delete(memd->c, i - 1, key, key_len);
          }
        client_execute(memd->c, 2);
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
                        SV *key;
                        HE *he;

                        key = ST(i + 1);
                        if (SvROK(key))
                          key = *av_fetch((AV *) SvRV(key), 0, 0);

                        he = hv_store_ent(hv, key, SvREFCNT_inc(*val), 0);
                        if (! he)
                          SvREFCNT_dec(*val);
                      }
                  }
                mPUSHs(newRV_noinc((SV *) hv));
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
touch(Cache_Memcached_Fast *memd, ...)
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { NULL, result_store, NULL, NULL };
        int noreply;
        const char *key;
        STRLEN key_len;
        exptime_type exptime = 0;
        SV *sv;
    PPCODE:
        object.arg = newAV();
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
        key = SvPV_stable_storage(aTHX_ ST(1), &key_len);
        if (items > 2)
          {
            /* exptime doesn't have to be defined.  */
            sv = ST(2);
            SvGETMAGIC(sv);
            if (SvOK(sv))
              exptime = SvIV(sv);
          }
        client_prepare_touch(memd->c, 0, key, key_len, exptime);
        client_execute(memd->c, 2);
        if (! noreply)
          {
            SV **val = av_fetch(object.arg, 0, 0);
            if (val)
              {
                PUSHs(*val);
                XSRETURN(1);
              }
            XSRETURN_EMPTY;
          }


void
touch_multi(Cache_Memcached_Fast *memd, ...)
    PROTOTYPE: $@
    PREINIT:
        struct result_object object =
            { NULL, result_store, NULL, NULL };
        int i, noreply;
    PPCODE:
        object.arg = newAV();
        sv_2mortal((SV *) object.arg);
        noreply = (GIMME_V == G_VOID);
        client_reset(memd->c, &object, noreply);
        for (i = 1; i < items; ++i)
          {
            SV *sv;
            AV *av;
            const char *key;
            STRLEN key_len;
            exptime_type exptime = 0;
            int arg = 0;

            sv = ST(i);
            if (! (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVAV))
              croak("Not an array reference");

            av = (AV *) SvRV(sv);
            key = SvPV_stable_storage(aTHX_ *safe_av_fetch(aTHX_ av, arg, 0), &key_len);
            ++arg;

            if (av_len(av) >= 1)
              {
                /* exptime doesn't have to be defined.  */
                SV **ps = av_fetch(av, arg, 0);
                if (ps)
                  SvGETMAGIC(*ps);
                if (ps && SvOK(*ps))
                  exptime = SvIV(*ps);
              }

            client_prepare_touch(memd->c, i - 1, key, key_len, exptime);
          }
        client_execute(memd->c, 2);
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
                        SV *key;
                        HE *he;

                        key = ST(i + 1);
                        if (SvROK(key))
                          key = *av_fetch((AV *) SvRV(key), 0, 0);

                        he = hv_store_ent(hv, key, SvREFCNT_inc(*val), 0);
                        if (! he)
                          SvREFCNT_dec(*val);
                      }
                  }
                mPUSHs(newRV_noinc((SV *) hv));
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


HV *
flush_all(Cache_Memcached_Fast *memd, ...)
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
        if (items > 1)
          {
            SV *sv = ST(1);
            SvGETMAGIC(sv);
            if (SvOK(sv))
              delay = SvUV(sv);
          }
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
nowait_push(Cache_Memcached_Fast *memd)
    PROTOTYPE: $
    CODE:
        client_nowait_push(memd->c);


HV *
server_versions(Cache_Memcached_Fast *memd)
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


SV *
namespace(Cache_Memcached_Fast *memd, ...)
    PROTOTYPE: $;$
    PREINIT:
        const char *ns;
        size_t len;
    CODE:
        ns = client_get_prefix(memd->c, &len);
        RETVAL = newSVpv(ns, len);
        if (items > 1)
          {
            ns = SvPV(ST(1), len);
            if (client_set_prefix(memd->c, ns, len) != MEMCACHED_SUCCESS)
              croak("Not enough memory");
          }
    OUTPUT:
        RETVAL


void
disconnect_all(Cache_Memcached_Fast *memd)
    PROTOTYPE: $
    CODE:
        client_reinit(memd->c);
