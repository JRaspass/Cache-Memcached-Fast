#ifndef CLIENT_H
#define CLIENT_H 1

#include <stddef.h>


struct client;


enum server_status {
  MEMCACHED_SUCCESS,
  MEMCACHED_FAILURE,
  MEMCACHED_EAGAIN,
  MEMCACHED_ERROR,
  MEMCACHED_UNKNOWN,
  MEMCACHED_CLOSED
};

enum set_cmd_e { CMD_SET, CMD_ADD, CMD_REPLACE, CMD_APPEND, CMD_PREPEND };


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


extern
struct client *
client_init();

extern
void
client_destroy(struct client *c);

extern
int
client_add_server(struct client *c, const char *host, size_t host_len,
                  const char *port, size_t port_len);

extern
int
client_set_prefix(struct client *c, const char *ns, size_t ns_len);

extern
void
client_set_connect_timeout(struct client *c, int to);

extern
void
client_set_io_timeout(struct client *c, int to);

extern
void
client_set_close_on_error(struct client *c, int enable);

extern
void
client_set_noreply(struct client *c, int enable);

extern
int
client_set(struct client *c, enum set_cmd_e cmd,
           const char *key, size_t key_len,
           flags_type flags, exptime_type exptime,
           const void *value, value_size_type value_size, int noreply);

extern
int
client_get(struct client *c, const char *key, size_t key_len,
           struct value_object *o);

extern
int
client_mget(struct client *c, int key_count, get_key_func get_key,
            struct value_object *o);

extern
int
client_delete(struct client *c, const char *key, size_t key_len,
              delay_type delay, int noreply);

extern
int
client_flush_all(struct client *c, delay_type delay, int noreply);


#endif /* ! CLIENT_H */
