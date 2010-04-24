/*
  Copyright (C) 2007-2010 Tomash Brechko.  All rights reserved.

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
#include "array.h"
#include "connect.h"
#include "parse_keyword.h"
#include "dispatch_key.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifndef WIN32
#include "socket_posix.h"
#include <sys/uio.h>
#include <signal.h>
#include <time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#else  /* WIN32 */
#include "socket_win32.h"
#endif  /* WIN32 */


/* REPLY_BUF_SIZE should be large enough to contain first reply line.  */
#define REPLY_BUF_SIZE  1536


#define FLAGS_STUB  "4294967295"
#define EXPTIME_STUB  "2147483647"
#define DELAY_STUB  "4294967295"
#define VALUE_SIZE_STUB  "18446744073709551615"
#define CAS_STUB  "18446744073709551615"
#define ARITH_STUB  "18446744073709551615"
#define NOREPLY  "noreply"


static const char eol[2] = "\r\n";


typedef unsigned long long generation_type;


struct value_state
{
  void *opaque;
  void *ptr;
  value_size_type size;
  struct meta_object meta;
};


struct embedded_state
{
  void *opaque;
  void *ptr;
};


struct command_state;
typedef int (*parse_reply_func)(struct command_state *state);


enum command_phase
{
  PHASE_RECEIVE,
  PHASE_PARSE,
  PHASE_VALUE,
  PHASE_DONE
};


enum socket_mode_e { NOT_TCP = -1, TCP_LATENCY, TCP_THROUGHPUT };


struct client;


struct command_state
{
  struct client *client;
  int fd;
  struct pollfd *pollfd;
  enum socket_mode_e socket_mode;
  int noreply;
  int last_cmd_noreply;

  struct array iov_buf;
  int str_step;

  generation_type generation;

  int phase;
  int nowait_count;
  int reply_count;

  char *buf;
  char *pos;
  char *end;
  char *eol;
  int match;

  struct iovec *iov;
  int iov_count;
  int write_offset;
  struct iovec *key;
  int key_count;
  int index;
  int index_head;
  int index_tail;

  parse_reply_func parse_reply;
  struct result_object *object;

  union
  {
    struct value_state value;
    struct embedded_state embedded;
  } u;
};


static inline
int
command_state_init(struct command_state *state,
                   struct client *c, int noreply)
{
  state->client = c;
  state->fd = -1;
  state->noreply = noreply;
  state->last_cmd_noreply = 0;

  array_init(&state->iov_buf);

  state->generation = 0;
  state->nowait_count = 0;
  state->buf = (char *) malloc(REPLY_BUF_SIZE);
  if (! state->buf)
    return -1;

  state->pos = state->end = state->eol = state->buf;

  return 0;
}


static inline
void
command_state_destroy(struct command_state *state)
{
  free(state->buf);

  array_destroy(&state->iov_buf);

  if (state->fd != -1)
    close(state->fd);
}


static inline
void
command_state_reinit(struct command_state *state)
{
  if (state->fd != -1)
    close(state->fd);

  state->fd = -1;
  state->last_cmd_noreply = 0;

  array_clear(state->iov_buf);

  state->generation = 0;
  state->nowait_count = 0;

  state->pos = state->end = state->eol = state->buf;
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
            const char *port, size_t port_len, int noreply)
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

  if (command_state_init(&s->cmd_state, c, noreply) != 0)
    return MEMCACHED_FAILURE;

  return MEMCACHED_SUCCESS;
}


static inline
void
server_destroy(struct server *s)
{
  free(s->host); /* This also frees port string.  */
  command_state_destroy(&s->cmd_state);
}


static inline
void
server_reinit(struct server *s)
{
  s->failure_count = 0;
  s->failure_expires = 0;

  command_state_reinit(&s->cmd_state);
}


struct index_node
{
  int index;
  int next;
};


struct client
{
  struct array pollfds;
  struct array servers;

  struct dispatch_state dispatch;

  char *prefix;
  size_t prefix_len;

  int connect_timeout;          /* 1/1000 sec.  */
  int io_timeout;               /* 1/1000 sec.  */
  int max_failures;
  int failure_timeout;          /* 1 sec.  */
  int close_on_error;
  int nowait;
  int hash_namespace;

  struct array index_list;
  struct array str_buf;
  int iov_max;

  generation_type generation;

  struct result_object *object;
  int noreply;
};


