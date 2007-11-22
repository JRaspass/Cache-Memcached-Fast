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
        if (client_init(memd) != 0)
          croak("Not enough memory");
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
        unsigned int exptime = 0;
        const void *buf;
        STRLEN buf_len;
        int res;
    CODE:
        if (items > 3)
          flags = SvUV(ST(3));
        if (items > 4)
          exptime = SvUV(ST(4));
        key = SvPV(skey, key_len);
        buf = (void *) SvPV(sval, buf_len);
        res = client_set(memd, key, key_len, flags, exptime, buf, buf_len);
        RETVAL = (res == MEMCACHED_SUCCESS);
    OUTPUT:
        RETVAL
