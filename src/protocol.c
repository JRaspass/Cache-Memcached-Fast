#include "protocol.h"
#include "parse_reply.h"
#include <sys/uio.h>
#include <stddef.h>
#include <errno.h>


static const char sp[1] = " ";
static const char eol[2] = "\r\n";


struct command_state
{
  struct iovec *request_iov;
  size_t request_iov_count;
  struct genparser_state reply_parser_state;
};


static
int
read_set_reply(int fd, struct command_state *state)
{
  char buf[2048];
  ssize_t res;

  genparser_init(&state->reply_parser_state);

  do
    {
      while ((res = read(fd, buf, sizeof(buf))) > 0)
        {
#if 0
          size_t offset = 0;

          while (offset < res)
            {
              if (buf[offset] != state->reply->str[state->reply_str_offset])
                break;
              ++offset;
              ++state->reply_str_offset;
            }

          if (offset == res)
            continue;

          if (state->reply->str[state->reply_str_offset] != '\0')
            state->reply = &ordered_replies[0];
#endif
        }
    }
  while (res == -1 && errno == EINTR);

  return -1;
}


static
int
client_process_command(int fd, struct command_state *state,
                       int (*read_reply)(int fd, struct command_state *state))
{
  while (state->request_iov_count > 0)
    {
      ssize_t res;

      do
        res = writev(fd, state->request_iov, state->request_iov_count);
      while (res == -1 && errno == EINTR);

      if (res <= 0)
        return -1;

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

  return 0;
}


int
client_set(int fd, const char *key, size_t key_len,
           unsigned int flags, unsigned int exptime, size_t val_size,
           const void *val)
{
  char buf[sizeof(" 4294967295 4294967295 18446744073709551615\r\n")];
  struct iovec iov[5];
  struct command_state state;

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

  return client_process_command(fd, &state, NULL);
}
