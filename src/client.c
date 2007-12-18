/*
  Copyright (C) 2007 Tomash Brechko.  All rights reserved.

  When used to build Perl module:

  This library is free software; you can redistribute it and/or modify
  it under the same terms as Perl itself, either Perl version 5.8.8
  or, at your option, any later version of Perl 5 you may have
  available.

  When used as a standalone library:

  This library is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as
  published by the Free Software Foundation; either version 2.1 of the
  License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.
*/

#include "client.h"
#include "connect.h"
#include "parse_keyword.h"
#include "dispatch_key.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/uio.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <signal.h>
#include <time.h>


#ifndef MAX_IOVEC
#define MAX_IOVEC  1024
#endif


/* REPLY_BUF_SIZE should be large enough to contain first reply line.  */
#define REPLY_BUF_SIZE  1024


static const char eol[2] = "\r\n";


typedef unsigned long long generation_type;


struct value_state
{
  struct value_object *object;

  flags_type flags;
  void *ptr;
  value_size_type size;
  int use_cas;
  cas_type cas;
};


static inline
void
value_state_reset(struct value_state *state, struct value_object *o,
                  int use_cas)
{
  state->object = o;
  state->use_cas = use_cas;

#if 0 /* No need to initialize the following.  */
  state->ptr = NULL;
  state->size = 0;
#endif
}


struct arith_state
{
  arith_type *result;
};


static inline
void
arith_state_reset(struct arith_state *state, arith_type *result)
{
  state->result = result;
}


struct embedded_state
{
  struct value_object *object;

  void *ptr;
};


