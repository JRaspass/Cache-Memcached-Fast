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

#include "addrinfo_hostent.h"
#ifndef WIN32
#include <sys/types.h>
#include <arpa/inet.h>
#endif  /* ! WIN32 */
#include <stdlib.h>
#include <string.h>


#ifdef h_addr
#define ADDR(host, i)  host->h_addr_list[i]
#else  /* ! h_addr */
#define ADDR(host, i)  host->h_addr
#endif  /* ! h_addr */

#define FILL_SOCKADDR(AF_INET, sockaddr_in, sin, s,             \
                      host, port, count, addrlen, addrs)        \
  do                                                            \
    {                                                           \
      struct sockaddr_in *addr;                                 \
      int i;                                                    \
                                                                \
      addrlen = sizeof(struct sockaddr_in);                     \
                                                                \
      addr = (struct sockaddr_in *) calloc(count, addrlen);     \
      for (i = 0; i < count; ++i)                               \
        {                                                       \
          addr[i].sin##_family = AF_INET;                       \
          addr[i].sin##_port = port;                            \
          memcpy(&addr[i].sin##_addr.s##_addr,                  \
                 ADDR(host, i), host->h_length);                \
        }                                                       \
                                                                \
      addrs = (char *) addr;                                    \
    }                                                           \
  while (0)

#define fill_sockaddr(host, port, count, addrlen, addrs)        \
  FILL_SOCKADDR(AF_INET, sockaddr_in, sin, s,                   \
                host, port, count, addrlen, addrs)

#ifdef AF_INET6
#define fill_sockaddr6(host, port, count, addrlen, addrs)       \
  FILL_SOCKADDR(AF_INET6, sockaddr_in6, sin6, s6,               \
                host, port, count, addrlen, addrs)
#endif  /* AF_INET6 */


int
getaddrinfo_hostent(const char *node, const char *service,
                    const struct addrinfo_hostent *hints,
                    struct addrinfo_hostent **res)
{
  struct hostent *host;
  struct servent *serv;
  int count, i;
  int port;
  char *name;
  size_t addrlen;
  char *addrs;
  struct addrinfo_hostent *addrinfos;

  host = gethostbyname(node);
  if (! host
      || (hints->ai_family != AF_UNSPEC
          && host->h_addrtype != hints->ai_family))
    return -1;

  count = 1;
#ifdef h_addr
  while (host->h_addr_list[count])
    ++count;
#endif  /* h_addr */

  serv = getservbyname(service, (hints->ai_socktype == SOCK_STREAM
                                 ? "tcp" : "udp"));
  port = serv ? serv->s_port : htons(atoi(service));

  if (host->h_name)
    {
      size_t name_len = strlen(host->h_name);
      name = (char *) malloc(name_len + 1);
      memcpy(name, host->h_name, name_len + 1);
    }
  else
    {
      name = NULL;
    }

#ifdef AF_INET6
  if (host->h_addrtype == AF_INET6)
    fill_sockaddr6(host, port, count, addrlen, addrs);
  else
#endif  /* AF_INET6 */
    fill_sockaddr(host, port, count, addrlen, addrs);


  addrinfos = (struct addrinfo_hostent *) malloc(sizeof(*addrinfos) * count);
  addrinfos[0].ai_flags = hints->ai_flags;
  addrinfos[0].ai_family = host->h_addrtype;
  addrinfos[0].ai_socktype = hints->ai_socktype;
  addrinfos[0].ai_protocol = hints->ai_protocol;
  addrinfos[0].ai_addrlen = addrlen;
  addrinfos[0].ai_addr = (struct sockaddr *) addrs;
  addrinfos[0].ai_canonname = name;
  for (i = 1; i < count; ++i)
    {
      addrinfos[i] = addrinfos[0];

      addrinfos[i].ai_addr = (struct sockaddr *) (addrs + addrlen * i);
      addrinfos[i - 1].ai_next = &addrinfos[i];
    }
  addrinfos[i - 1].ai_next = NULL;

  *res = addrinfos;

  return 0;
}


void
freeaddrinfo_hostent(struct addrinfo_hostent *res)
{
  free(res->ai_addr);
  free(res->ai_canonname);
  free(res);
}
