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

#include "socket_win32.h"


int
win32_socket_library_acquire()
{
  WSADATA wsaData;

  return WSAStartup(MAKEWORD(2, 2), &wsaData);
}


int
set_nonblock(SOCKET fd)
{
  u_long flags = 1;

  return ioctlsocket(fd, FIONBIO, &flags);
}


#undef connect

int
win32_connect(SOCKET fd, const struct sockaddr *addr, int addrlen)
{
  int res;

  res = connect(fd, addr, addrlen);

  /*
    For non-blocking socket Win32 connect() sets error to
    WSAEWOULDBLOCK.  We map it to WSAEINPROGRESS, because this is what
    we expect for non-blocking POSIX connect() in progress.
  */
  if (res == -1 && WSAGetLastError() == WSAEWOULDBLOCK)
    WSASetLastError(WSAEINPROGRESS);

  return res;
}


ssize_t
readv(SOCKET fd, const struct iovec *iov, int iovcnt)
{
  DWORD count, flags = 0;
  int res;

  res = WSARecv(fd, (LPWSABUF) iov, iovcnt, &count, &flags, NULL, NULL);

  return (res == 0 ? count : -1);
}


ssize_t
writev(SOCKET fd, const struct iovec *iov, int iovcnt)
{
  DWORD count;
  int res;

  res = WSASend(fd, (LPWSABUF) iov, iovcnt, &count, 0, NULL, NULL);

  return (res == 0 ? count : -1);
}
