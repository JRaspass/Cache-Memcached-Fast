use strict;
use warnings;

use Cache::Memcached::Fast;
use Test::More;

subtest server => sub {
    for (
        [ []   => qr/^server should be \[\$addr, \$weight\]/ ],
        [ {}   => qr/^server should have \{ address => \$addr \}/ ],
        [ qr// => qr/^Not a hash or array reference/, 'regex server' ],
        )
    {
        my ( $server, $expected ) = @$_;

        eval { Cache::Memcached::Fast->new( { servers => [$server] } ) };
        like $@, $expected, lc ref $server;
    }
};

eval {
    Cache::Memcached::Fast->new(
        { servers => [ { address => 'localhost:11211', weight => -1 } ] } );
};
like $@, qr/^\QServer weight should be positive/, 'negative weight';

done_testing;
