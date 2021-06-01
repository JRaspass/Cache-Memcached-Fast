use lib 't';

use Memd;
use Test2::V0;

plan skip_all => 'Not connected' unless $Memd::memd;

$Memd::memd->set( namespace => 1 );

my $ns = $Memd::memd->namespace;
$Memd::memd->set( namespace => 2 );

my $new_ns = "$ns*new_ns*";
is $Memd::memd->namespace($new_ns), $ns;
$Memd::memd->set( namespace => 3 );

is $Memd::memd->namespace($ns), $new_ns;
$Memd::memd->set( namespace => 4 );

$Memd::memd->delete('namespace');

done_testing;
