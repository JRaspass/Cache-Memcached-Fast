# -*- Encoding: koi8-r -*-
#
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


use encoding 'KOI8-R';

my $value = "Кириллица в KOI8-R";
$Memd::memd->set('encoding', $value);
my $value2 = $Memd::memd->get('encoding');
is($value2, $value);

$Memd::memd->delete('encoding');
