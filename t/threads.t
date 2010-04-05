use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;


if ($^V lt v5.7.2) {
   plan skip_all => 'Perl >= 5.7.2 is required';
}

use Config;
unless ($Config{useithreads}) {
   plan skip_all => 'ithreads are not configured';
}

use constant COUNT => 5;

if ($Memd::memd) {
    plan tests => COUNT * 2;
} else {
    plan skip_all => 'Not connected';
}


require threads;

sub job {
    my ($num) = @_;

    $Memd::memd->set($num, $num);
}

my @threads;
for my $num (1..COUNT) {
    push @threads, threads->new(\&job, $num);
}

for my $num (1..COUNT) {
    $threads[$num - 1]->join;

    my $n = $Memd::memd->get($num);
    is($n, $num);
    ok($Memd::memd->delete($num));
}
