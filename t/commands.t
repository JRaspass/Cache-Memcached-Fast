use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 68;
} else {
    plan skip_all => 'Not connected';
}


# count should be >= 4.
use constant count => 100;

my $key = 'commands';
my @keys = map { "commands-$_" } (1..count);

$Memd::memd->delete($key);
ok($Memd::memd->add($key, 'v1', undef), 'Add');
is($Memd::memd->get($key), 'v1', 'Fetch');
ok($Memd::memd->set($key, 'v2', undef), 'Set');
is($Memd::memd->get($key), 'v2', 'Fetch');
ok($Memd::memd->replace($key, 'v3'), 'Replace');
is($Memd::memd->get($key), 'v3', 'Fetch');

ok($Memd::memd->replace($key, 0), 'replace with numeric');
ok($Memd::memd->incr($key), 'Incr');
ok($Memd::memd->get($key) == 1, 'Fetch');
ok($Memd::memd->incr($key, 5), 'Incr');
ok((not $Memd::memd->incr('no-such-key', 5)), 'Incr no_such_key');
ok((defined $Memd::memd->incr('no-such-key', 5)),
   'Incr no_such_key returns defined value');
ok($Memd::memd->get($key) == 6, 'Fetch');
ok($Memd::memd->decr($key), 'Decr');
ok($Memd::memd->get($key) == 5, 'Fetch');
ok($Memd::memd->decr($key, 2), 'Decr');
ok($Memd::memd->get($key) == 3, 'Fetch');
ok($Memd::memd->decr($key, 100) == 0, 'Decr below zero');
ok($Memd::memd->decr($key, 100), 'Decr below zero returns true value');
ok($Memd::memd->get($key) == 0, 'Fetch');

ok($Memd::memd->get_multi(), 'get_multi() with empty list');

my $res = $Memd::memd->set_multi();
isa_ok($res, 'HASH');
is(scalar keys %$res, 0);
my @res = $Memd::memd->set_multi();
is(@res, 0);

@res = $Memd::memd->set_multi(map { [$_, $_] } @keys);
is(@res, count);
is((grep { not $_ } @res), 0);
$res = $Memd::memd->set_multi(map { [$_, $_] } @keys);
isa_ok($res, 'HASH');
is(keys %$res, count);
is((grep { not $_ } values %$res), 0);


my @extra_keys = @keys;
for (1..count) {
    splice(@extra_keys, int(rand(@extra_keys + 1)), 0, "no_such_key-$_");
}

$res = $Memd::memd->get_multi(@extra_keys);
isa_ok($res, 'HASH');
is(scalar keys %$res, scalar @keys, 'Number of entries in result');
my $count = 0;
foreach my $k (@keys) {
    ++$count if exists $res->{$k} and $res->{$k} eq $k;
}
is($count, count);


SKIP: {
    skip "memcached 1.2.4 is required for cas/gets/append/prepend commands", 27
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

    my $hash = $res;
    $res = $Memd::memd->cas_multi([$keys[0], @{$hash->{$keys[0]}}],
                                  ['no-such-key', 123, 'value', 10],
                                  [$keys[1], @{$hash->{$keys[1]}}, 1000]);
    isa_ok($res, 'HASH');
    is(scalar keys %$res, 3);
    ok($res->{$keys[0]});
    ok(defined $res->{'no-such-key'} and not $res->{'no-such-key'});
    ok($res->{$keys[1]});

    my @res = $Memd::memd->cas_multi([$keys[2], @{$hash->{$keys[2]}}],
                                     ['no-such-key', 123, 'value', 10],
                                     [$keys[3], @{$hash->{$keys[3]}}, 1000]);
    is(@res, 3);
    ok($res[0]);
    ok(not $res[1]);
    ok($res[2]);

    $res = $Memd::memd->cas_multi();
    isa_ok($res, 'HASH');
    is(scalar keys %$res, 0);
}

ok($Memd::memd->replace_multi(map { [$_,0] } @keys),'replace_multi to reset to numeric');
$res = $Memd::memd->incr_multi([$keys[0], 2], [$keys[1]], @keys[2..$#keys]);
ok(values %$res == @keys);
is((grep { $_ != 1 } values %$res), 1);
is($res->{$keys[0]}, 2);

$res = $Memd::memd->delete_multi($key);
ok($res->{$key});
$res = $Memd::memd->delete_multi([$keys[0]], $keys[1]);
ok($res->{$keys[0]} and $res->{$keys[1]});

ok($Memd::memd->remove($keys[2]));
@res = $Memd::memd->delete_multi(@keys);
is(@res, count);
is((grep { not $_ } @res), 3);
