#ifndef CLIENT_H
#define CLIENT_H 1

#include <stddef.h>


struct server
{
  char *host;
  char *port;
  int fd;
};


struct client
{
  struct server *servers;
  size_t server_count;
  size_t server_capacity;
  int connect_timeout;          /* 1/1000 sec.  */
  int io_timeout;               /* 1/1000 sec.  */
  char *namespace_prefix;
  size_t namespace_prefix_len;
};


extern
int
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
client_set_namespace(struct client *c, const char *ns, size_t ns_len);

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


#endif // ! CLIENT_H
