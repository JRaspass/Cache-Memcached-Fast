#ifndef PROTOCOL_H
#define PROTOCOL_H 1

#include <stddef.h>


extern
int
protocol_set(int fd, const char *key, size_t key_len,
             unsigned int flags, unsigned int exptime,
             const void *val, size_t val_size);


#endif /* ! PROTOCOL_H */
