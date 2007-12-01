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


typedef char *(*get_key_func)(void *arg, int key_index, size_t *key_len);


typedef void *(*alloc_value_func)(void *arg, value_size_type value_size);
typedef void (*store_value_func)(void *arg, int key_index, flags_type flags);
typedef void (*free_value_func)(void *arg);

struct value_object
{
  alloc_value_func alloc;
  store_value_func store;
  free_value_func free;

  void *arg;
};


#endif // ! SERVER_H
