#ifndef CONNECT_H
#define CONNECT_H 1


extern
int
client_connect_inet(const char *host, const char *port, int stream,
                    int timeout);


#endif // ! CONNECT_H
