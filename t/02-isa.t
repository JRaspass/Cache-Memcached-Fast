use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

isa_ok( $Memd::memd, 'Cache::Memcached::Fast' );

done_testing;
