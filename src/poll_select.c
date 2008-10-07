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

#include "poll_select.h"
#ifndef WIN32
#include "socket_posix.h"
#else  /* WIN32 */
#include "socket_win32.h"
#endif  /* WIN32 */


int
poll_select(struct pollfd *fds, int nfds, int timeout)
{
  fd_set read_set, write_set, exception_set;
  struct timeval to, *pto;
  int max_fd = -1;
  int select_res, poll_res;
  int i;

  if (timeout >= 0)
    {
      pto = &to;
      pto->tv_sec = timeout / 1000;
      pto->tv_usec = (timeout % 1000) * 1000;
    }
  else
    {
      pto = NULL;
    }

  FD_ZERO(&read_set);
  FD_ZERO(&write_set);
  FD_ZERO(&exception_set);

  for (i = 0; i < nfds; ++i)
    {
      fds[i].revents = 0;

      /* POSIX requires skipping fd less than zero.  */
      if (fds[i].fd < 0)
        continue;

      /*
        To continue is the best we can do here, but we shouldn't be
        called with non-select()'able descriptor at the first place.
      */
      if (! can_poll_fd(fds[i].fd))
        continue;

      if (max_fd < fds[i].fd)
        max_fd = fds[i].fd;

      if (fds[i].events & POLLIN)
        FD_SET(fds[i].fd, &read_set);
      if (fds[i].events & POLLOUT)
        FD_SET(fds[i].fd, &write_set);
      /*
        poll() waits for error condition even when no other event is
        requested (events == 0).  POSIX says that pending socket error
        should be an exceptional condition.  However other exceptional
        conditions are protocol-specific.  For instance for TCP
        out-of-band data is often also exceptional.  So we enable
        exceptions unconditionally, and callers should treat returned
        POLLERR as "may read/write".
      */
      FD_SET(fds[i].fd, &exception_set);
    }

  select_res = select(max_fd + 1, &read_set, &write_set, &exception_set, pto);

  if (select_res > 0)
    {
      /*
        select() returns number of bits set, but poll() returns number
        of flagged structures.
      */
      poll_res = 0;
      for (i = 0; i < nfds; ++i)
        {
          if (FD_ISSET(fds[i].fd, &read_set))
            {
              fds[i].revents |= POLLIN;
              --select_res;
            }
          if (FD_ISSET(fds[i].fd, &write_set))
            {
              fds[i].revents |= POLLOUT;
              --select_res;
            }
          if (FD_ISSET(fds[i].fd, &exception_set))
            {
              fds[i].revents |= POLLERR;
              --select_res;
            }

          if (fds[i].revents != 0)
            {
              ++poll_res;

              if (select_res == 0)
                break;
            }
        }
    }
  else
    {
      poll_res = select_res;
    }

  return poll_res;
}
