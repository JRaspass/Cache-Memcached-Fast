/*
  Copyright (C) 2007-2009 Tomash Brechko.  All rights reserved.

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

#include "dispatch_key.h"
#include "compute_crc32.h"
#include <string.h>


/*
  Note on rounding: C89 (which we are trying to be compatible with)
  doesn't have round-to-nearest function, only ceil() and floor(), so
  we add 0.5 to doubles before casting them to integers (and the cast
  always rounds toward zero).
*/


#define DISPATCH_MAX_POINT  0xffffffffU


struct continuum_point
{
  unsigned int point;
  int index;
};


static
struct continuum_point *
dispatch_find_bucket(struct dispatch_state *state, unsigned int point)
{
  struct continuum_point *beg, *end, *left, *right;

  beg = left = array_beg(state->buckets, struct continuum_point);
  end = right = array_end(state->buckets, struct continuum_point);

  while (left < right)
    {
      struct continuum_point *middle = left + (right - left) / 2;
      if (middle->point < point)
        {
          left = middle + 1;
        }
      else if (middle->point > point)
        {
          right = middle;
        }
      else
        {
          /* Find the first point for this value.  */
          while (middle != beg && (middle - 1)->point == point)
            --middle;

          return middle;
        }
    }

  /* Wrap around.  */
  if (left == end)
    left = beg;

  return left;
}


static inline
int
compatible_add_server(struct dispatch_state *state, double weight, int index)
{
  /*
    For compatibility with Cache::Memcached we put each server in a
    continuum so that it occupies the space proportional to its
    weight.  See the comment in compatible_get_server().
  */
  double scale;
  struct continuum_point *p;

  if (array_extend(state->buckets, struct continuum_point,
                   1, ARRAY_EXTEND_EXACT) == -1)
    return -1;

  state->total_weight += weight;
  scale = weight / state->total_weight;
  /*
    Note that during iterative scaling below the rounding error
    accumulates.  However the offset to the smaller values is alright
    as long as it is smaller than the interval length, which is big
    enough for sane number of servers (thousands) and relative weight
    ratios.
  */
  for (array_each(state->buckets, struct continuum_point, p))
    p->point -= (double) p->point * scale;

  /* Here p points to array_end().  */
  p->point = DISPATCH_MAX_POINT;
  p->index = index;
  array_push(state->buckets);

  ++state->server_count;

  return 0;
}


static inline
int
compatible_get_server(struct dispatch_state *state,
                      const char *key, size_t key_len)
{
  /*
    For compatibility with Cache::Memcached we do the following: first
    we compute 'hash' the same way the original module does.  Since
    that module puts 'weight' copies of each server into buckets
    array, our '(unsigned int) (state->total_weight + 0.5)' is equal
    to the number of such buckets (0.5 is there for proper rounding).
    Then we scale 'point' to the continuum, and since each server
    occupies the space proportional to its weight, we get the same
    server index.
  */
  struct continuum_point *p;
  unsigned int crc32 = compute_crc32_add(state->prefix_hash, key, key_len);
  unsigned int hash = (crc32 >> 16) & 0x00007fffU;
  unsigned int point = hash % (unsigned int) (state->total_weight + 0.5);

  point = (double) point / state->total_weight * DISPATCH_MAX_POINT + 0.5;
  /*
    Shift point one step forward to possibly get from the border point
    which belongs to the previous bucket.
  */
  point += 1;

  p = dispatch_find_bucket(state, point);
  return p->index;
}


static inline
int
ketama_crc32_add_server(struct dispatch_state *state,
                        const char *host, size_t host_len,
                        const char *port, size_t port_len,
                        double weight, int index)
{
  static const char delim = '\0';
  unsigned int crc32, point;
  int count, i;

  count = state->ketama_points * weight + 0.5;

  if (array_extend(state->buckets, struct continuum_point,
                   count, ARRAY_EXTEND_EXACT) == -1)
    return -1;

  crc32 = compute_crc32(host, host_len);
  crc32 = compute_crc32_add(crc32, &delim, 1);
  crc32 = compute_crc32_add(crc32, port, port_len);
  point = 0;

  for (i = 0; i < count; ++i)
    {
      char buf[4];
      struct continuum_point *p;

      /*
        We want the same result on all platforms, so we hardcode size
        of int as 4 8-bit bytes.
      */
      buf[0] = point & 0xff;
      buf[1] = (point >> 8) & 0xff;
      buf[2] = (point >> 16) & 0xff;
      buf[3] = (point >> 24) & 0xff;

      point = compute_crc32_add(crc32, buf, 4);

      if (! array_empty(state->buckets))
        {
          struct continuum_point *end =
            array_end(state->buckets, struct continuum_point);

          p = dispatch_find_bucket(state, point);

          /* Check if we wrapped around but actually have new max point.  */
          if (p == array_beg(state->buckets, struct continuum_point)
              && point > p->point)
            {
              p = end;
            }
          else
            {
              /*
                Even if there's a server for the same point already,
                we have to add ours, because the first one may be
                removed later.  But we add ours after the old servers
                for not to change key distribution.
              */
              while (p != end && p->point == point)
                ++p;

              /* Move the tail one position forward.  */
              if (p != end)
                memmove(p + 1, p, (end - p) * sizeof(*p));
            }
        }
      else
        {
          p = array_beg(state->buckets, struct continuum_point);
        }

      p->point = point;
      p->index = index;
      array_push(state->buckets);
    }

  ++state->server_count;

  return 0;
}


static inline
int
ketama_crc32_get_server(struct dispatch_state *state,
                        const char *key, size_t key_len)
{
  unsigned int point = compute_crc32_add(state->prefix_hash, key, key_len);
  struct continuum_point *p = dispatch_find_bucket(state, point);
  return p->index;
}


void
dispatch_init(struct dispatch_state *state)
{
  array_init(&state->buckets);
  state->total_weight = 0.0;
  state->ketama_points = 0;
  state->prefix_hash = 0x0U;
  state->server_count = 0;
}


void
dispatch_destroy(struct dispatch_state *state)
{
  array_destroy(&state->buckets);
}


void
dispatch_set_ketama_points(struct dispatch_state *state, int ketama_points)
{
  state->ketama_points = ketama_points;
}


void
dispatch_set_prefix(struct dispatch_state *state,
                    const char *prefix, size_t prefix_len)
{
  state->prefix_hash = compute_crc32(prefix, prefix_len);
}


int
dispatch_add_server(struct dispatch_state *state,
                    const char *host, size_t host_len,
                    const char *port, size_t port_len,
                    double weight, int index)
{
  if (state->ketama_points > 0)
    return ketama_crc32_add_server(state, host, host_len, port, port_len,
                                   weight, index);
  else
    return compatible_add_server(state, weight, index);
}


int
dispatch_key(struct dispatch_state *state, const char *key, size_t key_len)
{
  if (state->server_count == 0)
    return -1;

  if (state->server_count == 1)
    {
      struct continuum_point *p =
        array_beg(state->buckets, struct continuum_point);
      return p->index;
    }
  else
    {
      if (state->ketama_points > 0)
        return ketama_crc32_get_server(state, key, key_len);
      else
        return compatible_get_server(state, key, key_len);
    }
}
