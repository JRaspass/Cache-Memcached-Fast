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

sub job {
    my ($num) = @_;

    $Memd::memd->set( $num, $num );
}

my @threads;
for my $num ( 1 .. COUNT ) {
    push @threads, threads->new( \&job, $num );
}

for my $num ( 1 .. COUNT ) {
    $threads[ $num - 1 ]->join;

    my $n = $Memd::memd->get($num);
    is( $n, $num );
    ok( $Memd::memd->delete($num) );
}

done_testing;
