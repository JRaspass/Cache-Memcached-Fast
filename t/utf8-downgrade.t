use lib 't';
use strict;
use utf8;
use warnings;

use Config;
use Memd;
use Test::More;

plan skip_all => 'Perl >= 5.8.0 is required' unless $^V ge v5.8.0;
plan skip_all => 'Not connected'             unless $Memd::memd;

my %params = %Memd::params;
delete $params{utf8};
my $memd_bytes = new Cache::Memcached::Fast( \%params );

my $str_bytes = "\x81";
my $str_utf8  = $str_bytes;
utf8::upgrade($str_utf8);
is( $str_bytes, $str_utf8 );

$memd_bytes->set( 'utf8-downgrade', $str_utf8 );
my $str = $memd_bytes->get('utf8-downgrade');
is( $str, $str_utf8 );

my $str2 = $Memd::memd->get('utf8-downgrade');
is( $str2, $str_utf8 );

eval { $memd_bytes->set( 'utf8-downgrade', 'Привет' ); };
like( $@, qr/Wide character in subroutine entry at/ );

$Memd::memd->delete('utf8-downgrade');

done_testing;
