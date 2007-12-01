#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


#include "src/client.h"
#include <stdlib.h>
#include <string.h>


typedef struct client Cache_Memcached_Fast;


static
void
parse_config(Cache_Memcached_Fast *memd, HV *conf)
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
          if (client_add_server(memd, host, host_len, port, port_len)
              != MEMCACHED_SUCCESS)
            croak("Not enough memory");
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
skey_store(void *arg, int key_index, flags_type flags)
{
  struct xs_skey_result *skey_res;

  /* Suppress warning about unused key_index.  */
  if (key_index) {}

  skey_res = (struct xs_skey_result *) arg;

  skey_res->flags = flags;
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
mkey_store(void *arg, int key_index, flags_type flags)
{
  I32 ax;
  struct xs_mkey_result *mkey_res;
  SV *key_sv;

  mkey_res = (struct xs_mkey_result *) arg;

  ax = mkey_res->ax;
  key_sv = ST(mkey_res->stack_offset + key_index);
  SvREFCNT_inc(key_sv);
  av_push(mkey_res->key_val, key_sv);
  av_push(mkey_res->key_val, mkey_res->sv);

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


MODULE = Cache::Memcached::Fast		PACKAGE = Cache::Memcached::Fast


Cache_Memcached_Fast *
new(class, conf)
        const char *            class
        SV *                    conf
    PROTOTYPE: $$
    PREINIT:
        Cache_Memcached_Fast *memd;
    CODE:
        New(0, memd, 1, Cache_Memcached_Fast); /* FIXME: check OOM.  */
        client_init(memd);
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
        Safefree(memd);


bool
_xs_set(memd, skey, sval, flags, ...)
        Cache_Memcached_Fast *  memd
        SV *                    skey
        SV *                    sval
        unsigned int            flags
    ALIAS:
        _xs_add      =  CMD_ADD
        _xs_replace  =  CMD_REPLACE
        _xs_append   =  CMD_APPEND
        _xs_prepend  =  CMD_PREPEND
    PROTOTYPE: $$$$;$
    PREINIT:
        const char *key;
        STRLEN key_len;
        const void *buf;
        STRLEN buf_len;
        int exptime = 0, noreply, res;
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


void
_xs_get(memd, skey)
        Cache_Memcached_Fast *  memd
        SV *                    skey
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
        client_get(memd, key, key_len, &object);
        if (skey_res.sv != NULL)
          {
            dXSTARG;

            PUSHs(sv_2mortal(skey_res.sv));
            PUSHu(skey_res.flags);
            XSRETURN(2);
          }


void
_xs_mget(memd, ...)
        Cache_Memcached_Fast *  memd
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
          client_mget(memd, key_count, get_key, &object);
        EXTEND(SP, 2);
        PUSHs(sv_2mortal(newRV_noinc((SV *) mkey_res.key_val)));
        PUSHs(sv_2mortal(newRV_noinc((SV *) mkey_res.flags)));
        XSRETURN(2);


bool
delete(memd, skey, ...)
        Cache_Memcached_Fast *  memd
        SV *                    skey
    PROTOTYPE: $$;$
    PREINIT:
        const char *key;
        STRLEN key_len;
        unsigned int delay = 0;
        int noreply, res;
    CODE:
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
        unsigned int delay = 0;
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
