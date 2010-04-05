/*
  Copyright (C) 2008 Tomash Brechko.  All rights reserved.

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

#include "socket_posix.h"
#include <fcntl.h>
#include <sys/un.h>
#include <string.h>


/*
  http://www.opengroup.org/onlinepubs/009695399/basedefs/sys/un.h.html
  says 92 is a rather safe value.
*/
#define SAFE_UNIX_PATH_MAX  92


int
set_nonblock(int fd)
{
  int flags;

  flags = fcntl(fd, F_GETFL);

  return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}


int
connect_unix(const char *path, size_t path_len)
{
  int fd, res;
  struct sockaddr_un s_unix;

  if (path_len >= SAFE_UNIX_PATH_MAX)
    return -1;

  fd = socket(PF_UNIX, SOCK_STREAM, 0);
  if (fd == -1)
    return -1;

  if (! can_poll_fd(fd))
    {
      close(fd);

      return -1;
    }

  s_unix.sun_family = AF_UNIX;
  memcpy(s_unix.sun_path, path, path_len);
  s_unix.sun_path[path_len] = '\0';

  res = connect(fd, (const struct sockaddr *) &s_unix, sizeof(s_unix));
  if (res != 0)
    {
      close(fd);

      return -1;
    }

  res = set_nonblock(fd);
  if (res != 0)
    {
      close(fd);

      return -1;
    }

  return fd;
}
