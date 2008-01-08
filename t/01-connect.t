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
} else {
    plan skip_all => $Memd::error;
}
