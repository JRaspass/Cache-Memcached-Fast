use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 5;
} else {
    plan skip_all => 'Not connected';
}


use constant count => 1000;

my $another_memd = new Cache::Memcached::Fast(\%Memd::params);

my @keys = map { "nowait-$_" } (1..count);

foreach my $k (@keys) {
    $Memd::memd->set($k, $k);
}

$Memd::memd->replace('no-such-key', 1);
$Memd::memd->replace('no-such-key', 1);

my @extra_keys = @keys;
for (1..count) {
    splice(@extra_keys, int(rand(@extra_keys + 1)), 0, "no_such_key-$_");
}
my $res = $Memd::memd->get_multi(@extra_keys);
isa_ok($res, 'HASH');
is(scalar keys %$res, count, 'Fetched all keys');
my $count = 0;
while (my ($k, $v) = each %$res) {
    ++$count if $k eq $v;
}
is($count, count, 'Match results');

is($another_memd->get($keys[$#keys]), $keys[$#keys]);

foreach my $k (@keys) {
    $Memd::memd->delete($k);
}

$Memd::memd->nowait_push;

ok(not $another_memd->get($keys[$#keys]));
