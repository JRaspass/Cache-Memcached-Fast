use Test2::V0 -target => 'Cache::Memcached::Fast';

subtest server => sub {
    for (
        [ []   => qr/^server should be \[\$addr, \$weight\]/ ],
        [ {}   => qr/^server should have \{ address => \$addr \}/ ],
        [ qr// => qr/^Not a hash or array reference/, 'regex server' ],
        )
    {
        my ( $server, $expected ) = @$_;

        like dies { CLASS->new( { servers => [$server] } ) }, $expected,
            lc ref $server;
    }
};

like dies { CLASS->new( { servers => [ [ 'localhost:11211', -1 ] ] } ) },
    qr/^\QServer weight should be positive/, 'negative weight';

done_testing;
