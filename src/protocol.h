#ifndef PROTOCOL_H
#define PROTOCOL_H 1

#include "server.h"
#include <stddef.h>


extern
int
protocol_set(int fd, const char *key, size_t key_len,
             flags_type flags, exptime_type exptime,
             const void *val, size_t val_size);

extern
int
protocol_get(int fd, const char *key, size_t key_len,
             alloc_value_func alloc_value, void *alloc_value_arg);


#endif /* ! PROTOCOL_H */
