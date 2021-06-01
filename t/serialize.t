use lib 't';

use Memd;
use Test2::V0;

plan skip_all => 'Not connected' unless $Memd::memd;

my %hash = ( a => 'a', b => 2, c => [ 'a', 1 ], d => { a => 1, b => [] } );
my $key  = 'serialize';

ok $Memd::memd->set( $key => \%hash ), 'set()';

is $Memd::memd->get($key), \%hash, 'get()';

is $Memd::memd->get_multi($key), { $key => \%hash }, 'get_multi()';

subtest prepend => sub {
    plan skip_all => 'memcached 1.2.4 is required'
        if $Memd::version_num < 10204;

    ok $Memd::memd->prepend( $key => 'garbage' ), 'prepend()';

    is $Memd::memd->get($key), undef, 'get()';

    is $Memd::memd->get_multi($key), {}, 'get_multi()';
};

ok $Memd::memd->delete($key), 'delete()';

done_testing;
