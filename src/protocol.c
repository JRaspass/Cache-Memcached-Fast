#include "protocol.h"
#include "parse_reply.h"
#include <sys/uio.h>
#include <unistd.h>
#include <errno.h>


#ifndef MAX_IOVEC
#define MAX_IOVEC 1024
#endif


/* Any positive buffer size is supported, 1 is good for testing.  */
static const int REPLY_BUF_SIZE = 2048;
static const char sp[1] = " ";
static const char eol[2] = "\r\n";


struct command_state;
typedef int (*parse_reply_func)(struct command_state *state, char *buf);

struct command_state
{
  int fd;

  struct iovec *request_iov;
  size_t request_iov_count;

  struct genparser_state reply_parser_state;
  size_t eol_state;

  parse_reply_func parse_reply;
};


static inline
void
command_state_init(struct command_state *state, int fd,
                   struct iovec *iov, size_t count,
                   parse_reply_func parse_reply)
{
  state->fd = fd;
  state->request_iov = iov;
  state->request_iov_count = count;
  genparser_init(&state->reply_parser_state);
  state->eol_state = 0;
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
writev_restart(int fd, const struct iovec *iov, size_t count)
{
  ssize_t res;

  do
    res = writev(fd, iov, count);
  while (res == -1 && errno == EINTR);

  return res;
}


static
int
swallow_eol(struct command_state *state, char *buf, int skip)
{
  char *pos, *end;

  pos = genparser_get_buf(&state->reply_parser_state);
  end = genparser_get_buf_end(&state->reply_parser_state);

  while (state->eol_state < sizeof(eol))
    {
      if (pos == end)
        {
          ssize_t res;

          res = read_restart(state->fd, buf, REPLY_BUF_SIZE);
          if (res <= 0)
            return MEMCACHED_CLOSED;

          pos = buf;
          end = buf + res;
          genparser_set_buf(&state->reply_parser_state, pos, end);
        }

      if (*pos != eol[state->eol_state])
        {
          if (skip)
            {
              state->eol_state = 0;
              ++pos;
              continue;
            }
          else
            {
              return MEMCACHED_UNKNOWN;
            }
        }

      ++pos;
      ++state->eol_state;
    }

  genparser_set_buf(&state->reply_parser_state, pos, end);
  state->eol_state = 0;

  return MEMCACHED_SUCCESS;
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
garbage_remains(struct command_state *state)
{
  char *pos, *end;

  pos = genparser_get_buf(&state->reply_parser_state);
  end = genparser_get_buf_end(&state->reply_parser_state);

  return (pos != end);
}


static
int
read_reply(struct command_state *state)
{
  char buf[REPLY_BUF_SIZE];
  ssize_t res;

  while ((res = read_restart(state->fd, buf, REPLY_BUF_SIZE)) > 0)
    {
      int parse_res;
      int match;

      genparser_set_buf(&state->reply_parser_state, buf, buf + res);
      parse_res = parse_reply(&state->reply_parser_state);
      if (parse_res == 0)
        continue;
      if (parse_res == -1)
        return MEMCACHED_UNKNOWN;

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

  return MEMCACHED_CLOSED;
}


static
int
process_command(struct command_state *state)
{
  while (state->request_iov_count > 0)
    {
      size_t count;
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


int
protocol_set(int fd, const char *key, size_t key_len,
             unsigned int flags, unsigned int exptime, size_t val_size,
             const void *val)
{
  struct iovec iov[5];
  struct command_state state;
  char buf[sizeof(" 4294967295 4294967295 18446744073709551615\r\n")];

  iov[0].iov_base = "set ";
  iov[0].iov_len = 4;
  iov[1].iov_base = (void *) key;
  iov[1].iov_len = key_len;
  iov[2].iov_base = buf;
  iov[2].iov_len = sprintf(buf, " %u %u %zu\r\n", flags, exptime, val_size);
  iov[3].iov_base = (void *) val;
  iov[3].iov_len = val_size;
  iov[4].iov_base = (void *) eol;
  iov[4].iov_len = sizeof(eol);

  command_state_init(&state, fd, iov, sizeof(iov) / sizeof(*iov),
                     parse_set_reply);

  return process_command(&state);
}