static inline
void
command_state_reset(struct command_state *state, int str_step,
                    parse_reply_func parse_reply)
{
  state->reply_count = 0;
  state->str_step = str_step;
  state->key_count = 0;
  state->parse_reply = parse_reply;

  state->phase = PHASE_RECEIVE;

  array_clear(state->iov_buf);

  state->write_offset = 0;
  state->index_head = state->index_tail = -1;
  state->generation = state->client->generation;

#if 0 /* No need to initialize the following.  */
  state->key = NULL;
  state->index = 0;
  state->match = NO_MATCH;
  state->iov_count = 0;
  state->iov = NULL;
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
get_index(struct command_state *state)
{
  struct index_node *node = array_elem(state->client->index_list,
                                       struct index_node, state->index_head);
  return node->index;
}


static inline
void
next_index(struct command_state *state)
{
  struct index_node *node = array_elem(state->client->index_list,
                                       struct index_node, state->index_head);
  state->index_head = node->next;
}


struct client *
client_init()
{
  struct client *c;

#ifdef WIN32
  if (win32_socket_library_acquire() != 0)
    return NULL;
#endif  /* WIN32 */

  c = malloc(sizeof(struct client));
  if (! c)
    return NULL;

  array_init(&c->pollfds);
  array_init(&c->servers);
  array_init(&c->index_list);
  array_init(&c->str_buf);

  dispatch_init(&c->dispatch);

  c->connect_timeout = 250;
  c->io_timeout = 1000;
  c->prefix = " ";
  c->prefix_len = 1;
  c->max_failures = 0;
  c->failure_timeout = 10;
  c->close_on_error = 1;
  c->nowait = 0;
  c->hash_namespace = 0;

  c->iov_max = get_iov_max();

  c->generation = 1;            /* Different from initial command state.  */

  c->object = NULL;
  c->noreply = 0;

  return c;
}


static
int
client_noreply_push(struct client *c);


void
client_destroy(struct client *c)
{
  struct server *s;

  client_nowait_push(c);
  client_noreply_push(c);

  for (array_each(c->servers, struct server, s))
    server_destroy(s);

  dispatch_destroy(&c->dispatch);

  array_destroy(&c->servers);
  array_destroy(&c->pollfds);
  array_destroy(&c->index_list);
  array_destroy(&c->str_buf);

  if (c->prefix_len > 1)
    free(c->prefix);
  free(c);

#ifdef WIN32
  win32_socket_library_release();
#endif  /* WIN32 */
}


void
client_reinit(struct client *c)
{
  struct server *s;

  for (array_each(c->servers, struct server, s))
    server_reinit(s);

  array_clear(c->str_buf);
  array_clear(c->index_list);

  c->generation = 1;            /* Different from initial command state.  */
  c->object = NULL;
}


int
client_set_ketama_points(struct client *c, int ketama_points)
{
  /* Should be called before we added any server.  */
  if (! array_empty(c->servers) || ketama_points < 0)
    return MEMCACHED_FAILURE;

  dispatch_set_ketama_points(&c->dispatch, ketama_points);

  return MEMCACHED_SUCCESS;
}


void
client_set_connect_timeout(struct client *c, int to)
{
  c->connect_timeout = (to > 0 ? to : -1);
}


void
client_set_io_timeout(struct client *c, int to)
{
  c->io_timeout = (to > 0 ? to : -1);
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
client_set_nowait(struct client *c, int enable)
{
  c->nowait = enable;
}


void
client_set_hash_namespace(struct client *c, int enable)
{
  c->hash_namespace = enable;
}


int
client_add_server(struct client *c, const char *host, size_t host_len,
                  const char *port, size_t port_len, double weight,
                  int noreply)
{
  int res;

  if (weight <= 0.0)
    return MEMCACHED_FAILURE;

  if (array_extend(c->pollfds, struct pollfd, 1, ARRAY_EXTEND_EXACT) == -1)
    return MEMCACHED_FAILURE;

  if (array_extend(c->servers, struct server, 1, ARRAY_EXTEND_EXACT) == -1)
    return MEMCACHED_FAILURE;

  res = server_init(array_end(c->servers, struct server), c,
                    host, host_len, port, port_len, noreply);
  if (res != MEMCACHED_SUCCESS)
    return res;

  res = dispatch_add_server(&c->dispatch, host, host_len, port, port_len,
                            weight, array_size(c->servers));
  if (res == -1)
    return MEMCACHED_FAILURE;

  array_push(c->pollfds);
  array_push(c->servers);

  return MEMCACHED_SUCCESS;
}


int
client_set_prefix(struct client *c, const char *ns, size_t ns_len)
{
  char *s;

  if (ns_len == 0)
    {
      if (c->prefix_len > 1)
        {
          free(c->prefix);
          c->prefix = " ";
          c->prefix_len = 1;
        }

      if (c->hash_namespace)
        dispatch_set_prefix(&c->dispatch, "", 0);

      return MEMCACHED_SUCCESS;
    }

  if (c->prefix_len == 1)
    c->prefix = NULL;
  s = (char *) realloc(c->prefix, 1 + ns_len + 1);
  if (! s)
    return MEMCACHED_FAILURE;

  s[0] = ' ';
  memcpy(s + 1, ns, ns_len);
  s[ns_len + 1] = '\0';

  c->prefix = s;
  c->prefix_len = 1 + ns_len;

  if (c->hash_namespace)
    dispatch_set_prefix(&c->dispatch, ns, ns_len);

  return MEMCACHED_SUCCESS;
}


const char *
client_get_prefix(struct client *c, size_t *ns_len)
{
  *ns_len = c->prefix_len - 1;

  return (c->prefix + 1);
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
  state->pos += state->client->prefix_len - 1;

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
          next_index(state);
          state->key += 2;
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
  state->key += 2;
  state->index = get_index(state);
  next_index(state);

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

              state->object->free(state->u.value.opaque);
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
      state->object->free(state->u.value.opaque);
      return MEMCACHED_UNKNOWN;
    }
  state->pos += sizeof(eol);
  state->eol = state->pos;

  state->object->store(state->object->arg, state->u.value.opaque,
                       state->index, &state->u.value.meta);

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
  state->u.value.meta.flags = num;

  res = parse_ull(state, &num);
  if (res != MEMCACHED_SUCCESS)
    return res;
  state->u.value.size = num;

  if (state->u.value.meta.use_cas)
    {
      res = parse_ull(state, &num);
      if (res != MEMCACHED_SUCCESS)
        return res;
      state->u.value.meta.cas = num;
    }

  res = swallow_eol(state, 0, 0);
  if (res != MEMCACHED_SUCCESS)
    return res;

  state->u.value.ptr = state->object->alloc(state->u.value.size,
                                            &state->u.value.opaque);
  if (! state->u.value.ptr)
    return MEMCACHED_FAILURE;

  state->phase = PHASE_VALUE;

  return MEMCACHED_SUCCESS;
}


static inline
void
store_result(struct command_state *state, int res)
{
  int index = get_index(state);
  next_index(state);
  state->object->store(state->object->arg, (void *) (long) res, index, NULL);
}


static
int
parse_set_reply(struct command_state *state)
{
  switch (state->match)
    {
    case MATCH_STORED:
      store_result(state, 1);
      break;

    case MATCH_NOT_STORED:
    case MATCH_NOT_FOUND:
    case MATCH_EXISTS:
      store_result(state, 0);
      break;

    default:
      return MEMCACHED_UNKNOWN;
    }

  return swallow_eol(state, 0, 1);
}


static
int
parse_delete_reply(struct command_state *state)
{
  switch (state->match)
    {
    case MATCH_DELETED:
      store_result(state, 1);
      break;

    case MATCH_NOT_FOUND:
      store_result(state, 0);
      break;

    default:
      return MEMCACHED_UNKNOWN;
    }

  return swallow_eol(state, 0, 1);
}


static
int
parse_arith_reply(struct command_state *state)
{
  char *beg;
  size_t len;
  int zero;

  state->index = get_index(state);
  next_index(state);

  switch (state->match)
    {
    case MATCH_NOT_FOUND:
      /* On NOT_FOUND we store the defined empty string.  */
      state->u.embedded.ptr =
        state->object->alloc(0, &state->u.embedded.opaque);
      if (! state->u.embedded.ptr)
        return MEMCACHED_FAILURE;

      state->object->store(state->object->arg, state->u.embedded.opaque,
                           state->index, NULL);

      return swallow_eol(state, 0, 1);

    default:
      return MEMCACHED_UNKNOWN;

    case MATCH_0: case MATCH_1: case MATCH_2: case MATCH_3: case MATCH_4:
    case MATCH_5: case MATCH_6: case MATCH_7: case MATCH_8: case MATCH_9:
      break;
    }

  beg = state->pos - 1;
  len = 0;
  while (len == 0)
    {
      switch (*state->pos)
        {
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9':
          ++state->pos;
          break;

        default:
          len = state->pos - beg;
          break;
        }
    }

  zero = (*beg == '0' && len == 1);
  if (zero)
    len = 3;

  state->u.embedded.ptr = state->object->alloc(len, &state->u.embedded.opaque);
  if (! state->u.embedded.ptr)
    return MEMCACHED_FAILURE;

  if (! zero)
    memcpy(state->u.embedded.ptr, beg, len);
  else
    memcpy(state->u.embedded.ptr, "0E0", 3);

  state->object->store(state->object->arg, state->u.embedded.opaque,
                       state->index, NULL);

  /* Value may be space padded.  */
  return swallow_eol(state, 1, 1);
}


static
int
parse_ok_reply(struct command_state *state)
{
  switch (state->match)
    {
    case MATCH_OK:
      store_result(state, 1);
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

  state->index = get_index(state);
  next_index(state);

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

  state->u.embedded.ptr = state->object->alloc(len, &state->u.embedded.opaque);
  if (! state->u.embedded.ptr)
    return MEMCACHED_FAILURE;

  memcpy(state->u.embedded.ptr, beg, len);

  state->object->store(state->object->arg, state->u.embedded.opaque,
                       state->index, NULL);

  return MEMCACHED_SUCCESS;
}


static
int
parse_nowait_reply(struct command_state *state)
{
  int res;

  /*
    Cast to enum parse_keyword_e to get compiler warning when some
    match result is not handled.
  */
  switch ((enum parse_keyword_e) state->match)
    {
    case MATCH_DELETED:
    case MATCH_OK:
    case MATCH_STORED:
    case MATCH_EXISTS:
    case MATCH_NOT_FOUND:
    case MATCH_NOT_STORED:
      return swallow_eol(state, 0, 1);

    case MATCH_0: case MATCH_1: case MATCH_2: case MATCH_3: case MATCH_4:
    case MATCH_5: case MATCH_6: case MATCH_7: case MATCH_8: case MATCH_9:
    case MATCH_VERSION: /* see client_noreply_push().  */
      return swallow_eol(state, 1, 1);

    case MATCH_ERROR:
      res = swallow_eol(state, 0, 1);
      return (res == MEMCACHED_SUCCESS ? MEMCACHED_ERROR : res);

    case MATCH_CLIENT_ERROR:
    case MATCH_SERVER_ERROR:
      res = swallow_eol(state, 1, 1);
      return (res == MEMCACHED_SUCCESS ? MEMCACHED_ERROR : res);

    case NO_MATCH:
    case MATCH_VALUE:
    case MATCH_END:
    case MATCH_STAT:
      return MEMCACHED_UNKNOWN;
    }

  /* Never reach here.  */
  return MEMCACHED_UNKNOWN;
}


static
void
client_mark_failed(struct client *c, struct server *s)
{
  if (s->cmd_state.fd != -1)
    {
      close(s->cmd_state.fd);
      s->cmd_state.fd = -1;
      s->cmd_state.nowait_count = 0;
      s->cmd_state.pos = s->cmd_state.end = s->cmd_state.eol =
        s->cmd_state.buf;
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
send_request(struct command_state *state, struct server *s)
{
  while (state->iov_count > 0)
    {
      int count;
      ssize_t res;
      size_t len;

      count = (state->iov_count < state->client->iov_max
               ? state->iov_count : state->client->iov_max);

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
        {
          deactivate(state);
          client_mark_failed(state->client, s);

          return MEMCACHED_CLOSED;
        }

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

  if (state->reply_count == 0)
    deactivate(state);

  return MEMCACHED_SUCCESS;
}


static
int
receive_reply(struct command_state *state)
{
  while (state->eol != state->end && *state->eol != eol[sizeof(eol) - 1])
    ++state->eol;

  /*
    When buffer is empty, move to the beginning of it for better CPU
    cache utilization.
  */
  if (state->pos == state->end)
    state->pos = state->end = state->eol = state->buf;

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
              size = REPLY_BUF_SIZE - len;
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
      if (state->nowait_count)
        return parse_nowait_reply(state);
      else
        return state->parse_reply(state);

    case NO_MATCH:
      return MEMCACHED_UNKNOWN;
    }
}


static
int
process_reply(struct command_state *state, struct server *s)
{
  int res = 0;

  while (1)
    {
      switch (state->phase)
        {
        case PHASE_RECEIVE:
          res = receive_reply(state);
          if (res != MEMCACHED_SUCCESS)
            break;

          state->match = parse_keyword(&state->pos);

          state->phase = PHASE_PARSE;

          /* Fall into below.  */

        case PHASE_PARSE:
          res = parse_reply(state);
          if (res != MEMCACHED_SUCCESS)
            break;

          if (state->phase != PHASE_DONE)
            continue;

          /* Fall into below.  */

        case PHASE_DONE:
          res = MEMCACHED_SUCCESS;

          break;

        case PHASE_VALUE:
          res = read_value(state);
          if (res != MEMCACHED_SUCCESS)
            break;

          state->phase = PHASE_RECEIVE;
          continue;
        }

      switch (res)
        {
        case MEMCACHED_ERROR:
          if (! (state->client->close_on_error || state->noreply))
            break;

          /* else fall into below.  */

        case MEMCACHED_UNKNOWN:
        case MEMCACHED_CLOSED:
          deactivate(state);
          client_mark_failed(state->client, s);

          /* Fall into below.  */

        case MEMCACHED_EAGAIN:
          return res;
        }

      if (state->nowait_count > 0)
        {
          --state->nowait_count;
        }
      else if (--state->reply_count == 0)
        {
          if (state->iov_count == 0)
            deactivate(state);

          return res;
        }

      state->phase = PHASE_RECEIVE;
    }
}


static inline
void
state_prepare(struct command_state *state)
{
  state->key = array_elem(state->iov_buf, struct iovec, 2);
  state->iov = array_beg(state->iov_buf, struct iovec);
  state->iov_count = array_size(state->iov_buf);

  if (state->str_step > 0)
    {
      struct iovec *iov = state->iov;
      char *buf = array_beg(state->client->str_buf, char);
      int count = state->iov_count, step = state->str_step;

      if (state->key_count > 0)
        {
          iov += 3;
          count -= 3;
        }

      while (count > 0)
        {
          iov->iov_base = (void *) (buf + (long) (iov->iov_base));
          iov += step;
          count -= step;
        }
    }
}


int
client_execute(struct client *c)
{
  int first_iter = 1;

#if ! defined(MSG_NOSIGNAL) && ! defined(WIN32)
  struct sigaction orig, ignore;
  int res;

  ignore.sa_handler = SIG_IGN;
  sigemptyset(&ignore.sa_mask);
  ignore.sa_flags = 0;
  res = sigaction(SIGPIPE, &ignore, &orig);
  if (res == -1)
    return MEMCACHED_FAILURE;
#endif /* ! defined(MSG_NOSIGNAL) && ! defined(WIN32) */

  while (1)
    {
      struct server *s;
      struct pollfd *pollfd_beg, *pollfd;
      int res;

      pollfd_beg = array_beg(c->pollfds, struct pollfd);
      pollfd = pollfd_beg;

      for (array_each(c->servers, struct server, s))
        {
          int may_write, may_read;
          struct command_state *state = &s->cmd_state;

          if (! is_active(state))
            continue;

          if (first_iter)
            {
              state_prepare(state);

              may_write = 1;
              may_read = (state->reply_count > 0
                          || state->nowait_count > 0);
            }
          else
            {
              const short revents = state->pollfd->revents;

              may_write = revents & (POLLOUT | POLLERR | POLLHUP);
              may_read = revents & (POLLIN | POLLERR | POLLHUP);
            }

          if (may_read || may_write)
            {
              if (may_write)
                {
                  int res;

                  res = send_request(state, s);
                  if (res == MEMCACHED_CLOSED)
                    may_read = 0;
                }

              if (may_read)
                process_reply(state, s);

              if (! is_active(state))
                continue;
            }

          pollfd->events = 0;

          if (state->iov_count > 0)
            pollfd->events |= POLLOUT;
          if (state->reply_count > 0 || state->nowait_count > 0)
            pollfd->events |= POLLIN;

          if (pollfd->events != 0)
            {
              pollfd->fd = state->fd;
              state->pollfd = pollfd;
              ++pollfd;
            }
        }

      if (pollfd == pollfd_beg)
        break;

      do
        res = poll(pollfd_beg, pollfd - pollfd_beg, c->io_timeout);
      while (res == -1 && errno == EINTR);

      /*
        On error or timeout close all active connections.  Otherwise
        we might receive garbage on them later.
      */
      if (res <= 0)
        {
          for (array_each(c->servers, struct server, s))
            {
              struct command_state *state = &s->cmd_state;

              if (is_active(state))
                {
                  /*
                    Ugly fix for possible memory leak.  FIXME:
                    requires redesign.
                  */
                  if (state->phase == PHASE_VALUE)
                    state->object->free(state->u.value.opaque);

                  client_mark_failed(c, s);
                }
            }

          break;
        }

      first_iter = 0;
    }

#if ! defined(MSG_NOSIGNAL) && ! defined(WIN32)
  /*
    Ignore return value of sigaction(), there's nothing we can do in
    the case of error.
  */
  sigaction(SIGPIPE, &orig, NULL);
#endif /* ! defined(MSG_NOSIGNAL) && ! defined(WIN32) */

  return MEMCACHED_SUCCESS;
}


/* Is the following required for any platform?  */
#if (! defined(IPPROTO_TCP) && defined(SOL_TCP))
#define IPPROTO_TCP  SOL_TCP
#endif


static inline
void
tcp_optimize_latency(struct command_state *state)
{
#ifdef TCP_NODELAY
  if (state->socket_mode == TCP_THROUGHPUT)
    {
      static const int enable = 1;
      setsockopt(state->fd, IPPROTO_TCP, TCP_NODELAY,
                 (void *) &enable, sizeof(enable));
      state->socket_mode = TCP_LATENCY;
    }
#endif /* TCP_NODELAY */
}


static inline
void
tcp_optimize_throughput(struct command_state *state)
{
#ifdef TCP_NODELAY
  if (state->socket_mode == TCP_LATENCY)
    {
      static const int disable = 0;
      setsockopt(state->fd, IPPROTO_TCP, TCP_NODELAY,
                 (void *) &disable, sizeof(disable));
      state->socket_mode = TCP_THROUGHPUT;
    }
#endif /* TCP_NODELAY */
}


static
int
get_server_fd(struct client *c, struct server *s)
{
  struct command_state *state;

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
                                          c->connect_timeout);
          /* This is to trigger actual reset.  */
          state->socket_mode = TCP_THROUGHPUT;
          if (state->fd != -1)
            tcp_optimize_latency(state);
        }
      else
        {
          state->fd = client_connect_unix(s->host, s->host_len);
          state->socket_mode = NOT_TCP;
        }
    }

  if (state->fd == -1)
    client_mark_failed(c, s);

  return state->fd;
}


static inline
void
iov_push(struct command_state *state, const void *buf, size_t buf_size)
{
  struct iovec *iov = array_end(state->iov_buf, struct iovec);
  iov->iov_base = (void *) buf;
  iov->iov_len = buf_size;
  array_push(state->iov_buf);
}


static
int
push_index(struct command_state *state, int index)
{
  struct index_node *node;
  struct client *c;

  c = state->client;
  if (array_extend(c->index_list, struct index_node,
                   1, ARRAY_EXTEND_TWICE) == -1)
    return MEMCACHED_FAILURE;

  if (state->index_tail != -1)
    array_elem(c->index_list, struct index_node, state->index_tail)->next =
      array_size(c->index_list);
  else
    state->index_head = array_size(c->index_list);

  state->index_tail = array_size(c->index_list);

  node = array_elem(c->index_list, struct index_node, state->index_tail);
  node->index = index;
  node->next = -1;

  array_push(c->index_list);

  return MEMCACHED_SUCCESS;
}


static
struct command_state *
init_state(struct command_state *state, int index, size_t request_size,
           size_t str_size, parse_reply_func parse_reply)
{
  if (! is_active(state))
    {
      if (state->client->noreply)
        {
          if (state->client->nowait || state->noreply)
            {
              parse_reply = NULL;
              tcp_optimize_throughput(state);
            }

          state->last_cmd_noreply = state->noreply;
        }
      else
        {
          state->last_cmd_noreply = 0;
          tcp_optimize_latency(state);
        }

      state->object = state->client->object;
      command_state_reset(state, (str_size > 0 ? request_size : 0),
                          parse_reply);
    }

  if (array_extend(state->iov_buf, struct iovec,
                   request_size, ARRAY_EXTEND_EXACT) == -1)
    {
      deactivate(state);
      return NULL;
    }

  if (str_size > 0
      && array_extend(state->client->str_buf, char,
                      str_size, ARRAY_EXTEND_TWICE) == -1)
    {
      deactivate(state);
      return NULL;
    }

  if (push_index(state, index) != MEMCACHED_SUCCESS)
    {
      deactivate(state);
      return NULL;
    }

  if (state->parse_reply)
    ++state->reply_count;
  else if (! state->last_cmd_noreply)
    ++state->nowait_count;

  return state;
}


static
struct command_state *
get_state(struct client *c, int index, const char *key, size_t key_len,
          size_t request_size, size_t str_size,
          parse_reply_func parse_reply)
{
  struct server *s;
  int server_index, fd;

  server_index = dispatch_key(&c->dispatch, key, key_len);
  if (server_index == -1)
    return NULL;

  s = array_elem(c->servers, struct server, server_index);

  fd = get_server_fd(c, s);
  if (fd == -1)
    return NULL;

  return init_state(&s->cmd_state, index, request_size, str_size,
                    parse_reply);
}


static inline
const char *
get_noreply(struct command_state *state)
{
  if (state->noreply && state->client->noreply)
    return " " NOREPLY;
  else
    return "";
}


inline
void
client_reset(struct client *c, struct result_object *o, int noreply)
{
  array_clear(c->index_list);
  array_clear(c->str_buf);

  ++c->generation;
  c->object = o;
  c->noreply = noreply;
}


#define STR_WITH_LEN(str) (str), (sizeof(str) - 1)


int
client_prepare_set(struct client *c, enum set_cmd_e cmd, int key_index,
                   const char *key, size_t key_len,
                   flags_type flags, exptime_type exptime,
                   const void *value, value_size_type value_size)
{
  static const size_t request_size = 6;
  static const size_t str_size =
    sizeof(" " FLAGS_STUB " " EXPTIME_STUB " " VALUE_SIZE_STUB
           " " NOREPLY "\r\n");

  struct command_state *state;

  state = get_state(c, key_index, key, key_len, request_size, str_size,
                    parse_set_reply);
  if (! state)
    return MEMCACHED_FAILURE;

  ++state->key_count;

  switch (cmd)
    {
    case CMD_SET:
      iov_push(state, STR_WITH_LEN("set"));
      break;

    case CMD_ADD:
      iov_push(state, STR_WITH_LEN("add"));
      break;

    case CMD_REPLACE:
      iov_push(state, STR_WITH_LEN("replace"));
      break;

    case CMD_APPEND:
      iov_push(state, STR_WITH_LEN("append"));
      break;

    case CMD_PREPEND:
      iov_push(state, STR_WITH_LEN("prepend"));
      break;

    case CMD_CAS:
      /* This can't happen.  */
      return MEMCACHED_FAILURE;
    }
  iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, key, key_len);

  {
    char *buf = array_end(c->str_buf, char);
    size_t str_size =
      sprintf(buf, " " FMT_FLAGS " " FMT_EXPTIME " " FMT_VALUE_SIZE "%s\r\n",
              flags, exptime, value_size, get_noreply(state));
    iov_push(state, (void *) (long) array_size(c->str_buf), str_size);
    array_append(c->str_buf, str_size);
  }

  iov_push(state, value, value_size);
  iov_push(state, STR_WITH_LEN("\r\n"));

  return MEMCACHED_SUCCESS;
}


