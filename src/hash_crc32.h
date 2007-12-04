#ifndef HASH_CRC32_H
#define HASH_CRC32_H 1

#include "compute_crc32.h"


static inline
unsigned int
hash_crc32(const char *s, size_t len)
{
  unsigned int crc32 = compute_crc32(s, len);
  return ((crc32 >> 16) & 0x00007fff);
}


#endif // ! HASH_CRC32_H
