/*
  Copyright (C) 2009 Tomash Brechko.  All rights reserved.

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

#ifndef ADDRINFO_HOSTENT_H
#define ADDRINFO_HOSTENT_H 1

#ifndef WIN32
#include <netdb.h>
#else  /* WIN32 */
#include <ws2tcpip.h>
#endif  /* WIN32 */


#undef addrinfo
#define addrinfo  addrinfo_hostent

#undef getaddrinfo
#define getaddrinfo  getaddrinfo_hostent

#undef freeaddrinfo
#define freeaddrinfo  freeaddrinfo_hostent


struct addrinfo_hostent
{
  int ai_flags;
  int ai_family;
  int ai_socktype;
  int ai_protocol;
  size_t ai_addrlen;
  struct sockaddr *ai_addr;
  char *ai_canonname;

  struct addrinfo_hostent *ai_next;
};


extern
int
getaddrinfo_hostent(const char *node, const char *service,
                    const struct addrinfo_hostent *hints,
                    struct addrinfo_hostent **res);

extern
void
freeaddrinfo_hostent(struct addrinfo_hostent *res);


#endif  /* ! ADDRINFO_HOSTENT_H */
