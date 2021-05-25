use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

my %params = %Memd::params;
$params{hash_namespace} = 1;

my $another_memd = new Cache::Memcached::Fast( \%params );

my $ns  = $another_memd->namespace('');
my $key = 'hash_namespace';
$another_memd->set( "$ns$key", 1 );
$another_memd->namespace($ns);
is( $another_memd->get($key), 1 );

$another_memd->delete($key);

done_testing;
