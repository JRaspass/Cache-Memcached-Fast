/*
  Copyright (C) 2007 by Tomash Brechko.  All rights reserved.

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
#include <stdlib.h>


#define DISPATCH_MAX_POINT  0xffffffffU


struct dispatch_continuum_point
{
  unsigned int point;
  int index;
};


static
int
dispatch_find_server_index(struct dispatch_state *state, unsigned int point)
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
        return middle->index;
    }

  if (left == state->bins + state->bins_count)
    left = state->bins;

  return left->index;
}


static inline
void
compatible_add_server(struct dispatch_state *state, double weight, int index)
{
  /*
    For compatibility with Cache::Memcached we put each server in a
    continuum so that it occupies the space proportional to its
    weight.  See the comment in compatible_get_server().
  */
  int i;
  double scale;

  state->total_weight += weight;
  scale = (1 - weight / state->total_weight);
  for (i = 0; i < state->bins_count; ++i)
    state->bins[i].point = (double) state->bins[i].point * scale;

  state->bins[state->bins_count].point = DISPATCH_MAX_POINT;
  state->bins[state->bins_count].index = index;
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
  unsigned int crc32 = compute_crc32(key, key_len);
  unsigned int hash = ((crc32 >> 16) & 0x00007fff);
  unsigned int point = hash % (unsigned int) (state->total_weight + 0.5);

  point = (double) point / state->total_weight * DISPATCH_MAX_POINT;

  return dispatch_find_server_index(state, point);
}


void
dispatch_init(struct dispatch_state *state)
{
  state->bins = NULL;
  state->bins_count = state->bins_capacity = 0;
  state->total_weight = 0.0;
}


int
dispatch_add_server(struct dispatch_state *state, double weight, int index)
{
  if (state->bins_count == state->bins_capacity)
    {
      int capacity =
        (state->bins_capacity > 0 ? state->bins_capacity + 1 : 1);
      struct dispatch_continuum_point *b =
        (struct dispatch_continuum_point *)
          realloc(state->bins,
                  capacity * sizeof(struct dispatch_continuum_point));

      if (! b)
        return -1;

      state->bins = b;
      state->bins_capacity = capacity;
    }

  compatible_add_server(state, weight, index);

  ++state->bins_count;

  return 0;
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
      return compatible_get_server(state, key, key_len);
    }
}
