use lib 't';
use strict;
use utf8;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected'      unless $Memd::memd;
plan skip_all => '"utf8" is disabled' unless $Memd::params{utf8};

my $value = "Кириллица в UTF-8";
$Memd::memd->set( 'utf8', $value );
my $value2 = $Memd::memd->get('utf8');
is( $value2, $value );

$Memd::memd->delete('utf8');

done_testing;
