/*
  Copyright (C) 2008, 2010 Tomash Brechko.  All rights reserved.

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

#ifndef SOCKET_POSIX_H
#define SOCKET_POSIX_H 1

#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <limits.h>
#include <errno.h>


#if defined(_SC_IOV_MAX)

#define get_iov_max()  sysconf(_SC_IOV_MAX)

#elif defined(IOV_MAX)

#define get_iov_max()  IOV_MAX

#else

#define get_iov_max()  16

#endif


#if defined(HAVE_POLL_H)

#include <poll.h>

#define can_poll_fd(fd)  1

#elif defined(HAVE_SYS_POLL_H)

#include <sys/poll.h>

#define can_poll_fd(fd)  1

#else  /* ! defined(HAVE_POLL_H) && ! defined(HAVE_SYS_POLL_H) */

#include "poll_select.h"

#define poll(fds, nfds, timeout)  poll_select(fds, nfds, timeout)

#define can_poll_fd(fd)  ((fd) < FD_SETSIZE)

#endif  /* ! defined(HAVE_POLL_H) && ! defined(HAVE_SYS_POLL_H) */


extern
int
set_nonblock(int fd);

extern
int
connect_unix(const char *path, size_t path_len);


#endif  /* ! SOCKET_POSIX_H */
