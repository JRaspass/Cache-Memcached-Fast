use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 1;
} else {
    plan skip_all => 'Not connected';
}


my $data = bless {}, 'Test';
my $res = $Memd::memd->set('test', $data, 5);
$res = $Memd::memd->get('test');
is_deeply($res, $data);
