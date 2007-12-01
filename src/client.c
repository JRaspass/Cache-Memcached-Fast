#include "client.h"
#include "connect.h"
#include "parse_keyword.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/uio.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/types.h>


#ifndef MAX_IOVEC
#define MAX_IOVEC  1024
#endif


/* REPLY_BUF_SIZE should be large enough to contain first reply line.  */
#define REPLY_BUF_SIZE  1024


static const char eol[2] = "\r\n";


struct value_state
{
  struct value_object *object;

  flags_type flags;
  void *ptr;
  value_size_type size;
};


static inline
void
value_state_reset(struct value_state *state, struct value_object *o)
{
  state->object = o;

#if 0 /* No need to initialize the following.  */
  state->ptr = NULL;
  state->size = 0;
#endif
}


struct command_state;
typedef int (*parse_reply_func)(struct command_state *state);


enum command_phase
{
  PHASE_SEND,
  PHASE_RECEIVE,
  PHASE_PARSE,
  PHASE_VALUE,
  PHASE_DONE
};


struct command_state
{
  const struct client *client;
  int fd;

  /*
    If the command needs additional character buffer, the space after
    the last struct iovec is used.  Hence iov_buf_size may be not
    multiple of sizeof(struct iovec).
  */
  struct iovec *iov_buf;
  size_t iov_buf_size;

  int phase;

  char buf[REPLY_BUF_SIZE];
  char *pos;
  char *end;
  char *eol;
  int match;

  struct iovec *iov;
  int iov_count;
  int write_offset;
  struct iovec *key;
  int key_count;
  int key_index;

  parse_reply_func parse_reply;

  int active;

  struct value_state value;
};


static inline
void
command_state_init(struct command_state *state,
                   const struct client *c)
{
  state->client = c;
  state->fd = -1;
  state->iov_buf = NULL;
  state->iov_buf_size = 0;
}


static inline
void
command_state_destroy(struct command_state *state)
{
  free(state->iov_buf);
  if (state->fd != -1)
    close(state->fd);
}


static inline
void
command_state_reset(struct command_state *state, int first_key_index,
                    int key_count, parse_reply_func parse_reply)
{
  state->key = &state->iov_buf[first_key_index];
  state->key_count = key_count;
  state->parse_reply = parse_reply;

  state->phase = PHASE_SEND;
  state->iov = state->iov_buf;
  state->write_offset = 0;
  state->key_index = 0;
  state->active = 1;

#if 0 /* No need to initialize the following.  */
  state->pos = state->end = state->eol = state->buf;
  state->match = NO_MATCH;
#endif
}


struct server
{
  char *host;
  char *port;
  struct command_state cmd_state;
};


static inline
int
server_init(struct server *s, const struct client *c,
            const char *host, size_t host_len,
            const char *port, size_t port_len)
{
  s->host = (char *) malloc(host_len + 1 + port_len + 1);
  if (! s->host)
    return MEMCACHED_FAILURE;

  s->port = s->host + host_len + 1;
  memcpy(s->host, host, host_len);
  s->host[host_len] = '\0';
  memcpy(s->port, port, port_len);
  s->port[port_len] = '\0';

  command_state_init(&s->cmd_state, c);

  return MEMCACHED_SUCCESS;
}


static inline
void
server_destroy(struct server *s)
{
  free(s->host); /* This also frees port string.  */
  command_state_destroy(&s->cmd_state);
}


struct client
{
  struct server *servers;
  int server_count;
  int server_capacity;

  char *prefix;
  size_t prefix_len;

  int key_step;
  int connect_timeout;          /* 1/1000 sec.  */
  int io_timeout;               /* 1/1000 sec.  */
  int close_on_error;
  int noreply;
};


struct client *
client_init()
{
  struct client *c = malloc(sizeof(struct client));
  if (! c)
    return NULL;

  c->servers = NULL;
  c->server_capacity = 0;
  c->server_count = 0;

  c->connect_timeout = 250;
  c->io_timeout = 1000;
  c->prefix = NULL;
  c->prefix_len = 0;
  /* Keys are interleaved with spaces.  */
  c->key_step = 2;
  c->close_on_error = 1;
  c->noreply = 0;

  return c;
}


void
client_destroy(struct client *c)
{
  int i;

  for (i = 0; i < c->server_count; ++i)
    server_destroy(&c->servers[i]);

  free(c->servers);
  free(c->prefix);
  free(c);
}


void
client_set_connect_timeout(struct client *c, int to)
{
  c->connect_timeout = to;
}


