#include "client.h"
#include <stdlib.h>
#include <string.h>
#include <assert.h>


static inline
int
server_init(struct server *s, const char *host, size_t host_len,
            const char *port, size_t port_len)
{
  s->host = (char *) malloc(host_len + 1 + port_len + 1);

  if (! s->host)
    return -1;

  s->port = s->host + host_len + 1;
  memcpy(s->host, host, host_len);
  memcpy(s->port, port, port_len);

  return 0;
}


static inline
void
server_destroy(struct server *s)
{
  free(s->host);
}


void
client_init(struct client *c)
{
  c->servers = NULL;
  c->server_count = 0;
  c->server_capacity = 0;
  c->connect_timeout = 250;
  c->io_timeout = 1000;
  c->namespace_prefix = NULL;
  c->namespace_prefix_len = 0;
}


void
client_destroy(struct client *c)
{
  size_t i;

  for (i = 0; i < c->server_count; ++i)
    server_destroy(&c->servers[i]);

  free(c->servers);
  free(c->namespace_prefix);
}


int
client_add_server(struct client *c, const char *host, size_t host_len,
                  const char *port, size_t port_len)
{
  if (c->server_count == c->server_capacity)
    {
      size_t capacity = c->server_capacity * 2;
      struct server *s =
        (struct server *) realloc(c->servers,
                                  capacity * sizeof(struct server));

      if (! s)
        return -1;

      c->servers = s;
      c->server_capacity = capacity;
    }

  if (server_init(&c->servers[c->server_count],
                  host, host_len, port, port_len) == -1)
    return -1;

  ++c->server_count;

  return 0;
}


#if 0
int
client_get_sock(struct client *c, const char *key, size_t len)
{
  if (c->server_count == 0)
    return -1;

  struct server *s;
  if (c->server_count == 1)
    {
      s = &c->servers[0];
    }
  else
    {
      assert(0 && "NOT IMPLEMENTED");
    }

  if (s->fd >= 0)
    return s->fd;


}
#endif
