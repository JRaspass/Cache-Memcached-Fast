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

# The exceptions don't have the correct caller so test with "like".
like dies { CLASS->new( { servers => [ [ 'localhost:11211', -1 ] ] } ) },
    qr/^\QServer weight should be positive/, 'negative weight';

# The warnings do have the correct caller so test with "is".
is warning { CLASS->new( { compress_algo => 1 } ) },
    'compress_algo has been removed in 0.08, use compress_methods instead'
    . ( ' at ' . __FILE__ . ' line ' . ( __LINE__ - 2 ) . ".\n" ),
    'compress_algo';

is warning { CLASS->new( { unknown_param => 1 } ) },
    'Unknown parameter: unknown_param'
    . ( ' at ' . __FILE__ . ' line ' . ( __LINE__ - 2 ) . ".\n" ),
    'unknown_param';

ok no_warnings { CLASS->new( { check_args => 'SKIP', unknown_param => 1 } ) },
    'check_args: skip';

done_testing;
