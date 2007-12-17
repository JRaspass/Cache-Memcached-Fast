use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 12;
} else {
    plan skip_all => 'Not connected';
}


my %hash = ( a => 'a', b => 2, c => [ 'a', 1 ], d => { a => 1, b => [] } );

is_deeply(\%hash, \%hash, 'Check that is_deeply works');

my $key = 'serialize';

ok($Memd::memd->set($key, \%hash), 'Serialize and store');

my $res = $Memd::memd->get($key);
ok($res, 'Fetch');
is_deeply($res, \%hash, 'De-serialization');

$res = $Memd::memd->get_multi($key);
isa_ok($res, 'HASH');
ok(exists $res->{$key}, 'Fetch');
is_deeply($res->{$key}, \%hash, 'De-serialization');

SKIP: {
    skip "memcached 1.2.4 is required for prepend command", 4
      if $Memd::version_num < 10204;

    ok($Memd::memd->prepend($key, 'garbage'), 'Prepend garbage');
    $res = $Memd::memd->get($key);
    ok(! $res, 'Check that fetch fails');

    $res = $Memd::memd->get_multi($key);
    isa_ok($res, 'HASH');
    ok(! exists $res->{$key}, 'Check that fetch fails');
}

ok($Memd::memd->delete($key), 'Delete');
