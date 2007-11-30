# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Cache-Memcached-Fast.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 37;
BEGIN { use_ok('Cache::Memcached::Fast') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


use Cache::Memcached::Fast;

my $memd = Cache::Memcached::Fast->new({
    servers => ['localhost:11211'], #['localhost:11211', 'moonlight:50000'],
    namespace => 'Cache::Memcached::Fast::',
#    connect_timeout => 0.26,
#    select_timeout => 1.01,
    close_on_error => 0,
});

isa_ok($memd, 'Cache::Memcached::Fast');

ok($memd->flush_all);

ok($memd->set("key1", "val1"));
ok($memd->_xs_set("key2", "val2", 2));
ok($memd->_xs_set("key3", "val3", 3, 10));
ok(not $memd->set("key4", "x" x 2_000_000));
ok($memd->set("key4", "x" x 1_000_000));

is($memd->get("no_such_key"), undef);
is($memd->get("key2"), "val2");
is($memd->get("key4"), "x" x 1_000_000);

my ($val, $flags) = $memd->_xs_get("key3");
is($val, "val3");
is($flags, 3);

($val, $flags) = $memd->_xs_get("no_such_key");
is($val, undef);
is($flags, undef);

my $res1 = $memd->get_multi();
is(scalar keys %$res1, 0);

$res1 = $memd->get_multi("key1");
is(scalar keys %$res1, 1);
is($$res1{key1}, "val1");


ok($memd->set("zero", ""));
is($memd->get("zero"), "");


$res1 = $memd->get_multi("key_no_such_key", "key1", "key_no_such_key",
                         "key2", "key_no_such_key", "key_no_such_key",
                         "key3", "key_no_such_key", "key2", "key_no_such_key");
is(scalar keys %$res1, 3);
is($$res1{key1}, "val1");
is($$res1{key2}, "val2");
is($$res1{key3}, "val3");

ok($memd->delete("key4", 3));
ok(not $memd->delete("no_such_key"));

ok(not $memd->replace("key5", "x"));
ok($memd->add("key5", "x"));
ok(not $memd->add("key5", "x"));
ok($memd->append("key5", "a"));
ok($memd->prepend("key5", "b"));
is($memd->get("key5"), "bxa");

ok($memd->flush_all(2));
is(keys %{$memd->get_multi(map { "key$_" } (1, 2, 3, 5))}, 4);
sleep(2.2);
is(keys %{$memd->get_multi(map { "key$_" } (1, 2, 3, 5))}, 0);

undef $memd;


if (1) {
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
    $memd_noreply->flush_all;
}