int
client_prepare_cas(struct client *c, int key_index,
                   const char *key, size_t key_len,
                   cas_type cas, flags_type flags, exptime_type exptime,
                   const void *value, value_size_type value_size)
{
  static const size_t request_size = 6;
  static const size_t str_size =
    sizeof(" " FLAGS_STUB " " EXPTIME_STUB " " VALUE_SIZE_STUB
           " " CAS_STUB " " NOREPLY "\r\n");

  struct command_state *state;

  state = get_state(c, key_index, key, key_len, request_size, str_size,
                    parse_set_reply);
  if (! state)
    return MEMCACHED_FAILURE;

  ++state->key_count;

  iov_push(state, STR_WITH_LEN("cas"));
  iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, key, key_len);

  {
    char *buf = array_end(c->str_buf, char);
    size_t str_size =
      sprintf(buf, " " FMT_FLAGS " " FMT_EXPTIME " " FMT_VALUE_SIZE
              " " FMT_CAS "%s\r\n", flags, exptime, value_size, cas,
              get_noreply(state));
    iov_push(state, (void *) (long) array_size(c->str_buf), str_size);
    array_append(c->str_buf, str_size);
  }

  iov_push(state, value, value_size);
  iov_push(state, STR_WITH_LEN("\r\n"));

  return MEMCACHED_SUCCESS;
}


