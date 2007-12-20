use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

use constant count => 1000;

if ($Memd::memd) {
    plan tests => 3;
} else {
    plan skip_all => 'Not connected';
}


my @keys = map { "nowait-$_" } (1..count);

foreach my $k (@keys) {
    $Memd::memd->set($k, $k);
}

my $res = $Memd::memd->get_multi(@keys);
isa_ok($res, 'HASH');
is(scalar keys %$res, count, 'Fetched all keys');
my $count = 0;
while (my ($k, $v) = each %$res) {
    ++$count if $k eq $v;
}
is($count, count, 'Match results');

foreach my $k (@keys) {
    $Memd::memd->delete($k);
}
