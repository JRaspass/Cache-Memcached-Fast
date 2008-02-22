use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 2;
} else {
    plan skip_all => 'Not connected';
}


$Memd::memd->set('namespace', 1);

my $ns = $Memd::memd->namespace();
$Memd::memd->set('namespace', 2);

my $new_ns = "$ns*new_ns*";
is($Memd::memd->namespace($new_ns), $ns);
$Memd::memd->set('namespace', 3);

is($Memd::memd->namespace($ns), $new_ns);
$Memd::memd->set('namespace', 4);

$Memd::memd->delete('namespace');
