#!/usr/bin/perl

use Modern::Perl;
use Test::More;

use Cache::Memcached::Fast;

## IN THIS FILE ##
#
# Trigger errors when the memcached server is not available.
# -When actions are performed correctly, True is returned
# -When actions failed, but not errored, False is returned
# -When actions fail due to errors, undef is returned


#Create a bad server handle
my $memd = new Cache::Memcached::Fast({
    servers   => [ '127.0.0.1:22122' ], #This must be a nonexistent service
    namespace => 'bad:',
    utf8      => 1,
});

# Get server versions.



subtest "Memcached is unreachable, so operations return undef", sub {

    my $rv;

    $rv = $memd->server_versions;
    is(ref($rv), 'HASH', "server_versions() still returns a HASH");
    my @versionKeys = keys %$rv;
    ok(not(@versionKeys), "No versions found");

    $rv = $memd->add('key', 'text');
    ok(not(defined($rv)), "add()");

    $rv = $memd->get('key');
    ok(not(defined($rv)), "get()");

};

done_testing();
