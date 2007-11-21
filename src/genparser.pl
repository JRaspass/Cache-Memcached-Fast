#! /usr/bin/perl
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
my @internal_labels;

sub create_switch {
    my ($depth, $prefix, $common, $hash) = @_;

    my $I = ' ' x ($depth * 4);
    my @keys = sort keys %$hash;
    (my $common_ident = $common) =~ s/[^A-Z_]//g;
    my $phase = $prefix . $common_ident;
    my $res = '';

    if ($common) {
        push @internal_labels, $prefix;
        $res .= <<"EOF";
$I  state->match_pos = "$common";

$I  do
$I    {
$I      if (state->buf == state->buf_end)
$I        return 0;

$I    LABEL_$prefix:
$I      if (*state->buf++ != *state->match_pos++)
$I        {
$I          state->phase = NO_MATCH;
$I          return -1;
$I        }
$I    }
$I  while (*state->match_pos);

$I  state->phase = $phase;

EOF
    }
    if ($common or $depth) {
        if (@keys) {
            push @internal_labels, $phase;
            $res .= <<"EOF";
$I  if (state->buf == state->buf_end)
$I    return 0;

${I}LABEL_$phase:
EOF
        } else {
            push @external_enum, $phase;
            $res .= <<"EOF";
$I  return 1;

EOF
            return $res;
        }
    }

    $res .= <<"EOF";
$I  switch (*state->buf)
$I    {
EOF

    foreach my $key (@keys) {
        my $subphase = $phase . $key;
        $res .= <<"EOF";
$I    case '$key':
$I      state->phase = $subphase;

EOF
        $res .= create_switch($depth + 1, $subphase, @{$$hash{$key}});
    }

    $res .= <<"EOF";
$I    default:
$I      state->phase = NO_MATCH;
$I      return -1;
$I    }
EOF

    return $res;
}


my $switch = create_switch(0, 'PHASE_', @$tree);


my $gen_comment = <<"EOF";
/*
  This file was generated with $FindBin::Script from
  $keyword_file.

  Instead of editing this file edit the keyword file and regenerate.
*/
EOF

my $func_comment = <<"EOF";
/*
   $C{parser_func}() returns
     -1 when no match.
      0 when parsing is not finished yet.
      1 when matched.
*/
EOF


open(my $fc, '>', $file_c)
  or die "open(> $file_c): $!";

my $i = 0;
print $fc <<"EOF";
$gen_comment
#include "$file_h"


${func_comment}int
$C{parser_func}(struct genparser_state *state)
{
  /*
    Use negative values to avoid collision with elements
    of $C{parser_func}_e defined in $file_h.
  */
  enum {
    @{[ join ",\n    ", map { "$_ = " . --$i } @internal_labels ]}
  };

  /*
    Jump table to bring us to the place we stopped last time.
  */
  switch (state->phase)
    {
EOF
foreach my $label (@internal_labels) {
    print $fc <<"EOF";
    case $label:
      goto LABEL_$label;
EOF
}
print $fc <<"EOF";
    default:
      break;
    }

$switch
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

#include "${FindBin::Dir}genparser.h"


enum $C{parser_func}_e {
  @{[ join ",\n  ", @external_enum ]}
};


${func_comment}extern
int
$C{parser_func}(struct genparser_state *state);


#endif /* ! $guard */
EOF

close($fh)
  or die "close($file_h): $!";
