#ifndef PROTOCOL_H
#define PROTOCOL_H 1

#include "server.h"
#include <stddef.h>
#include <sys/uio.h>


extern
int
protocol_set(int fd, struct iovec *iov, int iov_count,
             const void *val, size_t val_size);

extern
int
protocol_get(int fd, struct iovec *iov, int iov_count,
             alloc_value_func alloc_value, void *alloc_value_arg);


#endif /* ! PROTOCOL_H */
