use lib 't';

use Memd;
use Test2::V0 -target => 'Cache::Memcached::Fast';

my $memd = CLASS->new( { %Memd::params, hash_namespace => 1 } );

my $ns  = $memd->namespace('');
my $key = 'hash_namespace';

$memd->set( "$ns$key" => 1 );
$memd->namespace($ns);

is $memd->get($key), 1;

$memd->delete($key);

done_testing;
