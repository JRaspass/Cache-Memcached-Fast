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


my @keys = map { "get_multi_$_" } (1 .. 2048);

$Memd::memd->set_multi(map { [ $_, 'x' x (990 + int(rand(20))) ] } @keys);

for (1 .. 100) {
    $Memd::memd->prepend("get_multi_" . (1 + int(rand(@keys))), 'x');
}

my $res = $Memd::memd->get_multi(@keys);

isa_ok($res, 'HASH');

$Memd::memd->delete_multi(@keys);
