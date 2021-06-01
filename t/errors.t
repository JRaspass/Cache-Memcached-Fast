use Test2::V0 -target => 'Cache::Memcached::Fast';

# Create a server handle to a nonexistent service.
my $memd = CLASS->new( { servers => ['127.0.0.1:22122'] } );

is $memd->server_versions, {}, 'server_versions()';

is $memd->add( key => 'value' ), undef, 'add()';

is $memd->get('key'), undef, 'get()';

done_testing;
