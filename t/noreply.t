use lib 't';

use Config;
use Memd;
use Test2::V0 -target => 'Cache::Memcached::Fast';

plan skip_all => 'Not connected' unless $Memd::memd;
plan skip_all => 'memcached >= 1.2.5 is required'
    unless $Memd::version_num >= 10205;

use constant count => 100;

my %params = %Memd::params;
for ( @{ $params{servers} } ) {
    $_->{noreply} = 1 if ref eq 'HASH';
}

my $another_memd = CLASS->new( \%params );

my @keys = map "noreply-$_", 1 .. count;
$another_memd->set_multi( map [ $_, $_ ], @keys );

is $another_memd->get_multi(@keys), { map { $_ => $_ } @keys };

$another_memd->delete_multi(@keys);

done_testing;
