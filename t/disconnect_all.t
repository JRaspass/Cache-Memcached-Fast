use lib 't';

use Memd;
use Test2::V0;

my $versions = $memd->server_versions;

$memd->disconnect_all;

is $memd->server_versions, $versions,
    'server_versions still works after disconnect_all';

done_testing;
