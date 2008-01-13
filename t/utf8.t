use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    if ($Memd::params{utf8}) {
        plan tests => 1;
    } else {
        plan skip_all => "'utf8' is disabled";
    }
} else {
    plan skip_all => 'Not connected';
}


use utf8;

my $value = "Кириллица в UTF-8";
$Memd::memd->set('utf8', $value);
my $value2 = $Memd::memd->get('utf8');
is($value2, $value);

$Memd::memd->delete('utf8');
