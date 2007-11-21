#! /usr/bin/perl
#
use warnings;
use strict;

use FindBin;


my %C = (
    parse_func_name => 'parse_reply',
    str_ptr => 'str_ptr',
    str_match_ptr => 'str_match_ptr',
    str_end_ptr => 'str_end_ptr',
);


my @keywords = (
    'CLIENT_ERROR\r\n',
    'DELETED\r\n',
    'END\r\n',
    'ERROR\r\n',
    'EXISTS\r\n',
    'NOT_FOUND\r\n',
    'NOT_STORED\r\n',
    'OK\r\n',
    'SERVER_ERROR ',
    'STAT ',
    'STORED\r\n',
    'VALUE ',
    'VERSION ',
);


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


my @external_enum = qw(INITIAL NO_MATCH);
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
$I  $C{str_match_ptr} = "$common";

$I  do
$I    {
$I      if ($C{str_ptr} == $C{str_end_ptr})
$I        return phase;

$I    LABEL_$prefix:
$I      if (*$C{str_ptr}++ != *$C{str_match_ptr}++)
$I        return NO_MATCH;
$I    }
$I  while (*$C{str_match_ptr});

$I  phase = $phase;

EOF
    }
    if ($common or $depth) {
        if (@keys) {
            push @internal_labels, $phase;
            $res .= <<"EOF";
$I  if ($C{str_ptr} == $C{str_end_ptr})
$I    return phase;

${I}LABEL_$phase:
EOF
        } else {
            push @external_enum, $phase;
            $res .= <<"EOF";
$I  return phase;

EOF
            return $res;
        }
    }

    $res .= <<"EOF";
$I  switch (*$C{str_ptr})
$I    {
EOF

    foreach my $key (@keys) {
        my $subphase = $phase . $key;
        $res .= <<"EOF";
$I    case '$key':
$I      phase = $subphase;

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


my $switch = create_switch(0, 'PHASE_', @$tree);


my $i = 0;
print <<"EOF";
/*
  This file was generated with $FindBin::Script.  Do not edit.
*/


enum $C{parse_func_name}_e {
  @{[ join ",\n  ", @external_enum ]}
};


int
$C{parse_func_name}(int phase)
{
  /*
    Use negative values to avoid collision with elements
    of $C{parse_func_name}_e.
  */
  enum {
    @{[ join ",\n    ", map { "$_ = " . --$i } @internal_labels ]}
  };

  /*
    Jump table to bring us to the place we stopped last time.
  */
  switch (phase)
    {
EOF
foreach my $label (@internal_labels) {
    print <<"EOF";
    case $label:
      goto LABEL_$label;
EOF
}
print <<"EOF";
    default:
      break;
    }

EOF

print $switch;

print <<"EOF";
}
EOF
