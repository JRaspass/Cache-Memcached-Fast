package Memd;

use warnings;
use strict;


use Cache::Memcached::Fast;


our (@addr, $memd, $version_str, $version_num);


BEGIN {
    # Use differently spelled addressed to enable Ketama to hash names
    # differently.
    @addr = qw(localhost:11211 127.0.0.1:11211);

    $memd = Cache::Memcached::Fast->new({
        servers => [ { address => $addr[0], weight => 1.5 },
                     $addr[1] ],
        namespace => 'Cache::Memcached::Fast::',
        connect_timeout => 0.2,
        io_timeout => 0.5,
        close_on_error => 0,
        compress_threshold => 1000,
#        compress_algo => 'bzip2',
        max_failures => 3,
        failure_timeout => 2,
        ketama_points => 150,
    });

    # Test what server version we have.  server_versions() is
    # currently undocumented.  We know that all servers are the same,
    # so test only the first version.
    my $version = $memd->server_versions;
    if (@$version == @addr) {
        if ($version->[0] =~ /(\d+)\.(\d+)\.(\d+)/) {
            $version_str = $version->[0];
            $version_num = $1 * 10000 + $2 * 100 + $3;
        } else {
            $memd = 0;
        }
    } else {
        undef $memd;
    }
}


1;
