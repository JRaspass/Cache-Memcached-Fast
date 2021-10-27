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
my %args  = ( compress_algo => 1, foo => 1, bar => 1 );
my $where = 'at ' . __FILE__ . ' line ' . ( __LINE__ + 1 ) . ".\n";
is warnings { CLASS->new( \%args ) } => [
    "compress_algo was removed in 0.08, use compress_methods $where",
    "Unknown arguments: bar, foo $where",
] => 'unknown params';

ok no_warnings { CLASS->new( { %args, check_args => 'SKIP' } ) },
    'check_args: skip';

done_testing;
