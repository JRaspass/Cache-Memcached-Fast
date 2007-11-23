#ifndef SERVER_H
#define SERVER_H 1

#include <stddef.h>


enum server_status {
  MEMCACHED_CLOSED,
  MEMCACHED_UNKNOWN,
  MEMCACHED_ERROR,
  MEMCACHED_FAILURE,
  MEMCACHED_SUCCESS
};


typedef unsigned int flags_type;
#define FMT_FLAGS "%u"

typedef int exptime_type;
#define FMT_EXPTIME "%d"


typedef void *(*alloc_value_func)(void *alloc_value_arg, size_t key_index,
                                  flags_type flags, size_t value_size);


#endif // ! SERVER_H
