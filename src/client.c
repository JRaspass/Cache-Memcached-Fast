#include "client.h"
#include "connect.h"
#include <stdlib.h>
#include <unistd.h>
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
  s->host[host_len] = '\0';
  memcpy(s->port, port, port_len);
  s->port[port_len] = '\0';

  s->fd = -1;

  return 0;
}


static inline
void
server_destroy(struct server *s)
{
  if (s->fd != -1)
    close(s->fd);

  free(s->host);
}


int
client_init(struct client *c)
{
  c->servers = (struct server *) malloc(sizeof(struct server));
  if (! c->servers)
    return -1;
  c->server_capacity = 1;
  c->server_count = 0;

  c->connect_timeout = 250;
  c->io_timeout = 1000;
  c->namespace_prefix = NULL;
  c->namespace_prefix_len = 0;

  return 0;
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
                  host, host_len, port, port_len) != 0)
    return -1;

  ++c->server_count;

  return 0;
}


int
client_set_namespace(struct client *c, const char *ns, size_t ns_len)
{
  char *s = (char *) realloc(c->namespace_prefix, ns_len + 1);
  if (! s)
    return -1;

  memcpy(s, ns, ns_len);
  s[ns_len] = '\0';

  c->namespace_prefix = s;
  c->namespace_prefix_len = ns_len;

  return 0;
}


static
int
client_get_sock(struct client *c, const char *key, size_t key_len)
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

  if (s->fd == -1)
    s->fd = client_connect_inet(s->host, s->port, 1, c->connect_timeout);

#if 0
  if (s->fd == -1)
    {
      remove the server.
    }
#endif

  return s->fd;
}


int
client_set(struct client *c, const char *key, size_t key_len,
           const void *buf, size_t buf_size)
{

}
