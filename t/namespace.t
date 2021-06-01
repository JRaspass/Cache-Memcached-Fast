use lib 't';

use Memd;
use Test2::V0;

$memd->set( namespace => 1 );

my $ns = $memd->namespace;
$memd->set( namespace => 2 );

my $new_ns = "$ns*new_ns*";
is $memd->namespace($new_ns), $ns;
$memd->set( namespace => 3 );

is $memd->namespace($ns), $new_ns;
$memd->set( namespace => 4 );

$memd->delete('namespace');

done_testing;
