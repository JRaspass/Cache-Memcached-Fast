#include "client.h"
#include "connect.h"
#include "parse_reply.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/uio.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>


#ifndef MAX_IOVEC
#define MAX_IOVEC 1024
#endif


/* Any positive buffer size is supported, 1 is good for testing.  */
static const int REPLY_BUF_SIZE = 2048;


typedef unsigned long long protocol_unum;


struct get_result_state
{
  protocol_unum flags;
  protocol_unum value_size;
  void *value;
  alloc_value_func alloc_value;
  void *alloc_value_arg;
};


struct command_state;
typedef int (*parse_reply_func)(struct command_state *state, char *buf);


struct command_state
{
  int fd;

  struct iovec *request_iov;
  int request_iov_count;
  struct iovec *key;
  int key_count;
  int key_index;

  struct genparser_state reply_parser_state;
  char *pos;
  char *end;
  int eol_state;
  char *key_pos;
  size_t prefix_len;
  int key_step;

  parse_reply_func parse_reply;

  union
  {
    struct get_result_state get_result;
  };

  /* iov_buf should be the last field.  */
  struct iovec iov_buf[1];
};


struct server
{
  char *host;
  char *port;
  void *request_buf;
  size_t request_buf_size;
  int fd;
};


static inline
void
get_result_state_reset(struct get_result_state *state)
{
  state->flags = 0;
  state->value_size = 0;
}


static inline
void
get_result_state_init(struct get_result_state *state,
                      alloc_value_func alloc_value, void *alloc_value_arg)
{
  get_result_state_reset(state);
  state->alloc_value = alloc_value;
  state->alloc_value_arg = alloc_value_arg;

#if 0 /* No need to initialize the following.  */
  state->value = NULL;
#endif
}


static inline
void
command_state_init(struct command_state *state, int fd,
                   int count, int first_key_index, int key_count,
                   size_t prefix_len, parse_reply_func parse_reply)
{
  state->fd = fd;
  state->request_iov = state->iov_buf;
  state->request_iov_count = count;
  state->key = &state->iov_buf[first_key_index];
  state->key_count = key_count;
  state->key_index = 0;
  genparser_init(&state->reply_parser_state);
  state->eol_state = 0;
  state->key_pos = (char *) state->key->iov_base;
  state->prefix_len = prefix_len;
  /* Keys are interleaved with spaces and possibly with prefix.  */
  state->key_step = (prefix_len ? 3 : 2);
  state->parse_reply = parse_reply;

#if 0 /* No need to initialize the following.  */
  state->pos = NULL;
  state->end = NULL;
#endif
}


static inline
ssize_t
read_restart(int fd, void *buf, size_t size)
{
  ssize_t res;

  do
    res = read(fd, buf, size);
  while (res == -1 && errno == EINTR);

  return res;
}


static inline
ssize_t
writev_restart(int fd, const struct iovec *iov, int count)
{
  ssize_t res;

  do
    res = writev(fd, iov, count);
  while (res == -1 && errno == EINTR);

  return res;
}


static inline
int
read_next_chunk(struct command_state *state, char *buf)
{
  ssize_t res;

  res = read_restart(state->fd, buf, REPLY_BUF_SIZE);
  if (res <= 0)
    return MEMCACHED_CLOSED;

  state->pos = buf;
  state->end = buf + res;

  return MEMCACHED_SUCCESS;
}


static
int
swallow_eol(struct command_state *state, char *buf, int skip)
{
  static const char eol[2] = "\r\n";

  while (state->eol_state < (int) sizeof(eol))
    {
      if (state->pos == state->end)
        {
          int res;

          res = read_next_chunk(state, buf);
          if (res != MEMCACHED_SUCCESS)
            return res;
        }

      if (*state->pos != eol[state->eol_state])
        {
          if (skip)
            {
              state->eol_state = 0;
              ++state->pos;
              continue;
            }
          else
            {
              return MEMCACHED_UNKNOWN;
            }
        }

      ++state->pos;
      ++state->eol_state;
    }

  state->eol_state = 0;

  return MEMCACHED_SUCCESS;
}


