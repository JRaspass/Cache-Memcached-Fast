#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use Memd;
use Test::More;

if ($Memd::memd) {
    plan tests => 34;
} 
else {
    plan skip_all => 'Not connected';
}

# add some values to the server
foreach ( 1 .. 3 ) {
   my ($key, $val) = ("k$_", "v$_");
   ok($Memd::memd->set($key, $val), "set '$key' to '$val'");
   is($Memd::memd->get($key), $val, "fetch '$key'");
}

# test that the no values are set on the server if one or more
# values in a call to set_multi are not defined
# or if the argument to set_multi is not an array reference
my @tests = (
   [ ['k1', 'new v1'], [], ['k2', 'new k2'] ],
   [ [], ['k1', 'new v1'], ['k2', 'new k2'] ],
   [ ['k1', 'new v1'], ['k2', 'new k2'], [] ],
   [ [undef, 'new v1'], ['k2', 'new v2'] ],
   [ ['k1', 'new v1'], ['k2', undef] ],
   [ ['k2', 'new v1'], undef ],
   [ undef, ['k2', 'new v2'] ],
);
foreach my $test ( @tests ) {
   eval {
      # no values should be updated after this set_multi
      $Memd::memd->set_multi( @$test );
   };
   ok $@, 'Croaked on empty value passed to set_multi';

   foreach ( 1 .. 3 ) {
      my ($key, $val) = ("k$_", "v$_");
      is($Memd::memd->get($key), $val, "fetch '$key'");
   }
}

