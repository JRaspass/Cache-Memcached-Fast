#include "connect.h"
#include <netdb.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>


int
client_connect_inet(const char *host, const char *port, int stream,
                    int timeout)
{
  struct timeval to, *pto;
  struct addrinfo hint, *addr, *a;
  int fd = -1, res;

  pto = timeout > 0 ? &to : NULL;

  memset(&hint, 0, sizeof(hint));
  hint.ai_flags = AI_ADDRCONFIG;
  hint.ai_socktype = stream ? SOCK_STREAM : SOCK_DGRAM;
  res = getaddrinfo(host, port, &hint, &addr);
  if (res != 0)
    {
#if 0
      if (res != EAI_SYSTEM)
        GAI error
      else
        system error
#endif

      return -1;
    }

  for (a = addr; a != NULL; a = a->ai_next)
    {
      int flags;
      fd_set write_set;
      int socket_error;
      socklen_t socket_error_len;

      fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
      if (fd == -1)
        break;

      flags = fcntl(fd, F_GETFL);
      res = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
      if (res != 0)
        {
          close(fd);
          fd = -1;
          continue;
        }

      do
        res = connect(fd, a->ai_addr, a->ai_addrlen);
      while (res == -1 && errno == EINTR);
      if (res == -1 && errno != EINPROGRESS)
        {
          close(fd);
          fd = -1;
          continue;
        }

      FD_ZERO(&write_set);
      FD_SET(fd, &write_set);
      if (pto)
        {
          pto->tv_sec = timeout / 1000;
          pto->tv_usec = (timeout % 1000) * 1000;
        }
      res = select(fd + 1, NULL, &write_set, NULL, pto);
      if (res <= 0)
        {
          close(fd);
          fd = -1;
          continue;
        }

      socket_error_len = sizeof(socket_error);
      res = getsockopt(fd, SOL_SOCKET, SO_ERROR,
                       &socket_error, &socket_error_len);
      if (res == 0 && socket_error == 0)
        break;

      close(fd);
      fd = -1;
    }

  freeaddrinfo(addr);

  return fd;
}
