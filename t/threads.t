use lib 't';

use Memd;
use Test2::IPC;
use Test2::Require::Threads;
use Test2::V0;

plan skip_all => 'Not connected' unless $Memd::memd;

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
