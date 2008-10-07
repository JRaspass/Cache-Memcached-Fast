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

#ifndef POLL_SELECT_H
#define POLL_SELECT_H 1


#undef  POLLIN
#define POLLIN   0x1
#undef  POLLOUT
#define POLLOUT  0x2
#undef  POLLERR
#define POLLERR  0x4
#undef  POLLHUP
#define POLLHUP  0x4


struct pollfd
{
  int fd;                       /* File descriptor.  */
  short events;                 /* Requested events.  */
  short revents;                /* Returned events.  */
};


extern
int
poll_select(struct pollfd *fds, int nfds, int timeout);


#endif  /* ! POLL_SELECT_H */
