use lib 't';
use strict;
use warnings;

use Config;
use Memd;
use Test::More;

plan skip_all => 'Perl >= 5.7.2 is required'   unless $^V ge v5.7.2;
plan skip_all => 'ithreads are not configured' unless $Config{useithreads};
plan skip_all => 'Not connected'               unless $Memd::memd;

use constant COUNT => 5;

require threads;

my @threads = map threads->new( sub { $Memd::memd->set( (@_) x 2 ) }, $_ ),
    1 .. COUNT;

for ( 1 .. COUNT ) {
    $threads[ $_ - 1 ]->join;

    is $Memd::memd->get($_), $_, "get($_)";
    ok $Memd::memd->delete($_), "delete($_)";
}

done_testing;
