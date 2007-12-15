#! /usr/bin/perl
#
# Copyright (C) 2007 Tomash Brechko.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.8
# or, at your option, any later version of Perl 5 you may have
# available.
#
use warnings;
use strict;

use FindBin;

@ARGV == 3
  or die "Usage: $FindBin::Script KEYWORD_FILE FILE_C FILE_H\n";

my ($keyword_file, $file_c, $file_h) = @ARGV;


my %C;
my @keywords;

open(my $kw, '<', $keyword_file)
  or die "open(< $keyword_file): $!";

my $section = 0;
while (my $line = <$kw>) {
    chomp $line;

    if ($line =~ /^\s*(?:#.*)?$/) {
        next;
    } elsif ($line =~ /^\s*%%\s*$/) {
        ++$section;
        next;
    }

    if ($section == 0 and $line =~ /^\s*(\S+)\s*=\s*(\S+)\s*$/) {
        $C{$1} = $2;
    } elsif ($section == 1) {
        push @keywords, $line;
    } else {
        die "Can't parse line: $line";
    }
}

close($kw);


sub dispatch_keywords {
    my ($words) = @_;

    return $words if @$words <= 1;

    my $len = 0;
    my $common = 1;
    while ($common) {
        ++$len;
        my $prefix = substr($$words[0], 0, $len);
        $common = ! grep(!/^$prefix/, @$words);
    }
    --$len;

    my $prefix = substr($$words[0], 0, $len);

    my %subtree;
    foreach my $word (@$words) {
        my $key = substr($word, $len, 1);
        my $val = substr($word, $len + 1);
        push @{$subtree{$key}}, $val;
    }

    foreach my $val (values %subtree) {
        $val = dispatch_keywords($val);
    }

    return [$prefix, \%subtree];
}


my $tree = dispatch_keywords(\@keywords);


my @external_enum = qw(NO_MATCH);

sub create_switch {
    my ($depth, $prefix, $common, $hash) = @_;

    my $I = ' ' x ($depth * 4);
    my @keys = sort keys %$hash;
    (my $common_ident = $common) =~ s/[^A-Z_]//g;
    my $phase = $prefix . $common_ident;
    my $res = '';

    if ($common) {
        if ($C{loose_match}) {
            $res .= <<"EOF";
$I  *pos += @{[ length $common ]};

EOF
        } else {
            $res .= <<"EOF";
$I  match_pos = "$common";

$I  do
$I    {
$I      if (**pos != *match_pos)
$I        return NO_MATCH;

$I      ++*pos;
$I      ++match_pos;
$I    }
$I  while (*match_pos != '\\0');

EOF
        }
    }
    if ($common or $depth) {
        if (! @keys) {
            push @external_enum, $phase;
            $res .= <<"EOF";
$I  return $phase;

EOF
            return $res;
        }
    }

    $res .= <<"EOF";
$I  switch (*(*pos)++)
$I    {
EOF

    foreach my $key (@keys) {
        my $subphase = $phase . $key;
        $res .= <<"EOF";
$I    case '$key':
EOF
        $res .= create_switch($depth + 1, $subphase, @{$$hash{$key}});
    }

    $res .= <<"EOF";
$I    default:
$I      return NO_MATCH;
$I    }
EOF

    return $res;
}


my $switch = create_switch(0, 'MATCH_', @$tree);


my $gen_comment = <<"EOF";
/*
  This file was generated with $FindBin::Script from
  $keyword_file.

  Instead of editing this file edit the keyword file and regenerate.
*/
EOF


open(my $fc, '>', $file_c)
  or die "open(> $file_c): $!";

my $i = 0;
print $fc <<"EOF";
$gen_comment
#include "$file_h"


enum $C{parser_func}_e
$C{parser_func}(char **pos)
{
EOF

unless ($C{loose_match}) {
    print $fc <<"EOF";
  char *match_pos;

EOF
}

print $fc <<"EOF";
$switch
  /* Never reach here.  */
}
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


enum $C{parser_func}_e {
  @{[ join ",\n  ", @external_enum ]}
};


extern
enum $C{parser_func}_e
$C{parser_func}(char **pos);


#endif /* ! $guard */
EOF

close($fh)
  or die "close($file_h): $!";
