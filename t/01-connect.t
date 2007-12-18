use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    diag("Connected to memcached $Memd::version_str");
    plan tests => 1;
    pass('connected');
} elsif (defined $Memd::memd) {
    plan skip_all => "Can't parse server version $Memd::version_str";
} else {
    plan skip_all => "No server is running at (one of) @Memd::addr";
}
