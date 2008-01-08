/*
  Copyright (C) 2008 Tomash Brechko.  All rights reserved.

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

#ifndef ARRAY_H
#define ARRAY_H 1


struct array
{
  void *buf;
  int capacity;
  int elems;
};


extern
void
array_init(struct array *a);


extern
void
array_destroy(struct array *a);


enum e_array_extend { ARRAY_EXTEND_EXACT, ARRAY_EXTEND_TWICE };


extern
int
array_resize(struct array *a, int elem_size, int elems,
             enum e_array_extend extend);


#define array_extend(array, type, add, extend)                          \
  array_resize(&(array), sizeof(type), (array).elems + add, extend)

#define array_push(array)  ++(array).elems

#define array_pop(array)  --(array).elems

#define array_append(array, add)  (array).elems += add

#define array_size(array)  ((array).elems)

#define array_empty(array)  ((array).elems == 0)

#define array_clear(array)  (array).elems = 0

#define array_elem(array, type, index)  ((type *) (array).buf + index)

#define array_beg(array, type)  ((type *) (array).buf)

#define array_end(array, type)  ((type *) (array).buf + (array).elems)

#define array_each(array, type, p)                                      \
  (p) = array_beg(array, type); (p) != array_end(array, type); ++(p)


#endif /* ! ARRAY_H */
