#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


#include "src/client.h"
#include <stdlib.h>


typedef struct client Cache_Memcached1;


MODULE = Cache::Memcached1		PACKAGE = Cache::Memcached1


void
new(class)
        const char *  class
    PREINIT:
        Cache_Memcached1 *memd;
    PPCODE:
        New(0, memd, 1, Cache_Memcached1);
        client_init(memd);
        PUSHmortal;
        sv_setref_pv(ST(0), class, (void*) memd);
        XSRETURN(1);            /* FIXME: do we need this?  */


void
DESTROY(memd)
        Cache_Memcached1 *  memd
    CODE:
        client_destroy(memd);
        Safefree(memd);
