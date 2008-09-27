/*
  Copyright (C) 2007-2008 Tomash Brechko.  All rights reserved.

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

#include "connect.h"
#include <string.h>
#include <netdb.h>
#include "socket_posix.h"


int
client_connect_inet(const char *host, const char *port, int stream,
                    int timeout)
{
  struct timeval to, *pto;
  struct addrinfo hint, *addr, *a;
  int fd = -1, res;

  pto = timeout > 0 ? &to : NULL;

  memset(&hint, 0, sizeof(hint));
#ifdef AI_ADDRCONFIG  /* NetBSD 3.1 doesn't have this.  */
  hint.ai_flags = AI_ADDRCONFIG;
#endif /* AI_ADDRCONFIG */
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
      fd_set write_set;
      int socket_error;
      socklen_t socket_error_len;

      fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
      if (fd == -1)
        break;

      res = set_nonblock(fd);
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
      do
        {
          if (pto)
            {
              pto->tv_sec = timeout / 1000;
              pto->tv_usec = (timeout % 1000) * 1000;
            }
          res = select(fd + 1, NULL, &write_set, NULL, pto);
        }
      while (res == -1 && errno == EINTR);
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


int
client_connect_unix(const char *path, size_t path_len)
{
  return connect_unix(path, path_len);
}
