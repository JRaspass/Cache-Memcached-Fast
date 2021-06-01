use lib 't';

use Memd;
use Test2::IPC;
use Test2::Require::Threads;
use Test2::V0;

use constant COUNT => 5;

require threads;

my @threads = map threads->new( sub { $memd->set( (@_) x 2 ) }, $_ ),
    1 .. COUNT;

for ( 1 .. COUNT ) {
    $threads[ $_ - 1 ]->join;

    is $memd->get($_), $_, "get($_)";
    ok $memd->delete($_), "delete($_)";
}

done_testing;
