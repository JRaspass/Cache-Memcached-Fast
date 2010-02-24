/*
  Copyright (C) 2008-2010 Tomash Brechko.  All rights reserved.

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

#ifndef SOCKET_WIN32_H
#define SOCKET_WIN32_H 1

#include <winsock2.h>
#include <ws2tcpip.h>
#include <sys/types.h>


#define get_iov_max()  64


#if _WIN32_WINNT >= 0x0501

#include <wspiapi.h>

#else  /* ! (_WIN32_WINNT >= 0x0501) */

#include "addrinfo_hostent.h"

#endif  /* ! (_WIN32_WINNT >= 0x0501) */


#if _WIN32_WINNT >= 0x0600

#define poll(fds, nfds, timeout)  WSAPoll(fds, nfds, timeout)

#else  /* ! (_WIN32_WINNT >= 0x0600) */

#include "poll_select.h"

#define poll(fds, nfds, timeout)  poll_select(fds, nfds, timeout)

#endif  /* ! (_WIN32_WINNT >= 0x0600) */


/*
  On Win32 FD_SETSIZE is not the limit on the max fd value, but
  instead the limit on the total number of fds that select() can
  handle.  So can_poll_fd() should return 1 in any case, any fd is
  select()'able or WSAPoll()'able.  By default FD_SETSIZE is 64.  If
  you plan to use more memcached servers, you may redefine it to a
  larger value before including <winsock2.h>.
*/
#define can_poll_fd(fd)  1


#undef  errno
#define errno  WSAGetLastError()

#undef  EINTR
#define EINTR        WSAEINTR
#undef  EWOULDBLOCK
#define EWOULDBLOCK  WSAEWOULDBLOCK
#undef  EAGAIN
#define EAGAIN       WSAEWOULDBLOCK
#undef  EINPROGRESS
#define EINPROGRESS  WSAEINPROGRESS


#define connect_unix(path, path_len)  -1

#define connect(fd, addr, addrlen)  win32_connect(fd, addr, addrlen)

#define read(fd, buf, size)  recv(fd, buf, size, 0)

#define close(fd)  closesocket(fd)

#define win32_socket_library_release  WSACleanup


extern
int
win32_socket_library_acquire();

extern
int
set_nonblock(SOCKET fd);

extern
int
win32_connect(SOCKET fd, const struct sockaddr *addr, int addrlen);


/* Define struct iovec the same way as WSABUF is defined.  */
struct iovec
{
  u_long iov_len;
  char FAR *iov_base;
};


extern
ssize_t
readv(SOCKET fd, const struct iovec *iov, int iovcnt);

extern
ssize_t
writev(SOCKET fd, const struct iovec *iov, int iovcnt);


#endif  /* ! SOCKET_WIN32_H */