int
client_prepare_get(struct client *c, enum get_cmd_e cmd, int key_index,
                   const char *key, size_t key_len)
{
  static const size_t request_size = 4;

  struct command_state *state;

  state = get_state(c, key_index, key, key_len, request_size, 0,
                    parse_get_reply);
  if (! state)
    return MEMCACHED_FAILURE;

  ++state->key_count;

  if (! array_empty(state->iov_buf))
    {
      /* Pop off trailing \r\n because we are about to add another key.  */
      array_pop(state->iov_buf);

      /* get can't be in noreply mode, so reply_count is positive.  */
      --state->reply_count;
    }
  else
    {
      switch (cmd)
        {
        case CMD_GET:
          state->u.value.meta.use_cas = 0;
          iov_push(state, STR_WITH_LEN("get"));
          break;

        case CMD_GETS:
          state->u.value.meta.use_cas = 1;
          iov_push(state, STR_WITH_LEN("gets"));
          break;
        }
    }

  iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, key, key_len);
  iov_push(state, STR_WITH_LEN("\r\n"));

  return MEMCACHED_SUCCESS;
}


int
client_prepare_incr(struct client *c, enum arith_cmd_e cmd, int key_index,
                    const char *key, size_t key_len, arith_type arg)
{
  static const size_t request_size = 4;
  static const size_t str_size = sizeof(" " ARITH_STUB " " NOREPLY "\r\n");

  struct command_state *state;

  state = get_state(c, key_index, key, key_len, request_size, str_size,
                    parse_arith_reply);
  if (! state)
    return MEMCACHED_FAILURE;

  ++state->key_count;

  switch (cmd)
    {
    case CMD_INCR:
      iov_push(state, STR_WITH_LEN("incr"));
      break;

    case CMD_DECR:
      iov_push(state, STR_WITH_LEN("decr"));
      break;
    }
  iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, key, key_len);

  {
    char *buf = array_end(c->str_buf, char);
    size_t str_size =
      sprintf(buf, " " FMT_ARITH "%s\r\n", arg, get_noreply(state));
    iov_push(state, (void *) (long) array_size(c->str_buf), str_size);
    array_append(c->str_buf, str_size);
  }

  return MEMCACHED_SUCCESS;
}