static inline
void
embedded_state_reset(struct embedded_state *state, struct value_object *o)
{
  state->object = o;
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


struct client;


struct command_state
{
  struct client *client;
  int fd;

  /*
    If the command needs additional character buffer, the space after
    the last struct iovec is used.  Hence iov_buf_size may be not
    multiple of sizeof(struct iovec).
  */
  struct iovec *iov_buf;
  size_t iov_buf_size;

  generation_type generation;

  int phase;

  char buf[REPLY_BUF_SIZE];
  char *pos;
  char *end;
  char *eol;
  int match;

  struct iovec *iov;
  int iov_count;
  int write_offset;
  int key_offset;
  struct iovec *key;
  int key_count;
  int key_index;
  int key_head;
  int key_tail;

  parse_reply_func parse_reply;

  union
  {
    struct value_state value;
    struct arith_state arith;
    struct embedded_state embedded;
  } u;
};


static inline
void
command_state_init(struct command_state *state,
                   struct client *c)
{
  state->client = c;
  state->fd = -1;
  state->iov_buf = NULL;
  state->iov_buf_size = 0;
  state->generation = 0;
}


static inline
void
command_state_destroy(struct command_state *state)
{
  free(state->iov_buf);
  if (state->fd != -1)
    close(state->fd);
}


struct server
{
  char *host;
  size_t host_len;
  char *port;
  int failure_count;
  time_t failure_expires;
  struct command_state cmd_state;
};


static inline
int
server_init(struct server *s, struct client *c,
            const char *host, size_t host_len,
            const char *port, size_t port_len)
{
  if (port)
    s->host = (char *) malloc(host_len + 1 + port_len + 1);
  else
    s->host = (char *) malloc(host_len + 1);

  if (! s->host)
    return MEMCACHED_FAILURE;

  memcpy(s->host, host, host_len);
  s->host[host_len] = '\0';
  s->host_len = host_len;

  if (port)
    {
      s->port = s->host + host_len + 1;
      memcpy(s->port, port, port_len);
      s->port[port_len] = '\0';
    }
  else
    {
      s->port = NULL;
    }

  s->failure_count = 0;
  s->failure_expires = 0;

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


struct key_node
{
  int key;
  int next;
};


struct client
{
  struct server *servers;
  int server_count;
  int server_capacity;

  struct dispatch_state dispatch;

  char *prefix;
  size_t prefix_len;

  int key_step;
  int connect_timeout;          /* 1/1000 sec.  */
  int io_timeout;               /* 1/1000 sec.  */
  int max_failures;
  int failure_timeout;          /* 1 sec.  */
  int close_on_error;
  int noreply;

  struct key_node *key_list;
  int key_list_count;
  int key_list_capacity;

  generation_type generation;
};


static inline
void
command_state_reset(struct command_state *state, int key_offset,
                    int key_count, parse_reply_func parse_reply)
{
  state->key_offset = key_offset;
  state->key_count = key_count;
  state->parse_reply = parse_reply;

  state->phase = PHASE_SEND;
  state->iov = state->iov_buf;
  state->write_offset = 0;
  state->key_head = state->key_tail = -1;
  state->iov_count = 0;
  state->generation = state->client->generation;

#if 0 /* No need to initialize the following.  */
  state->key = NULL;
  state->key_index = 0;
  state->pos = state->end = state->eol = state->buf;
  state->match = NO_MATCH;
#endif
}


static inline
int
is_active(struct command_state *state)
{
  return (state->generation == state->client->generation);
}


static inline
void
deactivate(struct command_state *state)
{
  state->generation = state->client->generation - 1;
}


static inline
int
get_key_index(struct command_state *state)
{
  return state->client->key_list[state->key_head].key;
}


static inline
void
next_key_index(struct command_state *state)
{
  state->key_head = state->client->key_list[state->key_head].next;
}


struct client *
client_init()
{
  struct client *c = malloc(sizeof(struct client));
  if (! c)
    return NULL;

  c->servers = NULL;
  c->server_count = c->server_capacity = 0;

  dispatch_init(&c->dispatch);

  c->connect_timeout = 250;
  c->io_timeout = 1000;
  c->prefix = NULL;
  c->prefix_len = 0;
  /* Keys are interleaved with spaces.  */
  c->key_step = 2;
  c->max_failures = 0;
  c->failure_timeout = 10;
  c->close_on_error = 1;
  c->noreply = 0;

  c->key_list = NULL;
  c->key_list_count = c->key_list_capacity = 0;

  c->generation = 1;            /* Different from initial command state.  */

  return c;
}


void
client_destroy(struct client *c)
{
  int i;

  for (i = 0; i < c->server_count; ++i)
    server_destroy(&c->servers[i]);

  dispatch_destroy(&c->dispatch);

  free(c->servers);
  free(c->prefix);
  free(c->key_list);
  free(c);
}


int
client_set_ketama_points(struct client *c, int ketama_points)
{
  /* Should be called before we added any server.  */
  if (c->server_count > 0 || ketama_points < 0)
    return MEMCACHED_FAILURE;

  dispatch_set_ketama_points(&c->dispatch, ketama_points);

  return MEMCACHED_SUCCESS;
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
client_set_max_failures(struct client *c, int f)
{
  c->max_failures = f;
}


void
client_set_failure_timeout(struct client *c, int to)
{
  c->failure_timeout = to;
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
                  const char *port, size_t port_len, double weight)
{
  int res;

  if (weight <= 0.0)
    return MEMCACHED_FAILURE;

  if (c->server_count == c->server_capacity)
    {
      int capacity = (c->server_capacity > 0 ? c->server_capacity + 1 : 1);
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

  res = dispatch_add_server(&c->dispatch, host, host_len, port, port_len,
                            weight, c->server_count);
  if (res == -1)
    return MEMCACHED_FAILURE;

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


#ifndef MSG_NOSIGNAL

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

#else  /* MSG_NOSIGNAL */

static inline
ssize_t
writev_restart(int fd, const struct iovec *iov, int count)
{
  struct msghdr msg;
  ssize_t res;

  memset(&msg, 0, sizeof(msg));
  msg.msg_iov = (struct iovec *) iov;
  msg.msg_iovlen = count;

  do
    res = sendmsg(fd, &msg, MSG_NOSIGNAL);
  while (res == -1 && errno == EINTR);

  return res;
}

#endif /* MSG_NOSIGNAL */


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

      if (key_pos == key_end && *state->pos == ' ')
        break;

      prefix_key = (char *) state->key->iov_base;
      prefix_len = key_pos - prefix_key;
      /*
        TODO: Below it might be faster to compare the tail of the key
        before comparing the head.
      */
      do
        {
          next_key_index(state);
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
  state->key += state->client->key_step;
  state->key_index = get_key_index(state);
  next_key_index(state);

  return MEMCACHED_SUCCESS;
}


static
int
read_value(struct command_state *state)
{
  value_size_type size;
  size_t remains;

  size = state->end - state->pos;
  if (size > state->u.value.size)
    size = state->u.value.size;
  if (size > 0)
    {
      memcpy(state->u.value.ptr, state->pos, size);
      state->u.value.size -= size;
      state->u.value.ptr = (char *) state->u.value.ptr + size;
      state->pos += size;
    }

  remains = state->end - state->pos;
  if (remains < sizeof(eol))
    {
      struct iovec iov[2], *piov;

      state->pos = memmove(state->buf, state->pos, remains);
      state->end = state->buf + remains;

      iov[0].iov_base = state->u.value.ptr;
      iov[0].iov_len = state->u.value.size;
      iov[1].iov_base = state->end;
      iov[1].iov_len = REPLY_BUF_SIZE - remains;
      piov = &iov[state->u.value.size > 0 ? 0 : 1];

      do
        {
          ssize_t res;

          res = readv_restart(state->fd, piov, iov + 2 - piov);
          if (res <= 0)
            {
              state->u.value.ptr = iov[0].iov_base;
              state->u.value.size = iov[0].iov_len;
              state->end = iov[1].iov_base;

              if (res == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
                return MEMCACHED_EAGAIN;

              state->u.value.object->free(state->u.value.object->arg);
              return MEMCACHED_CLOSED;
            }

          if ((size_t) res >= piov->iov_len)
            {
              piov->iov_base = (char *) piov->iov_base + piov->iov_len;
              res -= piov->iov_len;
              piov->iov_len = 0;
              ++piov;
            }

          piov->iov_len -= res;
          piov->iov_base = (char *) piov->iov_base + res;
        }
      while ((size_t) ((char *) iov[1].iov_base - state->pos) < sizeof(eol));

      state->end = iov[1].iov_base;
    }

  if (memcmp(state->pos, eol, sizeof(eol)) != 0)
    {
      state->u.value.object->free(state->u.value.object->arg);
      return MEMCACHED_UNKNOWN;
    }
  state->pos += sizeof(eol);
  state->eol = state->pos;

  state->u.value.object->store(state->u.value.object->arg, state->key_index,
                               state->u.value.flags,
                               state->u.value.use_cas, state->u.value.cas);

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
parse_ull(struct command_state *state, unsigned long long *result)
{
  unsigned long long res = 0;
  const char *beg;

  while (*state->pos == ' ')
    ++state->pos;

  beg = state->pos;

  while (1)
    {
      switch (*state->pos)
        {
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9':
          res = res * 10 + (*state->pos - '0');
          ++state->pos;
          break;

        default:
          *result = res;
          return (beg != state->pos ? MEMCACHED_SUCCESS : MEMCACHED_UNKNOWN);
        }
    }
}


static
int
parse_get_reply(struct command_state *state)
{
  unsigned long long num;
  int res;

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

  res = parse_ull(state, &num);
  if (res != MEMCACHED_SUCCESS)
    return res;
  state->u.value.flags = num;

  res = parse_ull(state, &num);
  if (res != MEMCACHED_SUCCESS)
    return res;
  state->u.value.size = num;

  if (state->u.value.use_cas)
    {
      res = parse_ull(state, &num);
      if (res != MEMCACHED_SUCCESS)
        return res;
      state->u.value.cas = num;
    }

  res = swallow_eol(state, 0, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  state->u.value.ptr = state->u.value.object->alloc(state->u.value.object->arg,
                                                    state->u.value.size);
  if (! state->u.value.ptr)
    return MEMCACHED_FAILURE;

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
    case MATCH_EXISTS:
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
parse_arith_reply(struct command_state *state)
{
  unsigned long long num;
  int res;

  switch (state->match)
    {
    case MATCH_NOT_FOUND:
      res = swallow_eol(state, 0, 1);

      return (res == MEMCACHED_SUCCESS ? MEMCACHED_FAILURE : res);

    default:
      return MEMCACHED_UNKNOWN;

    case MATCH_0: case MATCH_1: case MATCH_2: case MATCH_3: case MATCH_4:
    case MATCH_5: case MATCH_6: case MATCH_7: case MATCH_8: case MATCH_9:
      break;
    }

  --state->pos;

  res = parse_ull(state, &num);
  if (res != MEMCACHED_SUCCESS)
    return res;
  *state->u.arith.result = num;

  /* Value may be space padded.  */
  res = swallow_eol(state, 1, 1);
  if (res != MEMCACHED_SUCCESS)
    return res;

  return MEMCACHED_SUCCESS;
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
parse_version_reply(struct command_state *state)
{
  const char *beg;
  size_t len;
  int res;

  switch (state->match)
    {
    default:
      return MEMCACHED_UNKNOWN;

    case MATCH_VERSION:
      break;
    }

  while (*state->pos == ' ')
    ++state->pos;

  beg = state->pos;

  res = swallow_eol(state, 1, 1);
  if (res != MEMCACHED_SUCCESS)
    return res;

  len = state->pos - sizeof(eol) - beg;

  state->u.embedded.ptr =
    state->u.embedded.object->alloc(state->u.embedded.object->arg, len);
  if (! state->u.embedded.ptr)
    return MEMCACHED_FAILURE;

  memcpy(state->u.embedded.ptr, beg, len);

  return MEMCACHED_SUCCESS;
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

      state->iov->iov_base =
        (char *) state->iov->iov_base + state->write_offset;
      state->iov->iov_len -= state->write_offset;
      len = state->iov->iov_len;

      res = writev_restart(state->fd, state->iov, count);

      state->iov->iov_base =
        (char *) state->iov->iov_base - state->write_offset;
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
          state->key = &state->iov_buf[state->key_offset];

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

  if (c->max_failures > 0)
    {
      time_t now = time(NULL);
      if (s->failure_expires < now)
        s->failure_count = 0;
      ++s->failure_count;
      /*
        Set timeout on first failure, and on max_failures.  The idea
        is that if max_failures had happened during failure_timeout,
        we do not retry in another failure_timeout seconds.  This is
        not entirely true: we remember the time of the first failure,
        but for exact accounting we would have to keep time of each
        failure.  However such exact measurement is not necessary.
      */
      if (s->failure_count == 1 || s->failure_count == c->max_failures)
        s->failure_expires = now + c->failure_timeout;
    }
}


static
int
process_commands(struct client *c)
{
  int result = MEMCACHED_FAILURE;
  struct timeval to, *pto = c->io_timeout > 0 ? &to : NULL;
  fd_set write_set, read_set;
  int first_iter = 1;

#ifndef MSG_NOSIGNAL
  struct sigaction orig, ignore;
  int res;

  ignore.sa_handler = SIG_IGN;
  sigemptyset(&ignore.sa_mask);
  ignore.sa_flags = 0;
  res = sigaction(SIGPIPE, &ignore, &orig);
  if (res == -1)
    return result;
#endif /* ! MSG_NOSIGNAL */

  while (1)
    {
      int max_fd, i, res;

      max_fd = -1;
      for (i = 0; i < c->server_count; ++i)
        {
          struct command_state *state = &c->servers[i].cmd_state;

          if (! is_active(state))
            continue;

          if (first_iter
              || FD_ISSET(state->fd, &read_set)
              || FD_ISSET(state->fd, &write_set))
            {
              res = process_command(state);
              switch (res)
                {
                case MEMCACHED_SUCCESS:
                  result = MEMCACHED_SUCCESS;
                  deactivate(state);
                  break;

                case MEMCACHED_FAILURE:
                  deactivate(state);
                  break;

                case MEMCACHED_ERROR:
                  deactivate(state);
                  if (c->close_on_error)
                    client_mark_failed(c, i);
                  break;

                case MEMCACHED_UNKNOWN:
                case MEMCACHED_CLOSED:
                  deactivate(state);
                  client_mark_failed(c, i);
                  break;

                case MEMCACHED_EAGAIN:
                  if (max_fd < state->fd)
                    max_fd = state->fd;
                  break;
                }
            }
          else
            {
              if (max_fd < state->fd)
                max_fd = state->fd;
            }
        }

      if (max_fd == -1)
        break;

      FD_ZERO(&write_set);
      FD_ZERO(&read_set);
      for (i = 0; i < c->server_count; ++i)
        {
          struct command_state *state = &c->servers[i].cmd_state;

          if (is_active(state))
            {
              if (state->phase == PHASE_SEND)
                FD_SET(state->fd, &write_set);
              else
                FD_SET(state->fd, &read_set);
            }
        }

      do
        {
          /*
            For maximum portability across systems that may or may not
            modify the timeout argument we treat it as undefined after
            the call, and reinitialize on every iteration.
          */
          if (pto)
            {
              pto->tv_sec = c->io_timeout / 1000;
              pto->tv_usec = (c->io_timeout % 1000) * 1000;
            }
          res = select(max_fd + 1, &read_set, &write_set, NULL, pto);
        }
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

              if (is_active(state))
                client_mark_failed(c, i);
            }

          break;
        }

      first_iter = 0;
    }

#ifndef MSG_NOSIGNAL
  /*
    Ignore return value of sigaction(), there's nothing we can do in
    the case of error.
  */
  sigaction(SIGPIPE, &orig, NULL);
#endif /* ! MSG_NOSIGNAL */

  return result;
}


static
int
get_server_fd(struct client *c, int index)
{
  struct server *s;
  struct command_state *state;

  s = &c->servers[index];

  /*
    Do not try to try reconnect if had max_failures and
    failure_expires time is not reached yet.
  */
  if (c->max_failures > 0 && s->failure_count >= c->max_failures)
    {
      if (time(NULL) <= s->failure_expires)
        return -1;
      else
        s->failure_count = 0;
    }

  state = &s->cmd_state;
  if (state->fd == -1)
    {
      if (s->port)
        {
          state->fd = client_connect_inet(s->host, s->port,
                                          1, c->connect_timeout);
        }
      else
        {
          state->fd = client_connect_unix(s->host, s->host_len);
        }
    }

  if (state->fd == -1)
    client_mark_failed(c, index);

  return state->fd;
}


static
int
client_get_server_index(struct client *c, const char *key, size_t key_len)
{
  int index, fd;

  index = dispatch_key(&c->dispatch, key, key_len);
  if (index == -1)
    return -1;

  fd = get_server_fd(c, index);
  if (fd == -1)
    return -1;

  return index;
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

      state->iov = buf;
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


static
int
push_key(struct command_state *state, int key_index)
{
  struct key_node *node;
  struct client *c;

  c = state->client;
  if (c->key_list_count == c->key_list_capacity)
    {
      int capacity = (c->key_list_capacity > 0 ? c->key_list_capacity * 2 : 1);
      struct key_node *list =
        (struct key_node *) realloc(c->key_list,
                                    sizeof(struct key_node) * capacity);
      if (! list)
        return MEMCACHED_FAILURE;

      c->key_list = list;
      c->key_list_capacity = capacity;
    }

  if (state->key_tail != -1)
    c->key_list[state->key_tail].next = c->key_list_count;
  else
    state->key_head = c->key_list_count;

  state->key_tail = c->key_list_count;

  node = &c->key_list[state->key_tail];
  node->key = key_index;
  node->next = -1;

  ++c->key_list_count;

  return MEMCACHED_SUCCESS;
}


static inline
void
client_reset_for_command(struct client *c)
{
  c->key_list_count = 0;
  ++c->generation;
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

  client_reset_for_command(c);

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;
  command_state_reset(state, (c->prefix_len ? 2 : 1), 1,
                      (use_noreply ? NULL : parse_set_reply));

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

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

  res = push_key(state, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

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

  return process_commands(c);
}


int
client_cas(struct client *c, const char *key, size_t key_len,
           cas_type cas, flags_type flags, exptime_type exptime,
           const void *value, value_size_type value_size, int noreply)
{
  int use_noreply = (noreply && c->noreply);
  size_t request_size =
    (sizeof(struct iovec) * (c->prefix_len ? 6 : 5)
     + sizeof(" 4294967295 2147483647 18446744073709551615"
              " 18446744073709551615 noreply\r\n"));
  struct command_state *state;
  struct iovec *buf_iov;
  char *buf;
  int server_index, res;

  client_reset_for_command(c);

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;
  command_state_reset(state, (c->prefix_len ? 2 : 1), 1,
                      (use_noreply ? NULL : parse_set_reply));

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  iov_push(state, STR_WITH_LEN("cas "));
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);

  res = push_key(state, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  buf_iov = &state->iov_buf[state->iov_count];
  iov_push(state, NULL, 0);
  iov_push(state, (void *) value, value_size);
  iov_push(state, STR_WITH_LEN("\r\n"));

  buf = (char *) &state->iov_buf[state->iov_count];
  buf_iov->iov_base = buf;
  buf_iov->iov_len = sprintf(buf, " " FMT_FLAGS " " FMT_EXPTIME
                             " " FMT_VALUE_SIZE " " FMT_CAS "%s\r\n",
                             flags, exptime, value_size, cas,
                             (use_noreply ? " noreply" : ""));

  return process_commands(c);
}


int
client_get(struct client *c, enum get_cmd_e cmd,
           const char *key, size_t key_len, struct value_object *o)
{
  size_t request_size = (sizeof(struct iovec) * (c->prefix_len ? 4 : 3));
  struct command_state *state;
  int server_index, res;

  client_reset_for_command(c);

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;
  command_state_reset(state, (c->prefix_len ? 2 : 1), 1, parse_get_reply);
  value_state_reset(&state->u.value, o, (cmd == CMD_GETS));

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  switch (cmd)
    {
    case CMD_GET:
      iov_push(state, STR_WITH_LEN("get "));
      break;

    case CMD_GETS:
      iov_push(state, STR_WITH_LEN("gets "));
      break;
    }
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);

  res = push_key(state, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  iov_push(state, STR_WITH_LEN("\r\n"));

  return process_commands(c);
}


int
client_mget(struct client *c, enum get_cmd_e cmd,
            int key_count, get_key_func get_key, struct value_object *o)
{
  size_t min_request_size =
    (sizeof(struct iovec) * ((c->prefix_len ? 3 : 2) + 2));
  struct command_state *state;
  int i;

  client_reset_for_command(c);

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

      if (is_active(state))
        size = (sizeof(struct iovec)
                * (state->iov_count + (c->prefix_len ? 3 : 2) + 1));
      else
        size = min_request_size;

      res = iov_buf_extend(state, size);
      if (res != MEMCACHED_SUCCESS)
        {
          deactivate(state);
          continue;
        }

      if (! is_active(state))
        {
          command_state_reset(state, (c->prefix_len ? 3 : 2), 0,
                              parse_get_reply);
          value_state_reset(&state->u.value, o, (cmd == CMD_GETS));

          switch (cmd)
            {
            case CMD_GET:
              iov_push(state, STR_WITH_LEN("get"));
              break;

            case CMD_GETS:
              iov_push(state, STR_WITH_LEN("gets"));
              break;
            }
        }

      iov_push(state, STR_WITH_LEN(" "));
      if (c->prefix_len)
        iov_push(state, c->prefix, c->prefix_len);
      iov_push(state, (void *) key, key_len);

      res = push_key(state, i);
      if (res != MEMCACHED_SUCCESS)
        {
          deactivate(state);
          continue;
        }
    }

  for (i = 0; i < c->server_count; ++i)
    {
      state = &c->servers[i].cmd_state;

      if (is_active(state))
        {
          state->key_count = (state->iov_count - 1) / c->key_step;
          iov_push(state, STR_WITH_LEN("\r\n"));
        }
    }

  return process_commands(c);
}


int
client_arith(struct client *c, enum arith_cmd_e cmd,
             const char *key, size_t key_len,
             arith_type arg, arith_type *result, int noreply)
{
  int use_noreply = (noreply && c->noreply);
  size_t request_size =
    (sizeof(struct iovec) * (c->prefix_len ? 4 : 3)
     + sizeof(" 18446744073709551616 noreply\r\n"));
  struct command_state *state;
  struct iovec *buf_iov;
  char *buf;
  int server_index, res;

  client_reset_for_command(c);

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;
  command_state_reset(state, (c->prefix_len ? 2 : 1), 1,
                      (use_noreply ? NULL : parse_arith_reply));
  arith_state_reset(&state->u.arith, result);

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  switch (cmd)
    {
    case CMD_INCR:
      iov_push(state, STR_WITH_LEN("incr "));
      break;

    case CMD_DECR:
      iov_push(state, STR_WITH_LEN("decr "));
      break;
    }
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);

  res = push_key(state, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  buf_iov = &state->iov_buf[state->iov_count];
  iov_push(state, NULL, 0);
  buf = (char *) &state->iov_buf[state->iov_count];
  buf_iov->iov_base = buf;
  buf_iov->iov_len = sprintf(buf, " " FMT_ARITH "%s\r\n", arg,
                             (use_noreply ? " noreply" : ""));

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

  client_reset_for_command(c);

  server_index = client_get_server_index(c, key, key_len);
  if (server_index == -1)
    return MEMCACHED_CLOSED;

  state = &c->servers[server_index].cmd_state;
  command_state_reset(state, (c->prefix_len ? 2 : 1), 1,
                      (use_noreply ? NULL : parse_delete_reply));

  res = iov_buf_extend(state, request_size);
  if (res != MEMCACHED_SUCCESS)
    return res;

  iov_push(state, STR_WITH_LEN("delete "));
  if (c->prefix_len)
    iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, (void *) key, key_len);

  res = push_key(state, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  buf_iov = &state->iov_buf[state->iov_count];
  iov_push(state, NULL, 0);
  buf = (char *) &state->iov_buf[state->iov_count];
  buf_iov->iov_base = buf;
  buf_iov->iov_len = sprintf(buf, " " FMT_DELAY "%s\r\n", delay,
                             (use_noreply ? " noreply" : ""));

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

  client_reset_for_command(c);

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
      command_state_reset(state, 0, 0, (use_noreply ? NULL : parse_ok_reply));

      res = iov_buf_extend(state, request_size);
      if (res != MEMCACHED_SUCCESS)
        {
          deactivate(state);
          continue;
        }

      buf_iov = &state->iov_buf[state->iov_count];
      iov_push(state, NULL, 0);
      buf = (char *) &state->iov_buf[state->iov_count];
      buf_iov->iov_base = buf;
      buf_iov->iov_len = sprintf(buf, "flush_all " FMT_DELAY "%s\r\n",
                                 (delay_type) (ddelay + 0.5),
                                 (use_noreply ? " noreply" : ""));
    }

  return process_commands(c);
}


int
client_server_versions(struct client *c, struct value_object *o)
{
  static const size_t request_size = (sizeof(struct iovec) * 1);
  int i;

  client_reset_for_command(c);

  for (i = 0; i < c->server_count; ++i)
    {
      struct command_state *state;
      int fd, res;

      fd = get_server_fd(c, i);
      if (fd == -1)
        continue;

      state = &c->servers[i].cmd_state;
      command_state_reset(state, 0, 0, parse_version_reply);
      embedded_state_reset(&state->u.embedded, o);

      res = iov_buf_extend(state, request_size);
      if (res != MEMCACHED_SUCCESS)
        {
          deactivate(state);
          continue;
        }

      iov_push(state, STR_WITH_LEN("version\r\n"));
    }

  return process_commands(c);
}
