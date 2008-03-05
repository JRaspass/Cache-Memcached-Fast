use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    if ($Memd::version_num >= 10205) {
        plan tests => 3;
    } else {
        plan skip_all => 'memcached 1.2.5 is required for noreply mode';
    }
} else {
    plan skip_all => 'Not connected';
}


use constant count => 100;

my %params = %Memd::params;
foreach my $h (@{$params{servers}}) {
    $h->{noreply} = 1 if ref($h) eq 'HASH';
}

my $another_memd = new Cache::Memcached::Fast(\%params);

my @keys = map { "noreply-$_" } (1..count);

$another_memd->set_multi(map { [$_, $_] } @keys);
my $res = $another_memd->get_multi(@keys);
isa_ok($res, 'HASH');
is(scalar keys %$res, scalar @keys, 'Number of entries in result');
my $count = 0;
foreach my $k (@keys) {
    ++$count if exists $res->{$k} and $res->{$k} eq $k;
}
is($count, count);

$another_memd->delete_multi(@keys);
