use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

# add some values to the server
for ( 1 .. 3 ) {
    my ( $key, $val ) = ( "k$_", "v$_" );
    ok $Memd::memd->set( $key, $val ), "set('$key')";
    is $Memd::memd->get($key), $val, "get('$key')";
}

# test that the no values are set on the server if one or more
# values in a call to set_multi are not defined
# or if the argument to set_multi is not an array reference
for (
    [ [ 'k1', 'new v1' ],  [],                 [ 'k2', 'new k2' ] ],
    [ [],                  [ 'k1', 'new v1' ], [ 'k2', 'new k2' ] ],
    [ [ 'k1', 'new v1' ],  [ 'k2', 'new k2' ], [] ],
    [ [ undef, 'new v1' ], [ 'k2', 'new v2' ] ],
    [ [ 'k1', 'new v1' ],  [ 'k2', undef ] ],
    [ [ 'k2', 'new v1' ],  undef ],
    [ undef,               [ 'k2', 'new v2' ] ],
    )
{
    # no values should be updated after this set_multi
    eval { $Memd::memd->set_multi(@$_) };
    ok $@, 'Croaked on empty value passed to set_multi';

    is $Memd::memd->get("k$_"), "v$_", "get('k$_')" for 1 .. 3;
}

done_testing;