int
client_prepare_delete(struct client *c, int key_index,
                      const char *key, size_t key_len)
{
  static const size_t request_size = 4;
  static const size_t str_size = sizeof(" " NOREPLY "\r\n");

  struct command_state *state;

  state = get_state(c, key_index, key, key_len, request_size, str_size,
                    parse_delete_reply);
  if (! state)
    return MEMCACHED_FAILURE;

  ++state->key_count;

  iov_push(state, STR_WITH_LEN("delete"));
  iov_push(state, c->prefix, c->prefix_len);
  iov_push(state, key, key_len);

  {
    char *buf = array_end(c->str_buf, char);
    size_t str_size = sprintf(buf, "%s\r\n", get_noreply(state));
    iov_push(state, (void *) (long) array_size(c->str_buf), str_size);
    array_append(c->str_buf, str_size);
  }

  return MEMCACHED_SUCCESS;
}


int
client_flush_all(struct client *c, delay_type delay,
                 struct result_object *o, int noreply)
{
  static const size_t request_size = 1;
  static const size_t str_size =
    sizeof("flush_all " DELAY_STUB " " NOREPLY "\r\n");

  struct server *s;
  double ddelay = delay, delay_step = 0.0;
  int i;

  client_reset(c, o, noreply);

  if (array_size(c->servers) > 1)
    delay_step = ddelay / (array_size(c->servers) - 1);
  ddelay += delay_step;

