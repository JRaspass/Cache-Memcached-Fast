use strict;
use warnings;

use Cache::Memcached::Fast;
use Test::More;

# Create a server handle to a nonexistent service.
my $memd = new Cache::Memcached::Fast( { servers => ['127.0.0.1:22122'] } );

is_deeply $memd->server_versions, {}, 'server_versions()';

is $memd->add( key => 'value' ), undef, 'add()';

is $memd->get('key'), undef, 'get()';

done_testing;
