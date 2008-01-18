use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    diag("Connected to " . scalar @Memd::addr
         . " memcached servers, lowest version $Memd::version_str");
    plan tests => 1;
    pass('connected');
} else {
    plan skip_all => $Memd::error;
}