  for (i = 0, array_each(c->servers, struct server, s), ++i)
    {
      struct command_state *state;
      int fd;

      ddelay -= delay_step;

      fd = get_server_fd(c, s);
      if (fd == -1)
        continue;

      state = init_state(&s->cmd_state, i, request_size, str_size,
                         parse_ok_reply);
      if (! state)
        continue;

      {
        char *buf = array_end(c->str_buf, char);
        size_t str_size =
          sprintf(buf, "flush_all " FMT_DELAY "%s\r\n",
                  (delay_type) (ddelay + 0.5), get_noreply(state));
        iov_push(state, (void *) (long) array_size(c->str_buf), str_size);
        array_append(c->str_buf, str_size);
      }
    }

  return client_execute(c);
}


int
client_nowait_push(struct client *c)
{
  struct server *s;

  if (! c->nowait)
    return MEMCACHED_SUCCESS;

  client_reset(c, NULL, 0);

  for (array_each(c->servers, struct server, s))
    {
      struct command_state *state;
      int fd;

      state = &s->cmd_state;
      if (state->nowait_count == 0)
        continue;

      fd = get_server_fd(c, s);
      if (fd == -1)
        continue;

      /*
        In order to wait the final pending reply we pretend that one
        command was never a nowait command, and set parse function to
        parse_nowait_reply.
      */
      --state->nowait_count;
      command_state_reset(state, 0, parse_nowait_reply);
      tcp_optimize_latency(state);
      ++state->reply_count;
    }

  return client_execute(c);
}


