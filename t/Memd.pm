package Memd;

use strict;
use version;
use warnings;

use Cache::Memcached::Fast;
use List::Util 'min';
use Test2::API 'context';

# Use differently spelt hosts to enable Ketama to hash names differently.
our %params = (
    close_on_error     => 0,
    compress_threshold => 1000,
    connect_timeout    => 5,
    failure_timeout    => 2,
    io_timeout         => 5,
    ketama_points      => 150,
    max_failures       => 3,
    namespace          => "Cache::Memcached::Fast/$$/",
    nowait             => 1,
    utf8               => 1,
    servers            => [
        { address => 'localhost:11211', weight => 1.5 },
        '127.0.0.1:11211',
    ],
);

# 5.8 doesn't ship with Compress::Zlib, avoid lots of warnings.
delete $params{compress_threshold} unless eval { require Compress::Zlib };

sub import {
    *main::memd = \Cache::Memcached::Fast->new( \%params );

    # Find out what server versions we have.
    if ( my @versions = values %{ $main::memd->server_versions } ) {
        *main::memd_version = \min map version->parse($_), @versions;
    }
    else {
        my $ctx = context;
        $ctx->plan( 0, SKIP => 'Not connected' );
        $ctx->release;
    }
}

1;
