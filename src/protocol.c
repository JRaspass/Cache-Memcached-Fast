#include "protocol.h"
#include "parse_reply.h"
#include <sys/uio.h>
#include <errno.h>


/* Any positive buffer size is supported, 1 is good for testing.  */
static const int REPLY_BUF_SIZE = 2048;
static const char sp[1] = " ";
static const char eol[2] = "\r\n";


struct command_state
{
  struct iovec *request_iov;
  size_t request_iov_count;

  struct genparser_state reply_parser_state;
  size_t eol_state;
};


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
swallow_eol(int fd, struct command_state *state, char *buf, int skip)
{
  char *pos, *end;

  pos = genparser_get_buf(&state->reply_parser_state);
  end = genparser_get_buf_end(&state->reply_parser_state);

  while (state->eol_state < sizeof(eol))
    {
      if (pos == end)
        {
          ssize_t res;

          res = read_restart(fd, buf, REPLY_BUF_SIZE);
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
read_reply(int fd, struct command_state *state)
{
  char buf[REPLY_BUF_SIZE];
  ssize_t res;

  while ((res = read_restart(fd, buf, REPLY_BUF_SIZE)) > 0)
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
            int res = swallow_eol(fd, state, buf, (match != MATCH_ERROR));
            return (res == MEMCACHED_SUCCESS ? MEMCACHED_ERROR : res);
          }

        default:
        case MATCH_STAT:
        case MATCH_VALUE:
        case MATCH_VERSION:
          return MEMCACHED_UNKNOWN;

        case MATCH_EXISTS:
        case MATCH_NOT_FOUND:
        case MATCH_NOT_STORED:
          {
            int res = swallow_eol(fd, state, buf, 0);
            return (res == MEMCACHED_SUCCESS ? MEMCACHED_FAILURE : res);
          }

        case MATCH_STORED:
        case MATCH_DELETED:
        case MATCH_OK:
        case MATCH_END:
          return swallow_eol(fd, state, buf, 0);
        }
    }

  return MEMCACHED_CLOSED;
}


static
int
process_command(int fd, struct command_state *state,
                int (*read_reply)(int fd, struct command_state *state))
{
  while (state->request_iov_count > 0)
    {
      ssize_t res;

      res = writev_restart(fd, state->request_iov, state->request_iov_count);

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

  if (read_reply)
    return read_reply(fd, state);

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

  state.request_iov = iov;
  state.request_iov_count = sizeof(iov) / sizeof(*iov);
  genparser_init(&state.reply_parser_state);
  state.eol_state = 0;

  return process_command(fd, &state, read_reply);
}
