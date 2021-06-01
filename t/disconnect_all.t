use lib 't';

use Memd;
use Test2::V0;

plan skip_all => 'Not connected' unless $Memd::memd;

my $versions = $Memd::memd->server_versions;

$Memd::memd->disconnect_all;

is $Memd::memd->server_versions, $versions,
    'server_versions still works after disconnect_all';

done_testing;