void
client_set_io_timeout(struct client *c, int to)
{
  c->io_timeout = to;
}


void
client_set_close_on_error(struct client *c, int enable)
{
  c->close_on_error = enable;
}


void
client_set_noreply(struct client *c, int enable)
{
  c->noreply = enable;
  if (enable)
    client_set_close_on_error(c, 1);
}


int
client_add_server(struct client *c, const char *host, size_t host_len,
                  const char *port, size_t port_len)
{
  int res;

  if (c->server_count == c->server_capacity)
    {
      int capacity = (c->server_capacity > 0 ? c->server_capacity * 2 : 1);
      struct server *s =
        (struct server *) realloc(c->servers,
                                  capacity * sizeof(struct server));
      if (! s)
        return MEMCACHED_FAILURE;

      c->servers = s;
      c->server_capacity = capacity;
    }

  res = server_init(&c->servers[c->server_count], c,
                    host, host_len, port, port_len);
  if (res != MEMCACHED_SUCCESS)
    return res;

  ++c->server_count;

  return MEMCACHED_SUCCESS;
}


int
client_set_prefix(struct client *c, const char *ns, size_t ns_len)
{
  char *s;

  if (ns_len == 0)
    {
      free(c->prefix);
      c->prefix = NULL;
      c->prefix_len = 0;
      /* Keys are interleaved with spaces.  */
      c->key_step = 2;
      return MEMCACHED_SUCCESS;
    }

  s = (char *) realloc(c->prefix, ns_len + 1);
  if (! s)
    return MEMCACHED_FAILURE;

  /* Keys are interleaved with spaces and prefix.  */
  c->key_step = 3;

  memcpy(s, ns, ns_len);
  s[ns_len] = '\0';

  c->prefix = s;
  c->prefix_len = ns_len;

  return MEMCACHED_SUCCESS;
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
readv_restart(int fd, const struct iovec *iov, int count)
{
  ssize_t res;

  do
    res = readv(fd, iov, count);
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


/*
  parse_key() assumes that one key definitely matches.
*/
static
int
parse_key(struct command_state *state)
{
  char *key_pos;

  /* Skip over the prefix.  */
  state->pos += state->client->prefix_len;

  key_pos = (char *) state->key->iov_base;
  while (state->key_count > 1)
    {
      char *key_end, *prefix_key;
      size_t prefix_len;

      key_end = (char *) state->key->iov_base + state->key->iov_len;
      while (key_pos != key_end && *state->pos == *key_pos)
        {
          ++key_pos;
          ++state->pos;
        }

      if (key_pos == key_end)
        break;

      prefix_key = (char *) state->key->iov_base;
      prefix_len = key_pos - prefix_key;
      /*
        TODO: Below it might be faster to compare the tail of the key
        before comparing the head.
      */
      do
        {
          ++state->key_index;
          state->key += state->client->key_step;
        }
      while (--state->key_count > 1
             && (state->key->iov_len < prefix_len
                 || memcmp(state->key->iov_base,
                           prefix_key, prefix_len) != 0));

      key_pos = (char *) state->key->iov_base + prefix_len;
    }

  if (state->key_count == 1)
    {
      while (*state->pos != ' ')
        ++state->pos;
    }

  --state->key_count;
  ++state->key_index;
  state->key += state->client->key_step;

  return MEMCACHED_SUCCESS;
}


static
int
read_value(struct command_state *state)
{
  value_size_type size;
  size_t remains;

  size = state->end - state->pos;
  if (size > state->value.size)
    size = state->value.size;
  if (size > 0)
    {
      memcpy(state->value.ptr, state->pos, size);
      state->value.size -= size;
      state->value.ptr += size;
      state->pos += size;
    }

  remains = state->end - state->pos;
  if (remains < sizeof(eol))
    {
      struct iovec iov[2], *piov;

      state->pos = memmove(state->buf, state->pos, remains);
      state->end = state->buf + remains;

      iov[0].iov_base = state->value.ptr;
      iov[0].iov_len = state->value.size;
      iov[1].iov_base = state->end;
      iov[1].iov_len = REPLY_BUF_SIZE - remains;
      piov = &iov[state->value.size > 0 ? 0 : 1];

      do
        {
          ssize_t res;

          res = readv_restart(state->fd, piov, iov + 2 - piov);
          if (res <= 0)
            {
              state->value.ptr = iov[0].iov_base;
              state->value.size = iov[0].iov_len;
              state->end = iov[1].iov_base;

              if (res == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
                return MEMCACHED_EAGAIN;

              state->value.object->free(state->value.object->arg);
              return MEMCACHED_CLOSED;
            }

          if ((size_t) res >= piov->iov_len)
            {
              piov->iov_base += piov->iov_len;
              res -= piov->iov_len;
              piov->iov_len = 0;
              ++piov;
            }

          piov->iov_len -= res;
          piov->iov_base += res;
        }
      while ((size_t) ((char *) iov[1].iov_base - state->pos) < sizeof(eol));

      state->end = iov[1].iov_base;
    }

  if (memcmp(state->pos, eol, sizeof(eol)) != 0)
    {
      state->value.object->free(state->value.object->arg);
      return MEMCACHED_UNKNOWN;
    }
  state->pos += sizeof(eol);
  state->eol = state->pos;

  state->value.object->store(state->value.object->arg,
                             state->key_index - 1, state->value.flags);

  return MEMCACHED_SUCCESS;
}


static inline
int
swallow_eol(struct command_state *state, int skip, int done)
{
  if (! skip && state->eol - state->pos != sizeof(eol))
    return MEMCACHED_UNKNOWN;

  state->pos = state->eol;

  if (done)
    state->phase = PHASE_DONE;

  return MEMCACHED_SUCCESS;
}


static
int
parse_get_reply(struct command_state *state)
{
  int res, match_count;
  flags_type flags;
  value_size_type value_size;
  void *value;

  switch (state->match)
    {
    case MATCH_END:
      return swallow_eol(state, 0, 1);

    default:
      return MEMCACHED_UNKNOWN;

    case MATCH_VALUE:
      break;
    }

  while (*state->pos == ' ')
    ++state->pos;

  res = parse_key(state);
  if (res != MEMCACHED_SUCCESS)
    return res;

  res = sscanf(state->pos, " " FMT_FLAGS " " FMT_VALUE_SIZE "%n",
               &flags, &value_size, &match_count);
  if (res != 2)
    return MEMCACHED_UNKNOWN;

  state->pos += match_count;

  res = swallow_eol(state, 0, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  value = state->value.object->alloc(state->value.object->arg, value_size);
  if (! value)
    return MEMCACHED_FAILURE;

  state->value.flags = flags;
  state->value.ptr = value;
  state->value.size = value_size;

  state->phase = PHASE_VALUE;

  return MEMCACHED_SUCCESS;
}


static
int
parse_set_reply(struct command_state *state)
{
  int res;

  switch (state->match)
    {
    case MATCH_STORED:
      return swallow_eol(state, 0, 1);

    case MATCH_NOT_STORED:
      res = swallow_eol(state, 0, 1);

      return (res == MEMCACHED_SUCCESS ? MEMCACHED_FAILURE : res);

    default:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
parse_delete_reply(struct command_state *state)
{
  int res;

  switch (state->match)
    {
    case MATCH_DELETED:
      return swallow_eol(state, 0, 1);

    case MATCH_NOT_FOUND:
      res = swallow_eol(state, 0, 1);

      return (res == MEMCACHED_SUCCESS ? MEMCACHED_FAILURE : res);

    default:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
parse_ok_reply(struct command_state *state)
{
  switch (state->match)
    {
    case MATCH_OK:
      return swallow_eol(state, 0, 1);

    default:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
send_request(struct command_state *state)
{
  while (state->iov_count > 0)
    {
      int count;
      ssize_t res;
      size_t len;

      count = (state->iov_count < MAX_IOVEC
               ? state->iov_count : MAX_IOVEC);

      state->iov->iov_base += state->write_offset;
      state->iov->iov_len -= state->write_offset;
      len = state->iov->iov_len;

      res = writev_restart(state->fd, state->iov, count);

      state->iov->iov_base -= state->write_offset;
      state->iov->iov_len += state->write_offset;

      if (res == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
        return MEMCACHED_EAGAIN;
      if (res <= 0)
        return MEMCACHED_CLOSED;

      while ((size_t) res >= len)
        {
          res -= len;
          ++state->iov;
          if (--state->iov_count == 0)
            break;
          len = state->iov->iov_len;
          state->write_offset = 0;
        }
      state->write_offset += res;
    }

  return MEMCACHED_SUCCESS;
}


static
int
receive_reply(struct command_state *state)
{
  while (state->eol != state->end && *state->eol != eol[sizeof(eol) - 1])
    ++state->eol;

  while (state->eol == state->end)
    {
      size_t size;
      ssize_t res;

      size = REPLY_BUF_SIZE - (state->end - state->buf);
      if (size == 0)
        {
          if (state->pos != state->buf)
            {
              size_t len = state->end - state->pos;
              state->pos = memmove(state->buf, state->pos, len);
              state->end -= REPLY_BUF_SIZE - len;
              state->eol -= REPLY_BUF_SIZE - len;
              continue;
            }
          else
            {
              return MEMCACHED_UNKNOWN;
            }
        }

      res = read_restart(state->fd, state->end, size);
      if (res == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
        return MEMCACHED_EAGAIN;
      if (res <= 0)
        return MEMCACHED_CLOSED;

      state->end += res;

      while (state->eol != state->end && *state->eol != eol[sizeof(eol) - 1])
        ++state->eol;
    }

  if ((size_t) (state->eol - state->buf) < sizeof(eol) - 1
      || memcmp(state->eol - (sizeof(eol) - 1), eol, sizeof(eol) - 1) != 0)
    return MEMCACHED_UNKNOWN;

  ++state->eol;

  return MEMCACHED_SUCCESS;
}


static
int
parse_reply(struct command_state *state)
{
  int res, skip;

  switch (state->match)
    {
    case MATCH_ERROR:
    case MATCH_CLIENT_ERROR:
    case MATCH_SERVER_ERROR:
      skip = (state->match != MATCH_ERROR);
      res = swallow_eol(state, skip, 1);

      return (res == MEMCACHED_SUCCESS ? MEMCACHED_ERROR : res);

    default:
      return state->parse_reply(state);

    case NO_MATCH:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
process_command(struct command_state *state)
{
  int res;

  while (1)
    {
      switch (state->phase)
        {
        case PHASE_SEND:
          res = send_request(state);
          if (res != MEMCACHED_SUCCESS)
            return res;

          if (! state->parse_reply)
            return MEMCACHED_SUCCESS;

          state->pos = state->end = state->eol = state->buf;

          state->phase = PHASE_RECEIVE;

          /* Fall into below.  */

        case PHASE_RECEIVE:
          res = receive_reply(state);
          if (res != MEMCACHED_SUCCESS)
            return res;

          state->match = parse_keyword(&state->pos);

          state->phase = PHASE_PARSE;

          /* Fall into below.  */

        case PHASE_PARSE:
          res = parse_reply(state);
          if (res != MEMCACHED_SUCCESS)
            return res;

          if (state->phase != PHASE_DONE)
            break;

          /* Fall into below.  */

        case PHASE_DONE:
          if (state->pos != state->end)
            return MEMCACHED_UNKNOWN;

          return MEMCACHED_SUCCESS;

        case PHASE_VALUE:
          res = read_value(state);
          if (res != MEMCACHED_SUCCESS)
            return res;

          state->phase = PHASE_RECEIVE;

          break;
        }
    }
}


static
void
client_mark_failed(struct client *c, int server_index)
{
  struct server *s;

  s = &c->servers[server_index];

  if (s->cmd_state.fd != -1)
    {
      close(s->cmd_state.fd);
      s->cmd_state.fd = -1;
    }
}


static
int
process_commands(struct client *c)
{
  int result = MEMCACHED_FAILURE;

  while (1)
    {
      int i, max_fd, res;
      fd_set write_set, read_set;

      max_fd = -1;
      FD_ZERO(&write_set);
      FD_ZERO(&read_set);
      for (i = 0; i < c->server_count; ++i)
        {
          struct command_state *state = &c->servers[i].cmd_state;

          if (state->active)
            {
              if (max_fd < state->fd)
                max_fd = state->fd;

              if (state->phase == PHASE_SEND)
                FD_SET(state->fd, &write_set);
              else
                FD_SET(state->fd, &read_set);
            }
        }

      if (max_fd == -1)
        break;

      do
        res = select(max_fd + 1, &read_set, &write_set, NULL, NULL);
      while (res == -1 && errno == EINTR);

      /*
        On error or timeout close all active connections.  Otherwise
        we might receive garbage on them later.
      */
      if (res <= 0)
        {
          for (i = 0; i < c->server_count; ++i)
            {
              struct command_state *state = &c->servers[i].cmd_state;

              if (state->active)
                {
                  state->active = 0;
                  client_mark_failed(c, i);
                }
            }

          break;
        }

      for (i = 0; i < c->server_count; ++i)
        {
          struct command_state *state = &c->servers[i].cmd_state;

          if (FD_ISSET(state->fd, &read_set)
              || FD_ISSET(state->fd, &write_set))
            {
              res = process_command(state);
              switch (res)
                {
                case MEMCACHED_EAGAIN:
                  break;

                case MEMCACHED_SUCCESS:
                  result = MEMCACHED_SUCCESS;
                  state->active = 0;
                  break;

                case MEMCACHED_FAILURE:
                  state->active = 0;
                  break;

                case MEMCACHED_ERROR:
                  state->active = 0;
                  if (c->close_on_error)
                    client_mark_failed(c, i);
                  break;

                case MEMCACHED_UNKNOWN:
                case MEMCACHED_CLOSED:
                  state->active = 0;
                  client_mark_failed(c, i);
                  break;
                }
            }
        }
    }

  return result;
}


static
int
get_server_fd(struct client *c, int index)
{
  struct server *s;
  struct command_state *state;

  s = &c->servers[index];
  state = &s->cmd_state;
  if (state->fd == -1)
    state->fd = client_connect_inet(s->host, s->port, 1, c->connect_timeout);

  if (state->fd == -1)
    client_mark_failed(c, index);

  return state->fd;
}


static
int
client_get_server_index(struct client *c, const char *key, size_t key_len)
{
  int index, fd;

  if (c->server_count == 0)
    return -1;

  if (c->server_count == 1 || key_len == 0)
    {
      index = 0;
    }
  else
    {
      /* FIXME: implement better hash function.  */

      //index = key[key_len - 1] % c->server_count;

      if (key || key_len) {}
      index = 0;
    }

  fd = get_server_fd(c, index);

  return (fd >= 0 ? index : -1);
}


static inline
int
iov_buf_extend(struct command_state *state, size_t size)
{
  if (state->iov_buf_size < size)
    {
      struct iovec *buf =
        (struct iovec *) realloc(state->iov_buf, size);
      if (! buf)
        return MEMCACHED_FAILURE;

      state->iov_buf = buf;
      state->iov_buf_size = size;
    }

  return MEMCACHED_SUCCESS;
}


static inline
void
iov_push(struct command_state *state, void *buf, size_t buf_size)
{
  struct iovec *iov = &state->iov_buf[state->iov_count++];
  iov->iov_base = buf;
  iov->iov_len = buf_size;
}


#define STR_WITH_LEN(str) (str), (sizeof(str) - 1)


int
client_set(struct client *c, enum set_cmd_e cmd,
           const char *key, size_t key_len,
           flags_type flags, exptime_type exptime,
           const void *value, value_size_type value_size, int noreply)
{
  int use_noreply = (noreply && c->noreply);
  size_t request_size =
    (sizeof(struct iovec) * (c->prefix_len ? 6 : 5)
     + sizeof(" 4294967295 2147483647 18446744073709551615 noreply\r\n"));
  struct command_state *state;
  struct iovec *buf_iov;
  char *buf;
  int server_index, res;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  state->iov_count = 0;

  switch (cmd)
    {
    case CMD_SET:
      iov_push(state, STR_WITH_LEN("set "));
      break;

    case CMD_ADD:
      iov_push(state, STR_WITH_LEN("add "));
      break;

    case CMD_REPLACE:
      iov_push(state, STR_WITH_LEN("replace "));
      break;

    case CMD_APPEND:
      iov_push(state, STR_WITH_LEN("append "));
      break;

    case CMD_PREPEND:
      iov_push(state, STR_WITH_LEN("prepend "));
      break;
    }
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);
  buf_iov = &state->iov_buf[state->iov_count];
  iov_push(state, NULL, 0);
  iov_push(state, (void *) value, value_size);
  iov_push(state, STR_WITH_LEN("\r\n"));

  buf = (char *) &state->iov_buf[state->iov_count];
  buf_iov->iov_base = buf;
  buf_iov->iov_len = sprintf(buf, " " FMT_FLAGS " " FMT_EXPTIME
                             " " FMT_VALUE_SIZE "%s\r\n",
                             flags, exptime, value_size,
                             (use_noreply ? " noreply" : ""));

  command_state_reset(state, (c->prefix_len ? 2 : 1), 1,
                      (use_noreply ? NULL : parse_set_reply));

  return process_commands(c);
}


int
client_get(struct client *c, const char *key, size_t key_len,
           struct value_object *o)
{
  size_t request_size = (sizeof(struct iovec) * (c->prefix_len ? 4 : 3));
  struct command_state *state;
  int server_index, res;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  state->iov_count = 0;

  iov_push(state, STR_WITH_LEN("get "));
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);
  iov_push(state, STR_WITH_LEN("\r\n"));

  command_state_reset(state, (c->prefix_len ? 2 : 1), 1, parse_get_reply);
  value_state_reset(&state->value, o);

  return process_commands(c);
}


int
client_mget(struct client *c, int key_count, get_key_func get_key,
            struct value_object *o)
{
  size_t min_request_size = (sizeof(struct iovec) * 2);
  struct command_state *state;
  int i;

  for (i = 0; i < key_count; ++i)
    {
      char *key;
      size_t key_len;
      size_t size;
      int server_index, res;

      key = get_key(o->arg, i, &key_len);

      server_index = client_get_server_index(c, key, key_len);
      if (server_index == -1)
        continue;

      state = &c->servers[server_index].cmd_state;

      size = (state->iov_buf_size
              + sizeof(struct iovec) * (c->prefix_len ? 3 : 2));
      if (! state->active)
        size += min_request_size;

      res = iov_buf_extend(state, size);
      if (res != MEMCACHED_SUCCESS)
        {
          state->active = 0;
          continue;
        }

      if (! state->active)
        {
          state->active = 1;
          state->iov_count = 0;

          iov_push(state, STR_WITH_LEN("get"));
        }

      iov_push(state, STR_WITH_LEN(" "));
      if (c->prefix_len)
        iov_push(state, c->prefix, c->prefix_len);
      iov_push(state, (void *) key, key_len);
    }

  for (i = 0; i < c->server_count; ++i)
    {
      state = &c->servers[i].cmd_state;

      if (state->active)
        {
          iov_push(state, STR_WITH_LEN("\r\n"));

          command_state_reset(state, (c->prefix_len ? 3 : 2), key_count,
                              parse_get_reply);
          value_state_reset(&state->value, o);
        }
    }

  return process_commands(c);
}


int
client_delete(struct client *c, const char *key, size_t key_len,
              delay_type delay, int noreply)
{
  int use_noreply = (noreply && c->noreply);
  size_t request_size =
    (sizeof(struct iovec) * (c->prefix_len ? 4 : 3)
     + sizeof(" 4294967295 noreply\r\n"));
  struct command_state *state;
  struct iovec *buf_iov;
  char *buf;
  int server_index, res;

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  state->iov_count = 0;

  iov_push(state, STR_WITH_LEN("delete "));
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);
  buf_iov = &state->iov_buf[state->iov_count];
  iov_push(state, NULL, 0);
  buf = (char *) &state->iov_buf[state->iov_count];
  buf_iov->iov_base = buf;
  buf_iov->iov_len = sprintf(buf, " " FMT_DELAY "%s\r\n", delay,
                             (use_noreply ? " noreply" : ""));

  command_state_reset(state, (c->prefix_len ? 2 : 1), 1,
                      (use_noreply ? NULL : parse_delete_reply));

  return process_commands(c);
}


int
client_flush_all(struct client *c, delay_type delay, int noreply)
{
  int use_noreply = (noreply && c->noreply);
  static const size_t request_size =
    (sizeof(struct iovec) * 1 + sizeof("flush_all 4294967295 noreply\r\n"));
  double ddelay = delay, delay_step = 0.0;
  int i;

  if (c->server_count > 1)
    delay_step = ddelay / (c->server_count - 1);
  ddelay += delay_step;

  for (i = 0; i < c->server_count; ++i)
    {
      struct command_state *state;
      struct iovec *buf_iov;
      char *buf;
      int fd, res;

      ddelay -= delay_step;

      fd = get_server_fd(c, i);
      if (fd == -1)
        continue;

      state = &c->servers[i].cmd_state;

      res = iov_buf_extend(state, request_size);
      if (res != MEMCACHED_SUCCESS)
        continue;

      state->iov_count = 0;

      buf_iov = &state->iov_buf[state->iov_count];
      iov_push(state, NULL, 0);
      buf = (char *) &state->iov_buf[state->iov_count];
      buf_iov->iov_base = buf;
      buf_iov->iov_len = sprintf(buf, "flush_all " FMT_DELAY "%s\r\n",
                                 (delay_type) ddelay,
                                 (use_noreply ? " noreply" : ""));

      command_state_reset(state, 0, 0, (use_noreply ? NULL : parse_ok_reply));
    }

  return process_commands(c);
}
