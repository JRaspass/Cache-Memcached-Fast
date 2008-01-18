package Memd;

use warnings;
use strict;


use Cache::Memcached::Fast;
use Storable;

our (@addr, %params, $memd, $version_str, $version_num, $error);


BEGIN {
    # Use differently spelled host addresses to enable Ketama to hash
    # names differently.
    @addr = (
        { address => 'localhost:11211', weight => 1.5 },
        { address => '127.0.0.1:11211' },
        '127.0.0.2:11211',
        [ '127.0.0.3:11211', 2 ]
    );

    %params = (
        servers => [ @addr ],
        namespace => "Cache::Memcached::Fast/$$/",
        connect_timeout => 5,
        io_timeout => 5,
        close_on_error => 0,
        compress_threshold => 1000,
#        compress_algo => 'bzip2',
        max_failures => 3,
        failure_timeout => 2,
        ketama_points => 150,
        nowait => 1,
        serialize_methods => [ \&Storable::freeze, \&Storable::thaw ],
        utf8 => ($^V >= 5.008001 ? 1 : 0),
    );

    $memd = Cache::Memcached::Fast->new(\%params);

    # Test what server version we have.  server_versions() is
    # currently undocumented.  We know that all servers are the same,
    # so test only the first version.
    my $version = $memd->server_versions;
    if (keys %$version == @addr) {
        $version = (values %$version)[0];
        if ($version =~ /(\d+)\.(\d+)\.(\d+)/) {
            $version_str = $version;
            $version_num = $1 * 10000 + $2 * 100 + $3;
        } else {
            $error = "Can't parse server version $version";
            undef $memd;
        }
    } else {
        $error = "No server is running at "
            . join(', ', grep { not exists $version->{$_} }
                              @{$memd->{servers}});
        undef $memd;
    }
}


1;
