#include "connect.h"
#include <netdb.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>


int
client_connect_inet(const char *host, const char *port, int stream,
                    int timeout)
{
  struct addrinfo hint, *addr, *a;
  int fd = -1, res;

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
      fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
      if (fd == -1)
        break;

      /* TODO: support timeout.  */
      do
        res = connect(fd, a->ai_addr, a->ai_addrlen);
      while (res == -1 && errno == EINTR);
      if (res == 0)
        break;

      close(fd);
      fd = -1;
    }

  freeaddrinfo(addr);

  return fd;
}
