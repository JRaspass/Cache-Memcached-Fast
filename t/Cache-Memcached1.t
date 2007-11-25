# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Cache-Memcached1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 20;
BEGIN { use_ok('Cache::Memcached1') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


use Cache::Memcached1;

my $memd = Cache::Memcached1->new({
    servers => ['localhost:11211'], #['localhost:11211', 'moonlight:50000'],
#    namespace => 'Cache::Memcached1::',
#    connect_timeout => 0.26,
#    select_timeout => 1.01,
    close_on_error => 0,
});

isa_ok($memd, 'Cache::Memcached1');

ok($memd->set("key1", "val1"));
ok($memd->_xs_set("key2", "val2", 2));
ok($memd->_xs_set("key3", "val3", 3, 10));
ok(not $memd->set("key4", "x" x 2_000_000));
ok($memd->set("key4", "x" x 1_000_000));

is($memd->get("no_such_key"), undef);
is($memd->get("key2"), "val2");

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

$res1 = $memd->get_multi("key_no_such_key", "key1", "key_no_such_key",
                         "key2", "key_no_such_key", "key_no_such_key",
                         "key3", "key_no_such_key", "key2", "key_no_such_key");
is(scalar keys %$res1, 3);
is($$res1{key1}, "val1");
is($$res1{key2}, "val2");
is($$res1{key3}, "val3");

undef $memd;
