#ifndef SERVER_H
#define SERVER_H 1

#include <stddef.h>


enum server_status {
  MEMCACHED_SUCCESS,
  MEMCACHED_FAILURE,
  MEMCACHED_EAGAIN,
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

typedef size_t value_size_type;
#define FMT_VALUE_SIZE "%zu"


typedef void *(*alloc_value_func)(void *alloc_value_arg, int key_index,
                                  flags_type flags,
                                  value_size_type value_size);


typedef void (*invalidate_value_func)(void *arg);


typedef char *(*get_key_func)(void *arg, int key_index, size_t *key_len);


#endif // ! SERVER_H
