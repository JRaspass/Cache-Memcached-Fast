use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 6;
} else {
    plan skip_all => 'Not connected';
}


my $key1 = 'big_request1';
my $key2 = 'big_request2';

$Memd::memd->enable_compress(0);

ok($Memd::memd->set($key1, 'x' x 1_000_000));
ok($Memd::memd->set($key2, 'value2'));

my $res = $Memd::memd->get_multi(($key1) x 10, ('no_such_key') x 10, $key2);
isa_ok($res, 'HASH');
is(scalar keys %$res, 2);

ok($Memd::memd->delete($key1));
ok($Memd::memd->delete($key2));
