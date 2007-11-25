#ifndef SERVER_H
#define SERVER_H 1

#include <stddef.h>


enum server_status {
  MEMCACHED_SUCCESS,
  MEMCACHED_FAILURE,
  MEMCACHED_ERROR,
  MEMCACHED_UNKNOWN,
  MEMCACHED_CLOSED
};


typedef unsigned int flags_type;
#define FMT_FLAGS "%u"

typedef int exptime_type;
#define FMT_EXPTIME "%d"

typedef unsigned int delay_type;
#define FMT_DELAY "%u"


typedef void *(*alloc_value_func)(void *alloc_value_arg, int key_index,
                                  flags_type flags, size_t value_size);


typedef char *(*get_key_func)(void *arg, int key_index, size_t *key_len);


#endif // ! SERVER_H
