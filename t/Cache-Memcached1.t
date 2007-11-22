# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Cache-Memcached1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok('Cache::Memcached1') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


use Cache::Memcached1;

my $memd = Cache::Memcached1->new({
    servers => ['localhost:11211'], #['localhost:11211', 'moonlight:50000'],
    namespace => 'Cache::Memcached1::',
    connect_timeout => 0.26,
    select_timeout => 1.01,
});

isa_ok($memd, 'Cache::Memcached1');

ok($memd->set("key1", "val1"));
ok($memd->set("key2", "val2", 1));
ok($memd->set("key3", "val3", 1, 10));

undef $memd;
