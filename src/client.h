#ifndef CLIENT_H
#define CLIENT_H 1

#include <stddef.h>


struct server
{
  char *host;
  char *port;
  int fd;
};


struct client
{
  struct server *servers;
  size_t server_count;
  size_t server_capacity;
  int connect_timeout;          /* 1/1000 sec.  */
  int io_timeout;               /* 1/1000 sec.  */
  char *namespace_prefix;
  size_t namespace_prefix_len;
};


extern
void
client_init(struct client *c);

extern
void
client_destroy(struct client *c);


#endif // ! CLIENT_H