static inline
int
parse_keyword(struct command_state *state, char *buf)
{
  int parse_res;

  do
    {
      if (state->pos == state->end)
        {
          int res;

          res = read_next_chunk(state, buf);
          if (res != MEMCACHED_SUCCESS)
            return res;
        }

      parse_res = parse_reply(&state->reply_parser_state,
                              &state->pos, state->end);
    }
  while (parse_res == 0);

  if (parse_res == -1)
    return MEMCACHED_UNKNOWN;

  return MEMCACHED_SUCCESS;
}


static inline
int
skip_space(struct command_state *state, char *buf)
{
  while (1)
    {
      int res;

      while (state->pos != state->end && *state->pos == ' ')
        ++state->pos;

      if (state->pos != state->end)
        return MEMCACHED_SUCCESS;

      res = read_next_chunk(state, buf);
      if (res != MEMCACHED_SUCCESS)
        return res;
    }
}


static
int
parse_key(struct command_state *state, char *buf)
{
  size_t prefix_len;
  int res;

  res = skip_space(state, buf);
  if (res != MEMCACHED_SUCCESS)
    return res;

  /* Skip over the prefix.  */
  /* FIXME: should be part of the state.  */
  prefix_len = state->prefix_len;
  while ((size_t) (state->end - state->pos) < prefix_len)
    {
      int res;

      prefix_len -= state->end - state->pos;
      res = read_next_chunk(state, buf);
      if (res != MEMCACHED_SUCCESS)
        return res;
    }
  if (prefix_len > 0)
    state->pos += prefix_len;

  if (--state->key_count > 0)
    {
      while (1)
        {
          char *key_end, *prefix_key;
          size_t prefix_len;

          key_end = (char *) state->key->iov_base + state->key->iov_len;
          while (state->pos != state->end && state->key_pos != key_end
                 && *state->pos == *state->key_pos)
            {
              ++state->key_pos;
              ++state->pos;
            }

          if (state->key_pos == key_end)
            break;

          if (state->pos == state->end)
            {
              int res;

              res = read_next_chunk(state, buf);
              if (res != MEMCACHED_SUCCESS)
                return res;

              continue;
            }

          if (--state->key_count == 0)
            {
              ++state->key_index;
              state->key += state->key_step;

              break;
            }

          prefix_key = (char *) state->key->iov_base;
          prefix_len = state->key_pos - prefix_key;
          do
            {
              ++state->key_index;
              state->key += state->key_step;
            }
          while ((state->key->iov_len < prefix_len
                  || memcmp(state->key->iov_base, prefix_key, prefix_len) != 0)
                 && --state->key_count > 0);

          state->key_pos = (char *) state->key->iov_base + prefix_len;
        }
    }

  if (state->key_count == 0)
    {
      while (1)
        {
          int res;

          while (state->pos != state->end && *state->pos != ' ')
            ++state->pos;

          if (state->pos != state->end)
            break;

          res = read_next_chunk(state, buf);
          if (res != MEMCACHED_SUCCESS)
            return res;
        }
    }

  ++state->key_index;
  state->key += state->key_step;
  state->key_pos = (char *) state->key->iov_base;

  return MEMCACHED_SUCCESS;
}


static
int
parse_unum(struct command_state *state, char *buf,
           protocol_unum *num)
{
  int digits = 0; /* FIXME: should be part of the state.  */
  int res;

  res = skip_space(state, buf);
  if (res != MEMCACHED_SUCCESS)
    return res;

  while (1)
    {
      int res;

      while (state->pos != state->end)
        {
          switch (*state->pos)
            {
            case '0': case '1': case '2': case '3': case '4':
            case '5': case '6': case '7': case '8': case '9':
              *num = *num * 10 + (*state->pos - '0');
              ++digits;
              ++state->pos;
              break;

            default:
              return (digits ? MEMCACHED_SUCCESS : MEMCACHED_UNKNOWN);
            }
        }

      res = read_next_chunk(state, buf);
      if (res != MEMCACHED_SUCCESS)
        return res;
    }
}


static
int
read_value(struct command_state *state, void *value, protocol_unum value_size)
{
  size_t size;
  void *ptr;
  ssize_t res;

  size = state->end - state->pos;
  if (size > value_size)
    size = value_size;
  memcpy(value, state->pos, size);
  value_size -= size;
  state->pos += size;

  /* FIXME: should be part of the state (as well as value_size).  */
  ptr = (void *) ((char *) value + size);
  while (value_size > 0
         && (res = read_restart(state->fd, ptr, value_size)) > 0)
    {
      ptr = (void *) ((char *) ptr + res);
      value_size -= res;
    }

  return (value_size == 0 ? MEMCACHED_SUCCESS : MEMCACHED_CLOSED);
}


