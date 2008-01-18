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
        $version_num = 2 ** 31;
        while (my ($s, $v) = each %$version) {
            if ($v =~ /(\d+)\.(\d+)\.(\d+)/) {
                my $n = $1 * 10000 + $2 * 100 + $3;
                if ($n < $version_num) {
                    $version_str = $v;
                    $version_num = $n;
                }
            } else {
                $error = "Can't parse version of $s: $v";
                undef $memd;
                last;
            }
        }
    } else {
        my @servers = map {
            if (ref($_) eq 'HASH') {
                $_->{address};
            } elsif (ref($_) eq 'ARRAY') {
                $_->[0];
            } else {
                $_;
            }
        } @addr;

        $error = "No server is running at "
            . join(', ', grep { not exists $version->{$_} } @servers);
        undef $memd;
    }
}


1;
