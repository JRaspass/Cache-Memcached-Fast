use lib 't';

use Memd;
use Test2::V0 -target => 'Cache::Memcached::Fast';

plan skip_all => 'memcached 1.2.5 is required' if $memd_version < v1.2.5;

use constant count => 100;

my %params = %Memd::params;
for ( @{ $params{servers} } ) {
    $_->{noreply} = 1 if ref eq 'HASH';
}

my $memd = CLASS->new( \%params );

my @keys = map "noreply-$_", 1 .. count;
$memd->set_multi( map [ $_, $_ ], @keys );

is $memd->get_multi(@keys), { map { $_ => $_ } @keys };

$memd->delete_multi(@keys);

done_testing;
