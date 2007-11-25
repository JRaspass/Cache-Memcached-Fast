#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


#include "src/client.h"
#include <stdlib.h>
#include <string.h>


typedef struct client Cache_Memcached1;


static
void
parse_config(Cache_Memcached1 *memd, HV *conf)
{
  SV **ps;

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
          static const int delim = ':';
          const char *host, *port;
          size_t host_len, port_len;
          STRLEN len;

          ps = av_fetch(a, i, 0);
          if (! ps)
            continue;
          /* TODO: parse [host, weight].  */
          host = SvPV(*ps, len);
          /*
            NOTE: here we relay on the fact that host is zero-terminated.
          */
          port = strrchr(host, delim);
          if (! port)
            croak("Servers should be specified as 'host:port'");
          host_len = port - host;
          ++port;
          port_len = len - host_len - 1;
          if (client_add_server(memd, host, host_len, port, port_len) != 0)
            croak("Not enough memory");
        }
    }

  ps = hv_fetch(conf, "namespace", 9, 0);
  if (ps)
    {
      const char *ns;
      STRLEN len;
      ns = SvPV(*ps, len);
      if (client_set_namespace(memd, ns, len) != 0)
        croak("Not enough memory");
    }

  ps = hv_fetch(conf, "connect_timeout", 15, 0);
  if (ps)
    {
      client_set_connect_timeout(memd, SvNV(*ps) * 1000.0);
    }

  ps = hv_fetch(conf, "select_timeout", 14, 0);
  if (ps)
    {
      client_set_io_timeout(memd, SvNV(*ps) * 1000.0);
    }

  ps = hv_fetch(conf, "close_on_error", 14, 0);
  if (ps)
    {
      client_set_close_on_error(memd, SvTRUE(*ps));
    }
}


struct xs_skey_result
{
  SV *sv;
  flags_type flags;
};


static
void *
skey_alloc(void *arg, int key_index, flags_type flags, size_t value_size)
{
  struct xs_skey_result *skey_res;
  char *res;

  skey_res = (struct xs_skey_result *) arg;

  skey_res->flags = flags;
  skey_res->sv = newSVpvn("", 0);
  res = SvGROW(skey_res->sv, value_size + 1); /* FIXME: check OOM.  */
  res[value_size] = '\0';
  SvCUR_set(skey_res->sv, value_size);

  return (void *) res;
}


struct xs_mkey_result
{
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
mkey_alloc(void *arg, int key_index, flags_type flags, size_t value_size)
{
  I32 ax;
  struct xs_mkey_result *mkey_res;
  SV *key_sv, *val_sv;
  char *res;

  mkey_res = (struct xs_mkey_result *) arg;

  ax = mkey_res->ax;
  key_sv = ST(mkey_res->stack_offset + key_index);
  SvREFCNT_inc(key_sv);
  av_push(mkey_res->key_val, key_sv);

  val_sv = newSVpvn("", 0);
  res = SvGROW(val_sv, value_size + 1); /* FIXME: check OOM.  */
  res[value_size] = '\0';
  SvCUR_set(val_sv, value_size);
  av_push(mkey_res->key_val, val_sv);

  av_push(mkey_res->flags, newSVuv(flags));

  return (void *) res;
}


MODULE = Cache::Memcached1		PACKAGE = Cache::Memcached1


Cache_Memcached1 *
new(class, conf)
        const char *  class
        SV *          conf
    PROTOTYPE: $$
    PREINIT:
        Cache_Memcached1 *memd;
    CODE:
        New(0, memd, 1, Cache_Memcached1); /* FIXME: check OOM.  */
        client_init(memd);
        if (! SvROK(conf) || SvTYPE(SvRV(conf)) != SVt_PVHV)
          croak("Not a hash reference");
        parse_config(memd, (HV *) SvRV(conf));
        RETVAL = memd;
    OUTPUT:
        RETVAL


void
DESTROY(memd)
        Cache_Memcached1 *  memd
    PROTOTYPE: $
    CODE:
        client_destroy(memd);
        Safefree(memd);


bool
set(memd, skey, sval, ...)
        Cache_Memcached1 *  memd
        SV *                skey
        SV *                sval
    PROTOTYPE: $$$;$$
    PREINIT:
        const char *key;
        STRLEN key_len;
        unsigned int flags = 0;
        int exptime = 0;
        const void *buf;
        STRLEN buf_len;
        int res;
    CODE:
        if (items > 3)
          flags = SvUV(ST(3));
        if (items > 4)
          exptime = SvIV(ST(4));
        key = SvPV(skey, key_len);
        buf = (void *) SvPV(sval, buf_len);
        res = client_set(memd, key, key_len, flags, exptime, buf, buf_len);
        /* FIXME: use XSRETURN_{YES|NO} or even TARG.  */
        RETVAL = (res == MEMCACHED_SUCCESS);
    OUTPUT:
        RETVAL


void
_xs_get(memd, skey)
        Cache_Memcached1 *  memd
        SV *                skey
    PROTOTYPE: $$
    PREINIT:
        const char *key;
        STRLEN key_len;
        struct xs_skey_result skey_res;
        int res;
    PPCODE:
        key = SvPV(skey, key_len);
        skey_res.sv = NULL;
        res = client_get(memd, key, key_len, skey_alloc, &skey_res);
        if (skey_res.sv != NULL)
          {
            if (res == MEMCACHED_SUCCESS)
              {
                dXSTARG;

                PUSHs(sv_2mortal(skey_res.sv));
                PUSHu(skey_res.flags);
                XSRETURN(2);
              }
            else
              {
                /*
                  client_get() didn't return success, so we can't be
                  sure the value is valid.  Release SV, and return no
                  result.
                */
                SvREFCNT_dec(skey_res.sv);
              }
          }


void
_xs_mget(memd, ...)
        Cache_Memcached1 *  memd
    PROTOTYPE: $@
    PREINIT:
        struct xs_mkey_result mkey_res;
        int key_count, i;
    PPCODE:
        key_count = items - 1;
        mkey_res.ax = ax;
        mkey_res.stack_offset = 1;  
        mkey_res.key_val = newAV();
        mkey_res.flags = newAV();
        av_extend(mkey_res.key_val, key_count * 2);
        av_extend(mkey_res.flags, key_count);
        if (key_count > 0)
          {
            int res;

            res = client_mget(memd, key_count, get_key, mkey_alloc, &mkey_res);
            if (res != MEMCACHED_SUCCESS && av_len(mkey_res.flags) >= 0)
              {
                /* Last value may be invalid.  Release it.  */
                SvREFCNT_dec(av_pop(mkey_res.key_val));
                SvREFCNT_dec(av_pop(mkey_res.key_val));
                SvREFCNT_dec(av_pop(mkey_res.flags));
              }
          }
        EXTEND(SP, 2);
        PUSHs(sv_2mortal(newRV_noinc((SV *) mkey_res.key_val)));
        PUSHs(sv_2mortal(newRV_noinc((SV *) mkey_res.flags)));
        XSRETURN(2);
