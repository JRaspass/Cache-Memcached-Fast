#ifndef CLIENT_H
#define CLIENT_H 1

#include "server.h"
#include <stddef.h>


enum set_cmd_e { CMD_SET, CMD_ADD, CMD_REPLACE, CMD_APPEND, CMD_PREPEND };


struct server;


struct client
{
  struct server *servers;
  char *prefix;
  size_t prefix_len;
  int server_count;
  int server_capacity;
  int connect_timeout;          /* 1/1000 sec.  */
  int io_timeout;               /* 1/1000 sec.  */
  int close_on_error;
  int noreply;
};


extern
void
client_init(struct client *c);

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

static inline
void
client_set_connect_timeout(struct client *c, int to)
{
  c->connect_timeout = to;
}

static inline
void
client_set_io_timeout(struct client *c, int to)
{
  c->io_timeout = to;
}

static inline
void
client_set_close_on_error(struct client *c, int enable)
{
  c->close_on_error = enable;
}

static inline
void
client_set_noreply(struct client *c, int enable)
{
  c->noreply = enable;
}

extern
int
client_set(struct client *c, enum set_cmd_e cmd,
           const char *key, size_t key_len,
           flags_type flags, exptime_type exptime,
           const void *value, size_t value_size, int noreply);

extern
int
client_get(struct client *c, const char *key, size_t key_len,
           alloc_value_func alloc_value, void *arg);

extern
int
client_mget(struct client *c, int key_count, get_key_func get_key,
            alloc_value_func alloc_value, void *arg);

extern
int
client_delete(struct client *c, const char *key, size_t key_len,
              delay_type delay, int noreply);

extern
int
client_flush_all(struct client *c, delay_type delay, int noreply);


#endif /* ! CLIENT_H */
