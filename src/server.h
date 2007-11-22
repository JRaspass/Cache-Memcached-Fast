#ifndef SERVER_H
#define SERVER_H 1


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


#endif // ! SERVER_H
