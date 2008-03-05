use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 1;
} else {
    plan skip_all => 'Not connected';
}


my %params = %Memd::params;
$params{hash_namespace} = 1;

my $another_memd = new Cache::Memcached::Fast(\%params);

my $ns = $another_memd->namespace('');
my $key = 'hash_namespace';
$another_memd->set("$ns$key", 1);
$another_memd->namespace($ns);
is($another_memd->get($key), 1);

$another_memd->delete($key);
