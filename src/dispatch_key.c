/*
  Copyright (C) 2007 Tomash Brechko.  All rights reserved.

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
#include <stdlib.h>


/*
  Note on rounding: C89 (which we are trying to be compatible with)
  doesn't have round-to-nearest function, only ceil() and floor(), so
  we add 0.5 to doubles before casting them to integers (and the cast
  always rounds toward zero).
*/


#define DISPATCH_MAX_POINT  0xffffffffU


struct dispatch_continuum_point
{
  unsigned int point;
  int index;
};


static inline
int
extend_bins(struct dispatch_state *state, int add)
{
  int capacity =
    (state->bins_capacity > 0 ? state->bins_capacity + add : add);
  struct dispatch_continuum_point *b =
    (struct dispatch_continuum_point *)
      realloc(state->bins,
              capacity * sizeof(struct dispatch_continuum_point));

  if (! b)
    return -1;

  state->bins = b;
  state->bins_capacity = capacity;

  return 0;
}


static
int
dispatch_find_bin(struct dispatch_state *state, unsigned int point)
{
  struct dispatch_continuum_point *left, *right;

  left = state->bins;
  right = state->bins + state->bins_count;

  while (left < right)
    {
      struct dispatch_continuum_point *middle = left + (right - left) / 2;
      if (middle->point < point)
        left = middle + 1;
      else if (middle->point > point)
        right = middle;
      else
        return (middle - state->bins);
    }

  /* Wrap around.  */
  if (left == state->bins + state->bins_count)
    left = state->bins;

  return (left - state->bins);
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
  int i;
  double scale;

  if (state->bins_count == state->bins_capacity)
    {
      int res = extend_bins(state, 1);
      if (res == -1)
        return -1;
    }

  state->total_weight += weight;
  scale = (1 - weight / state->total_weight);
  for (i = 0; i < state->bins_count; ++i)
    state->bins[i].point = ((double) state->bins[i].point * scale + 0.5);

  state->bins[state->bins_count].point = DISPATCH_MAX_POINT;
  state->bins[state->bins_count].index = index;

  ++state->bins_count;

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
    that module put 'weight' copies of each the server into buckets
    array, our '(unsigned int) (state->total_weight + 0.5)' is equal
    to the number of such buckets (0.5 is there for proper rounding).
    The we scale 'point' to the continuum, and since each server
    occupies the space proportional to its weight, we get the same
    server index.
  */
  int bin;
  unsigned int crc32 = compute_crc32(key, key_len);
  unsigned int hash = ((crc32 >> 16) & 0x00007fff);
  unsigned int point = hash % (unsigned int) (state->total_weight + 0.5);

  point = ((double) point / state->total_weight * DISPATCH_MAX_POINT + 0.5);
  /*
    Shift point one step forward to possibly get from the border point
    which belongs to the previous bin.
  */
  point += 1;

  bin = dispatch_find_bin(state, point);
  return state->bins[bin].index;
}


static inline
int
ketama_crc32_add_server(struct dispatch_state *state,
                        const char *host, size_t host_len,
                        const char *port, size_t port_len,
                        double weight, int index)
{
  static const char delim = '\0';
  unsigned int crc32;
  int count, i;

  count = (state->ketama_points * weight + 0.5);

  if (state->bins_count + count > state->bins_capacity)
    {
      int add = state->bins_count + count - state->bins_capacity;
      int res = extend_bins(state, add);
      if (res == -1)
        return -1;
    }

  crc32 = compute_crc32(host, host_len);
  crc32 = compute_crc32_add(crc32, &delim, 1);
  crc32 = compute_crc32_add(crc32, port, port_len);

  for (i = 0; i < count; ++i)
    {
      char buf[4];
      unsigned int point;
      int bin;

      /*
        We want the same result on all platforms, so we hardcode size
        of int as 4 8-bit bytes.
      */
      buf[0] = i & 0xff;
      buf[1] = (i >> 8) & 0xff;
      buf[2] = (i >> 16) & 0xff;
      buf[3] = (i >> 24) & 0xff;

      point = compute_crc32_add(crc32, buf, 4);

      if (state->bins_count > 0)
        {
          bin = dispatch_find_bin(state, point);

          /* Check if we wrapped around but actually have new max point.  */
          if (bin == 0 && point > state->bins[0].point)
            {
              bin = state->bins_count;
            }
          else
            {
              if (point == state->bins[bin].point)
                {
                  /*
                    Even if there's a server for the same point
                    already, we have to add ours, because the first
                    one may be removed later.  But we add ours after
                    the first server for not to change key
                    distribution.
                  */
                  ++bin;
                }

              /* Move the tail one position forward.  */
              memmove(state->bins + bin + 1, state->bins + bin,
                      (state->bins_count - bin) * sizeof(*state->bins));
            }
        }
      else
        {
          bin = 0;
        }

      state->bins[bin].point = point;
      state->bins[bin].index = index;

      ++state->bins_count;
    }

  return 0;
}


static inline
int
ketama_crc32_get_server(struct dispatch_state *state,
                        const char *key, size_t key_len)
{
  unsigned int point = compute_crc32(key, key_len);
  int bin = dispatch_find_bin(state, point);
  return state->bins[bin].index;
}


void
dispatch_init(struct dispatch_state *state)
{
  state->bins = NULL;
  state->bins_count = state->bins_capacity = 0;
  state->total_weight = 0.0;
  state->ketama_points = 0;
}


void
dispatch_destroy(struct dispatch_state *state)
{
  free(state->bins);
}


void
dispatch_set_ketama_points(struct dispatch_state *state, int ketama_points)
{
  state->ketama_points = ketama_points;
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
  if (state->bins_count == 0)
    return -1;

  if (state->bins_count == 1)
    {
      return state->bins[0].index;
    }
  else
    {
      if (state->ketama_points > 0)
        return ketama_crc32_get_server(state, key, key_len);
      else
        return compatible_get_server(state, key, key_len);
    }
}