static
int
parse_get_reply(struct command_state *state, char *buf)
{
  while (1)
    {
      int match, res;

      match = genparser_get_match(&state->reply_parser_state);
      switch (match)
        {
        case MATCH_END:
          return swallow_eol(state, buf, 0);

        default:
          return MEMCACHED_UNKNOWN;

        case MATCH_VALUE:
          break;
        }

      res = parse_key(state, buf);
      if (res != MEMCACHED_SUCCESS)
        return res;

      res = parse_unum(state, buf, &state->get_result.flags);
      if (res != MEMCACHED_SUCCESS)
        return res;

      res = parse_unum(state, buf, &state->get_result.value_size);
      if (res != MEMCACHED_SUCCESS)
        return res;

      res = swallow_eol(state, buf, 0);
      if (res != MEMCACHED_SUCCESS)
        return res;

      state->get_result.value =
        state->get_result.alloc_value(state->get_result.alloc_value_arg,
                                      state->key_index - 1, 
                                      state->get_result.flags,
                                      state->get_result.value_size);
      if (! state->get_result.value)
        return MEMCACHED_FAILURE;

      res = read_value(state, state->get_result.value,
                       state->get_result.value_size);
      if (res != MEMCACHED_SUCCESS)
        return res;

      res = swallow_eol(state, buf, 0);
      if (res != MEMCACHED_SUCCESS)
        return res;

      get_result_state_reset(&state->get_result);

      /* Proceed with the next key.  */
      res = parse_keyword(state, buf);
      if (res != MEMCACHED_SUCCESS)
        return res;
    }
}


