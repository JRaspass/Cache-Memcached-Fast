use lib 't';
use strict;
use warnings;

use Config;
use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;
plan skip_all => 'memcached >= 1.2.5 is required'
    unless $Memd::version_num >= 10205;

use constant count => 100;

my %params = %Memd::params;
foreach my $h ( @{ $params{servers} } ) {
    $h->{noreply} = 1 if ref($h) eq 'HASH';
}

my $another_memd = new Cache::Memcached::Fast( \%params );

my @keys = map {"noreply-$_"} ( 1 .. count );

$another_memd->set_multi( map { [ $_, $_ ] } @keys );
my $res = $another_memd->get_multi(@keys);
isa_ok( $res, 'HASH' );
is( scalar keys %$res, scalar @keys, 'Number of entries in result' );
my $count = 0;
foreach my $k (@keys) {
    ++$count if exists $res->{$k} and $res->{$k} eq $k;
}
is( $count, count );

$another_memd->delete_multi(@keys);

done_testing;
