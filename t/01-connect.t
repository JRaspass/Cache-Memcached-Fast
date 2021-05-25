use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

diag(     "Connected to "
        . scalar @Memd::addr
        . " memcached servers, lowest version $Memd::version_str" );
pass('connected');

my $server_versions = $Memd::memd->server_versions;
$Memd::memd->disconnect_all;
is_deeply( $Memd::memd->server_versions,
    $server_versions,
    'server_versions still works after disconnect_all' );

done_testing;
