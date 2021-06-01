use lib 't';

use Memd;
use Test2::V0;

my %hash = ( a => 'a', b => 2, c => [ 'a', 1 ], d => { a => 1, b => [] } );
my $key  = 'serialize';

ok $memd->set( $key => \%hash ), 'set()';

is $memd->get($key), \%hash, 'get()';

is $memd->get_multi($key), { $key => \%hash }, 'get_multi()';

subtest prepend => sub {
    plan skip_all => 'memcached 1.2.4 is required' if $memd_version < v1.2.4;

    ok $memd->prepend( $key => 'garbage' ), 'prepend()';

    is $memd->get($key), undef, 'get()';

    is $memd->get_multi($key), {}, 'get_multi()';
};

ok $memd->delete($key), 'delete()';

done_testing;
