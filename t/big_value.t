use lib 't';

use Memd;
use Test2::V0 -target => 'Cache::Memcached::Fast';

use constant THRESHOLD => 1024 * 1024 - 1024;

my $key         = 'big_value';
my $value       = 'x' x THRESHOLD;
my $small_value = 'x' x ( THRESHOLD - 2048 );
my $big_value   = 'x' x ( THRESHOLD + 2048 );

my %smaller_params = %Memd::params;
$smaller_params{max_size} = THRESHOLD - 2048;
$smaller_params{namespace} .= 'smaller/';
my $smaller_memd = CLASS->new( \%smaller_params );

my %bigger_params = %Memd::params;
$bigger_params{max_size} = THRESHOLD + 2048;
$bigger_params{namespace} .= 'bigger/';
my $bigger_memd = CLASS->new( \%bigger_params );

$memd->enable_compress(0);
$smaller_memd->enable_compress(0);
$bigger_memd->enable_compress(0);

ok $memd->set( $key, $value ), 'Store value uncompressed';
is $memd->get($key), $value, 'Fetch';
ok !$smaller_memd->set( $key, $value ),
    'Values equal to or greater than THRESHOLD should be rejected by module';
ok !$bigger_memd->set( $key, $big_value ),
    'Values greater than 1MB should be rejected by server';

my @res = $smaller_memd->set_multi(
    [ "$key-1", $small_value ],
    [ "$key-2", $big_value ],
    [ "$key-3", $small_value ]
);
is \@res, [1, undef, 1];
ok $smaller_memd->delete_multi( "$key-1", "$key-3" );

SKIP: {
    my $warnings = warnings {
        $memd->enable_compress(1);
        $smaller_memd->enable_compress(1);
        $bigger_memd->enable_compress(1);
    };

    if ( my ($warning) = @$warnings ) {
        chomp $warning;
        if ( $warning =~ /^Compression module was not found/ ) {
            skip $warning, 6;
        }
        else {
            warn "$warning\n";
        }
    }

    ok $smaller_memd->set( $key, $value ),    'Store compressed value';
    ok $bigger_memd->set( $key, $big_value ), 'Store compressed value';

    is $smaller_memd->get($key), $value,    'Fetch and uncompress';
    is $bigger_memd->get($key), $big_value, 'Fetch and uncompress';

    ok $smaller_memd->delete($key), 'Delete';
    ok $bigger_memd->delete($key),  'Delete';
}

ok $memd->delete($key), 'Delete';

done_testing;
