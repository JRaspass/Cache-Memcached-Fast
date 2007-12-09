#ifndef CONNECT_H
#define CONNECT_H 1

#include <stddef.h>


extern
int
client_connect_inet(const char *host, const char *port, int stream,
                    int timeout);

extern
int
client_connect_unix(const char *path, size_t path_len);


#endif /* ! CONNECT_H */
