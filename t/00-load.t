use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('Cache::Memcached::Fast');
}

diag(
    "Testing Cache::Memcached::Fast $Cache::Memcached::Fast::VERSION, Perl $], $^X"
);

done_testing;
