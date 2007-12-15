use warnings;
use strict;

use Test::More tests => 1;

BEGIN {
	use_ok( 'Cache::Memcached::Fast' );
}

diag( "Testing Cache::Memcached::Fast $Cache::Memcached::Fast::VERSION, Perl $], $^X" );