static
int
parse_set_reply(struct command_state *state, char *buf)
{
  int match;

  match = genparser_get_match(&state->reply_parser_state);
  switch (match)
    {
    case MATCH_STORED:
      return swallow_eol(state, buf, 0);

    case MATCH_NOT_STORED:
      {
        int res;

        res = swallow_eol(state, buf, 0);

        return (res == MEMCACHED_SUCCESS ? MEMCACHED_FAILURE : res);
      }

    default:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
parse_delete_reply(struct command_state *state, char *buf)
{
  int match;

  match = genparser_get_match(&state->reply_parser_state);
  switch (match)
    {
    case MATCH_DELETED:
      return swallow_eol(state, buf, 0);

    case MATCH_NOT_FOUND:
      {
        int res;

        res = swallow_eol(state, buf, 0);

        return (res == MEMCACHED_SUCCESS ? MEMCACHED_FAILURE : res);
      }

    default:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
parse_ok_reply(struct command_state *state, char *buf)
{
  int match;

  match = genparser_get_match(&state->reply_parser_state);
  switch (match)
    {
    case MATCH_OK:
      return swallow_eol(state, buf, 0);

    default:
      return MEMCACHED_UNKNOWN;
    }
}


static inline
int
garbage_remains(struct command_state *state)
{
  return (state->pos != state->end);
}


static
int
read_reply(struct command_state *state)
{
  char buf[REPLY_BUF_SIZE];
  int res, match;

  state->pos = state->end = buf;

  res = parse_keyword(state, buf);
  if (res != MEMCACHED_SUCCESS)
    return res;

  match = genparser_get_match(&state->reply_parser_state);
  switch (match)
    {
    case MATCH_CLIENT_ERROR:
    case MATCH_SERVER_ERROR:
    case MATCH_ERROR:
      {
        int skip, res;

        skip = (match != MATCH_ERROR);
        res = swallow_eol(state, buf, skip);

        if (garbage_remains(state))
          return MEMCACHED_UNKNOWN;

        return (res == MEMCACHED_SUCCESS ? MEMCACHED_ERROR : res);
      }

    default:
      {
        int res;

        res = state->parse_reply(state, buf);

        if (garbage_remains(state))
          return MEMCACHED_UNKNOWN;

        return res;
      }
    }
}


static
int
process_command(struct command_state *state)
{
  while (state->request_iov_count > 0)
    {
      int count;
      ssize_t res;

      count = (state->request_iov_count < MAX_IOVEC
               ? state->request_iov_count : MAX_IOVEC);
      res = writev_restart(state->fd, state->request_iov, count);

      if (res <= 0)
        return MEMCACHED_CLOSED;

      while ((size_t) res >= state->request_iov->iov_len)
        {
          res -= state->request_iov->iov_len;
          ++state->request_iov;
          --state->request_iov_count;
        }
      state->request_iov->iov_base += res;
      state->request_iov->iov_len -= res;
    }

  if (state->parse_reply)
    return read_reply(state);

  return MEMCACHED_SUCCESS;
}


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
  c->prefix = NULL;
  c->prefix_len = 0;
  c->close_on_error = 1;
}


void
client_destroy(struct client *c)
{
  int i;

  for (i = 0; i < c->server_count; ++i)
    server_destroy(&c->servers[i]);

  free(c->servers);
  free(c->prefix);
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
client_set_prefix(struct client *c, const char *ns, size_t ns_len)
{
  char *s = (char *) realloc(c->prefix, ns_len + 1);
  if (! s)
    return -1;

  memcpy(s, ns, ns_len);
  s[ns_len] = '\0';

  c->prefix = s;
  c->prefix_len = ns_len;

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
      /* FIXME: implement multiple servers.  */
      index = 0;
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
client_set(struct client *c, enum set_cmd_e cmd,
           const char *key, size_t key_len,
           flags_type flags, exptime_type exptime,
           const void *value, size_t value_size)
{
  size_t request_size =
    (sizeof(struct command_state)
     + sizeof(struct iovec) * ((c->prefix_len ? 6 : 5) - 1)
     + sizeof(" 4294967295 2147483647 18446744073709551615\r\n"));
  struct command_state *state;
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
        return MEMCACHED_FAILURE;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  state = (struct command_state *) s->request_buf;
  iov = state->iov_buf;

  switch (cmd)
    {
    case CMD_SET:
      iov->iov_base = "set ";
      iov->iov_len = 4;
      break;

    case CMD_ADD:
      iov->iov_base = "add ";
      iov->iov_len = 4;
      break;

    case CMD_REPLACE:
      iov->iov_base = "replace ";
      iov->iov_len = 8;
      break;

    case CMD_APPEND:
      iov->iov_base = "append ";
      iov->iov_len = 7;
      break;

    case CMD_PREPEND:
      iov->iov_base = "prepend ";
      iov->iov_len = 8;
      break;
    }
  ++iov;
  if (c->prefix_len)
    {
      iov->iov_base = c->prefix;
      iov->iov_len = c->prefix_len;
      ++iov;
    }
  iov->iov_base = (void *) key;
  iov->iov_len = key_len;
  ++iov;
  buf = (char *) (iov + 3);
  iov->iov_base = buf;
  iov->iov_len = sprintf(buf, " " FMT_FLAGS " " FMT_EXPTIME " %zu\r\n",
                           flags, exptime, value_size);
  ++iov;
  iov->iov_base = (void *) value;
  iov->iov_len = value_size;
  ++iov;
  iov->iov_base = "\r\n";
  iov->iov_len = 2;
  ++iov;

  command_state_init(state, s->fd, (iov - state->iov_buf),
                     (c->prefix_len ? 2 : 1), 1,
                     c->prefix_len, parse_set_reply);
  res = process_command(state);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_get(struct client *c, const char *key, size_t key_len,
           alloc_value_func alloc_value, void *arg)
{
  size_t request_size =
    (sizeof(struct command_state)
     + sizeof(struct iovec) * ((c->prefix_len ? 4 : 3) - 1));
  struct command_state *state;
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
        return MEMCACHED_FAILURE;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    }

  state = (struct command_state *) s->request_buf;
  iov = state->iov_buf;

  iov->iov_base = "get ";
  iov->iov_len = 4;
  ++iov;
  if (c->prefix_len)
    {
      iov->iov_base = c->prefix;
      iov->iov_len = c->prefix_len;
      ++iov;
    }
  iov->iov_base = (void *) key;
  iov->iov_len = key_len;
  ++iov;
  iov->iov_base = "\r\n";
  iov->iov_len = 2;
  ++iov;

  command_state_init(state, s->fd, (iov - state->iov_buf),
                     (c->prefix_len ? 2 : 1), 1,
                     c->prefix_len, parse_get_reply);
  get_result_state_init(&state->get_result, alloc_value, arg);
  res = process_command(state);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_mget(struct client *c, int key_count, get_key_func get_key,
            alloc_value_func alloc_value, void *arg)
{
  size_t request_size =
    (sizeof(struct command_state)
     + sizeof(struct iovec) * (key_count * (c->prefix_len ? 3 : 2) + 2 - 1));
  struct command_state *state;
  struct iovec *iov;
  int server_index, res;
  struct server *s;
  int i;

  /* FIXME: implement per-key dispatch.  */
  server_index = client_get_server_index(c, NULL, 0);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  s = &c->servers[server_index];

  if (s->request_buf_size < request_size)
    {
      void *buf = realloc(s->request_buf, request_size);
      if (! buf)
        return MEMCACHED_FAILURE;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  state = (struct command_state *) s->request_buf;
  iov = state->iov_buf;

  iov->iov_base = "get";
  iov->iov_len = 3;
  ++iov;
  i = 0;
  while (i < key_count)
    {
      size_t key_len;

      iov->iov_base = " ";
      iov->iov_len = 1;
      ++iov;
      if (c->prefix_len)
        {
          iov->iov_base = c->prefix;
          iov->iov_len = c->prefix_len;
          ++iov;
        }
      iov->iov_base = (void *) get_key(arg, i, &key_len);
      iov->iov_len = key_len;
      ++iov;
      ++i;
    }
  iov->iov_base = "\r\n";
  iov->iov_len = 2;
  ++iov;

  command_state_init(state, s->fd, (iov - state->iov_buf),
                     (c->prefix_len ? 3 : 2), key_count,
                     c->prefix_len, parse_get_reply);
  get_result_state_init(&state->get_result, alloc_value, arg);
  res = process_command(state);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_delete(struct client *c, const char *key, size_t key_len,
              delay_type delay)
{
  size_t request_size =
    (sizeof(struct command_state)
     + sizeof(struct iovec) * ((c->prefix_len ? 4 : 3) - 1)
     + sizeof(" 4294967295\r\n"));
  struct command_state *state;
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
        return MEMCACHED_FAILURE;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  state = (struct command_state *) s->request_buf;
  iov = state->iov_buf;

  iov->iov_base = "delete ";
  iov->iov_len = 7;
  ++iov;
  if (c->prefix_len)
    {
      iov->iov_base = c->prefix;
      iov->iov_len = c->prefix_len;
      ++iov;
    }
  iov->iov_base = (void *) key;
  iov->iov_len = key_len;
  ++iov;
  buf = (char *) (iov + 1);
  iov->iov_base = buf;
  iov->iov_len = sprintf(buf, " " FMT_DELAY "\r\n", delay);
  ++iov;

  command_state_init(state, s->fd, (iov - state->iov_buf),
                     (c->prefix_len ? 2 : 1), 1,
                     c->prefix_len, parse_delete_reply);
  res = process_command(state);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}


int
client_flush_all(struct client *c, delay_type delay)
{
  static const size_t request_size =
    (sizeof(struct command_state) + sizeof(struct iovec) * (1 - 1)
     + sizeof("flush_all 4294967295\r\n"));
  struct command_state *state;
  struct iovec *iov;
  char *buf;
  int server_index, res;
  struct server *s;

  /* FIXME: loop over all servers, distribute the delay.  */
  server_index = client_get_server_index(c, NULL, 0);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  s = &c->servers[server_index];

  if (s->request_buf_size < request_size)
    {
      void *buf = realloc(s->request_buf, request_size);
      if (! buf)
        return MEMCACHED_FAILURE;

      s->request_buf = buf;
      s->request_buf_size = request_size;
    } 

  state = (struct command_state *) s->request_buf;
  iov = state->iov_buf;

  buf = (char *) (iov + 1);
  iov->iov_base = buf;
  iov->iov_len = sprintf(buf, "flush_all " FMT_DELAY "\r\n", delay);

  command_state_init(state, s->fd, 1, 0, 0, c->prefix_len, parse_ok_reply);
  res = process_command(state);

  if (res == MEMCACHED_UNKNOWN || res == MEMCACHED_CLOSED
      || (c->close_on_error && res == MEMCACHED_ERROR))
    client_mark_failed(c, server_index);

  return res;
}
