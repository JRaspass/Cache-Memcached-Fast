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

#include "array.h"
#include <stdlib.h>


void
array_init(struct array *a)
{
  a->buf = NULL;
  a->capacity = a->elems = 0;
}


void
array_destroy(struct array *a)
{
  free(a->buf);
}


int
array_resize(struct array *a, int elem_size, int elems,
             enum e_array_extend extend)
{
  void *buf;

  if (elems <= a->capacity)
    return 0;

  if (extend == ARRAY_EXTEND_TWICE && elems < a->capacity * 2)
    elems = a->capacity * 2;

  buf = realloc(a->buf, elem_size * elems);
  if (! buf)
    return -1;

  a->buf = buf;
  a->capacity = elems;

  return 0;
}
