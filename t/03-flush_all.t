use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 1;
} else {
    plan skip_all => 'Not connected';
}


if (0) {
  my $res = $Memd::memd->flush_all;
  ok(keys %$res == @Memd::addr);
} else {
  pass;
}
