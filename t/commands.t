use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

use constant count => 100;

if ($Memd::memd) {
    plan tests => 39;
} else {
    plan skip_all => 'Not connected';
}

my $key = 'commands';
my @keys = map { "commands-$_" } (1..count);

ok(! $Memd::memd->get($key), "There is no key '$key' in the cache yet");
ok($Memd::memd->add($key, 'v1'), 'Add');
is($Memd::memd->get($key), 'v1', 'Fetch');
ok($Memd::memd->set($key, 'v2'), 'Set');
is($Memd::memd->get($key), 'v2', 'Fetch');
ok($Memd::memd->replace($key, 'v3'), 'Replace');
is($Memd::memd->get($key), 'v3', 'Fetch');

ok($Memd::memd->incr($key), 'Incr');
ok($Memd::memd->get($key) == 1, 'Fetch');
ok($Memd::memd->incr($key, 5), 'Incr');
ok($Memd::memd->get($key) == 6, 'Fetch');
ok($Memd::memd->decr($key), 'Decr');
ok($Memd::memd->get($key) == 5, 'Fetch');
ok($Memd::memd->decr($key, 2), 'Decr');
ok($Memd::memd->get($key) == 3, 'Fetch');
ok($Memd::memd->decr($key, 100) == 0, 'Decr below zero');
ok($Memd::memd->get($key) == 0, 'Fetch');


my $count = 0;
foreach my $k (@keys) {
    ++$count if $Memd::memd->set($k, $k);
}
is($count, count);

my @extra_keys = @keys;
for (1..count) {
    splice(@extra_keys, int(rand($#extra_keys)), 0, "no_such_key-$_");
}

my $res = $Memd::memd->get_multi(@extra_keys);
isa_ok($res, 'HASH');
is(scalar keys %$res, scalar @keys, 'Number of entries in result');
$count = 0;
foreach my $k (@keys) {
    ++$count if $res->{$k} eq $k;
}
is($count, count);


SKIP: {
    skip "memcached 1.2.4 is required for cas/gets/append/prepend commands", 16
      if $Memd::version_num < 10204;

    ok($Memd::memd->set($key, 'value'), 'Store');
    ok($Memd::memd->append($key, '-append'), 'Append');
    is($Memd::memd->get($key), 'value-append', 'Fetch');
    ok($Memd::memd->prepend($key, 'prepend-'), 'Prepend');
    is($Memd::memd->get($key), 'prepend-value-append', 'Fetch');

    $res = $Memd::memd->gets($key);
    ok($res, 'Gets');
    isa_ok($res, 'ARRAY');
    is(scalar @$res, 2, 'Gets result is an array of two elements');
    ok($res->[0], 'CAS opaque defined');
    is($res->[1], 'prepend-value-append', 'Match value');
    $res->[1] = 'new value';
    ok($Memd::memd->cas($key, @$res), 'First update success');
    ok(! $Memd::memd->cas($key, @$res), 'Second update failure');
    is($Memd::memd->get($key), 'new value', 'Fetch');

    $res = $Memd::memd->gets_multi(@extra_keys);
    isa_ok($res, 'HASH');
    is(scalar keys %$res, scalar @keys, 'Number of entries in result');
    $count = 0;
    foreach my $k (@keys) {
        ++$count if ref($res->{$k}) eq 'ARRAY';
        ++$count if @{$res->{$k}} == 2;
        ++$count if defined $res->{$k}->[0];
        ++$count if $res->{$k}->[1] eq $k;
    }
    is($count, count * 4);
}


ok($Memd::memd->delete($key), 'Delete');
$count = 0;
foreach my $k (@keys) {
    ++$count if $Memd::memd->delete($k);
}
is($count, count);
