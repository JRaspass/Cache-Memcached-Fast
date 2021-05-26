use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

my $versions = $Memd::memd->server_versions;

$Memd::memd->disconnect_all;

is_deeply $Memd::memd->server_versions, $versions,
    'server_versions still works after disconnect_all';

done_testing;
