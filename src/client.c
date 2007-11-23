#include "client.h"
#include "connect.h"
#include "protocol.h"
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
  c->close_on_error = 1;

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
void
client_mark_failed(struct client *c, int server_index)
{
  struct server *s;

  s = &c->servers[server_index];

  if (s->fd != -1)
    {
      close(s->fd);
      s->fd = -1;
    }
}


static
int
client_get_server_index(struct client *c, const char *key, size_t key_len)
{
  int index;
  struct server *s;

  if (c->server_count == 0)
    return -1;

  if (c->server_count == 1)
    {
      index = 0;
    }
  else
    {
      assert(0 && "NOT IMPLEMENTED");
    }

  s = &c->servers[index];
  if (s->fd == -1)
    s->fd = client_connect_inet(s->host, s->port, 1, c->connect_timeout);

  if (s->fd == -1)
    {
      client_mark_failed(c, index);
      return -1;
    }

  return index;
}


int
client_set(struct client *c, const char *key, size_t key_len,
           flags_type flags, exptime_type exptime,
           const void *buf, size_t buf_size)
{
  int server_index, fd, res;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  fd = c->servers[server_index].fd;
  res = protocol_set(fd, key, key_len, flags, exptime, buf, buf_size);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_get(struct client *c, const char *key, size_t key_len,
           alloc_value_func alloc_value, void *alloc_value_arg)
{
  int server_index, fd, res;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  fd = c->servers[server_index].fd;
  res = protocol_get(fd, key, key_len, alloc_value, alloc_value_arg);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}
