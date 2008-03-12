#! /usr/bin/perl
#
# Copyright (C) 2007-2008 Tomash Brechko.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.8
# or, at your option, any later version of Perl 5 you may have
# available.
#
use warnings;
use strict;

use FindBin;

@ARGV == 2
  or die "Usage: $FindBin::Script FILE_C FILE_H\n";

my ($file_c, $file_h) = @ARGV;

my $poly = 0xedb88320;
my $init = 0x0;


sub gen_lookup {
    my ($poly) = @_;

    my @lookup;

    for (my $i = 0; $i < 256; ++$i) {
        my $crc32 = $i;
        for (my $j = 8; $j > 0; --$j) {
            if ($crc32 & 0x1) {
                $crc32 = ($crc32 >> 1) ^ $poly;
            } else {
                $crc32 >>= 1;
            }
        }
        push @lookup, $crc32;
    }

    return \@lookup;
}


my $lookup = gen_lookup($poly);

my $table;
while (@$lookup) {
    $table .= join(', ',
                  map { sprintf("0x%08xU", $_) } splice(@$lookup, 0, 6));
    $table .= ",\n  ";
}
$table =~ s/,\n  \Z//;

my $gen_comment = <<"EOF";
/*
  This file was generated with $FindBin::Script.

  Do not edit.
*/
EOF


open(my $fc, '>', $file_c)
  or die "open(> $file_c): $!";

print $fc <<"EOF";
$gen_comment
#include "$file_h"


const unsigned int crc32lookup[256] = {
  $table
};
EOF

close($fc)
  or die "close($file_c): $!";


my $guard = uc $file_h;
$guard =~ s/[^[:alnum:]_]/_/g;

open(my $fh, '>', $file_h)
  or die "open(> $file_h): $!";


print $fh <<"EOF";
$gen_comment
#ifndef $guard
#define $guard 1

#include <stddef.h>


extern const unsigned int crc32lookup[];


#define compute_crc32(s, l)                                      \\
  compute_crc32_add(@{[ sprintf("0x%08xU", $init) ]}, (s), (l))

static inline
unsigned int
compute_crc32_add(unsigned int crc32, const char *s, size_t len)
{
  const char *end = s + len;

  crc32 = ~crc32;

  while (s < end)
    {
      unsigned int index = (crc32 ^ (unsigned char) *s) & 0x000000ffU;
      crc32 = (crc32 >> 8) ^ crc32lookup[index];
      ++s;
    }

  return (~crc32);
}


#endif /* ! $guard */
EOF

close($fh)
  or die "close($file_h): $!";
