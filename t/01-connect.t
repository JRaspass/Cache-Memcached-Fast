use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    diag("Connected to " . scalar @Memd::addr
         . " memcached servers, lowest version $Memd::version_str");
    plan tests => 2;
    pass('connected');

    my $server_versions = $Memd::memd->server_versions;
    $Memd::memd->disconnect_all;
    is_deeply($Memd::memd->server_versions, $server_versions, "server_versions still works after disconnect_all");
} else {
    plan skip_all => $Memd::error;
}
