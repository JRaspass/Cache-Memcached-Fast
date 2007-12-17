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

isa_ok($Memd::memd, 'Cache::Memcached::Fast');
