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

  s->request_buf = NULL;
  s->request_buf_size = 0;

  s->fd = -1;

  return 0;
}


static inline
void
server_destroy(struct server *s)
{
  free(s->host); /* This also frees port string.  */
  free(s->request_buf);

  if (s->fd != -1)
    close(s->fd);
}


void
client_init(struct client *c)
{
  c->servers = NULL;
  c->server_capacity = 0;
  c->server_count = 0;

  c->connect_timeout = 250;
  c->io_timeout = 1000;
  c->namespace_prefix = NULL;
  c->namespace_prefix_len = 0;
  c->close_on_error = 1;
}


void
client_destroy(struct client *c)
{
  int i;

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
      int capacity = (c->server_capacity > 0 ? c->server_capacity * 2 : 1);
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
           const void *value, size_t value_size)
{
  static const size_t request_size =
    (sizeof(struct iovec) * 5
     + sizeof(" 4294967295 2147483647 18446744073709551615\r\n"));
  struct iovec *iov;
  char *buf;
  int server_index, res;
  struct server *s;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  s = &c->servers[server_index];

  if (s->request_buf_size < request_size)
    {
      void *buf = realloc(s->request_buf, request_size);
      if (! buf)
        return -1;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  iov = (struct iovec *) s->request_buf;
  buf = (char *) s->request_buf + sizeof(struct iovec) * 5;

  iov[0].iov_base = "set ";
  iov[0].iov_len = 4;
  iov[1].iov_base = (void *) key;
  iov[1].iov_len = key_len;
  iov[2].iov_base = buf;
  iov[2].iov_len = sprintf(buf, " " FMT_FLAGS " " FMT_EXPTIME " %zu\r\n",
                           flags, exptime, value_size);
  iov[3].iov_base = (void *) value;
  iov[3].iov_len = value_size;
  iov[4].iov_base = "\r\n";
  iov[4].iov_len = 2;

  res = protocol_set(s->fd, iov, 5, value, value_size);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_get(struct client *c, const char *key, size_t key_len,
           alloc_value_func alloc_value, void *arg)
{
  static const size_t request_size = sizeof(struct iovec) * 3;
  struct iovec *iov;
  int server_index, res;
  struct server *s;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  s = &c->servers[server_index];

  if (s->request_buf_size < request_size)
    {
      void *buf = realloc(s->request_buf, request_size);
      if (! buf)
        return -1;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  iov = (struct iovec *) s->request_buf;

  iov[0].iov_base = "get ";
  iov[0].iov_len = 4;
  iov[1].iov_base = (void *) key;
  iov[1].iov_len = key_len;
  iov[2].iov_base = "\r\n";
  iov[2].iov_len = 2;

  res = protocol_get(s->fd, iov, 3, alloc_value, arg);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_mget(struct client *c, int key_count, get_key_func get_key,
            alloc_value_func alloc_value, void *arg)
{
  size_t request_size = sizeof(struct iovec) * (key_count * 2 + 2);
  struct iovec *iov;
  int server_index, res;
  struct server *s;
  int i;

  server_index = 0; //client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  s = &c->servers[server_index];

  if (s->request_buf_size < request_size)
    {
      void *buf = realloc(s->request_buf, request_size);
      if (! buf)
        return -1;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  iov = (struct iovec *) s->request_buf;

  iov[0].iov_base = "get";
  iov[0].iov_len = 3;
  i = 1;
  while (i <= key_count * 2)
    {
      size_t key_len;

      iov[i].iov_base = " ";
      iov[i].iov_len = 1;
      iov[i + 1].iov_base = get_key(arg, i - 1, &key_len);
      iov[i + 1].iov_len = key_len;
      i += 2;
    }
  iov[i].iov_base = "\r\n";
  iov[i].iov_len = 2;

  res = protocol_get(s->fd, iov, i + 1, alloc_value, arg);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}
