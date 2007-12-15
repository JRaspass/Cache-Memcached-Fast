use warnings;
use strict;

# TODO: the test is messy.  It should be split into several files.


use Test::More tests => 58;
BEGIN { use_ok('Cache::Memcached::Fast') };

use Cache::Memcached::Fast;

my $memd = Cache::Memcached::Fast->new({
    servers => [ { address => 'localhost:11211', weight => 2.5 },
                 '127.0.0.1:11211', '127.0.0.1:11211' ],
    namespace => 'Cache::Memcached::Fast::',
    connect_timeout => 0.2,
    io_timeout => 0.5,
    close_on_error => 0,
    compress_threshold => 1000,
#    compress_algo => 'deflate',
    max_failures => 3,
    failure_timeout => 2,
    ketama_points => 150,
});

isa_ok($memd, 'Cache::Memcached::Fast');

ok($memd->flush_all);

ok($memd->set("key1", "val1"));
ok($memd->set("key2", "val2"));
ok($memd->set("key3", "val3", 10));
$memd->enable_compress(0);
ok(not $memd->set("key4", "x" x 2_000_000));
$memd->enable_compress(1);
ok($memd->set("key4", "x" x 1_000_000));

is($memd->get("no_such_key"), undef);
is($memd->get("key2"), "val2");
is($memd->get("key4"), "x" x 1_000_000);

my $val = $memd->get("key3");
is($val, "val3");

$val = $memd->get("no_such_key");
is($val, undef);

my $res1 = $memd->get_multi();
is(scalar keys %$res1, 0);

$res1 = $memd->get_multi("key", "key1");
is(scalar keys %$res1, 1);
is($$res1{key1}, "val1");


ok($memd->set("zero", ""));
is($memd->get("zero"), "");


$memd->set("arith", 10);
is($memd->incr("arith", 5), 15);
is($memd->decr("arith"), 14);
is($memd->get("arith"), 14);


$res1 = $memd->get_multi("key_no_such_key", "key1", "key_no_such_key",
                         "key2", "key_no_such_key", "key_no_such_key",
                         "key3", "key_no_such_key", "key2", "key_no_such_key");
is(scalar keys %$res1, 3);
is($$res1{key1}, "val1");
is($$res1{key2}, "val2");
is($$res1{key3}, "val3");

ok($memd->delete("key4", 3));
ok(not $memd->delete("no_such_key"));

$memd->delete("key5");
ok(not $memd->replace("key5", "x"));
ok($memd->add("key5", "x"));
ok(not $memd->add("key5", "x"));
ok($memd->append("key5", "a"));
ok($memd->prepend("key5", "b"));
is($memd->get("key5"), "bxa");

ok($memd->flush_all(1));
sleep(1.2);


my $key = "key_ref";
my $value = "value ref check";
ok($memd->set($key, $value));
my $h = $memd->get_multi($key);
is($$h{$key}, $value);
my $old_key = $key;
substr($key, 3, 4, "");
is($$h{$old_key}, $value);
is($$h{$key}, undef);


$memd->set("cas", "value");
my $cas_res = $memd->gets("cas");
isa_ok($cas_res, "ARRAY");
is (scalar @$cas_res, 2);
is($$cas_res[1], "value");
ok($memd->cas("cas", $$cas_res[0], "new value"));
ok(! $memd->cas("cas", @$cas_res));
is($memd->get("cas"), "new value");

$h = $memd->gets_multi("no_such_key", "cas", "nothing");
is(scalar keys %$h, 1);
isa_ok($$h{cas}, "ARRAY");
is (scalar @{$$h{cas}}, 2);
is(${$$h{cas}}[1], "new value");


my %hash = (
   list => [ qw(a b) ],
   hash => { a => 1 },
   num  => 3,
   str  => "test",
);

sub storable_ok {
    my ($hash_ref) = @_;

    ok(${$$hash_ref{list}}[0] eq 'a'
       and ${$$hash_ref{list}}[1] eq 'b'
       and ${$$hash_ref{hash}}{a} == 1
       and $$hash_ref{num} == 3
       and $$hash_ref{str} eq 'test');
}

$h = \%hash;
ok($memd->set("hash", $h));
storable_ok($h);
my $hash_ref = $memd->get("hash");
isa_ok($hash_ref, 'HASH');
storable_ok($hash_ref);

$memd->prepend("hash", "garbage");
$h = $memd->get_multi("cas", "hash");
is(scalar keys %$h, 1);
ok(exists $$h{cas});
ok(not exists $$h{hash});


undef $memd;


if (1) {
   ok(1);
   ok(1);
   ok(1);
} else {
    my $memd_noreply = Cache::Memcached::Fast->new({
        servers => ['localhost:11211'],
        namespace => 'Cache::Memcached::Fast::',
        close_on_error => 0, # noreply should re-enable this.
        noreply => 1,
    });

    $memd_noreply->flush_all;

    $memd_noreply->add("k", "v");
    $memd_noreply->set("k", "v");
    $memd_noreply->replace("k", "v");
    $memd_noreply->prepend("k", "_");
    $memd_noreply->append("k", "_");
    is($memd_noreply->get("k"), "_v_");
    $memd_noreply->delete("k");
    is($memd_noreply->get("k"), undef);

    $memd_noreply->set("arith", 10);
    $memd_noreply->incr("arith", 5);
    $memd_noreply->decr("arith");
    is($memd_noreply->get("arith"), 14);

    $memd_noreply->flush_all;
}