int
client_server_versions(struct client *c, struct result_object *o)
{
  static const size_t request_size = 1;

  struct server *s;
  int i;

  client_reset(c, o, 0);

  for (i = 0, array_each(c->servers, struct server, s), ++i)
    {
      struct command_state *state;
      int fd;

      fd = get_server_fd(c, s);
      if (fd == -1)
        continue;

      state = init_state(&s->cmd_state, i, request_size, 0,
                         parse_version_reply);
      if (! state)
        continue;

      iov_push(state, STR_WITH_LEN("version\r\n"));
    }

  return client_execute(c);
}


/*
  When noreply mode is enabled the client may send the last noreply
  request and close the connection.  The server will see that the
  connection is closed, and will discard all previously read data
  without processing it.  To avoid this, we send "version" command and
  wait for the reply (discarding it).
*/
static
int
client_noreply_push(struct client *c)
{
  static const size_t request_size = 1;

  struct server *s;
  int i;

  client_reset(c, NULL, 0);

  for (i = 0, array_each(c->servers, struct server, s), ++i)
    {
      struct command_state *state = &s->cmd_state;
      int fd;

      if (! state->last_cmd_noreply)
        continue;

      fd = get_server_fd(c, s);
      if (fd == -1)
        continue;

      state = init_state(state, i, request_size, 0, parse_nowait_reply);
      if (! state)
        continue;

      iov_push(state, STR_WITH_LEN("version\r\n"));
    }

  return client_execute(c);
}
