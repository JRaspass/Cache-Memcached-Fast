use lib 't';

use Memd;
use Test2::V0;

# count should be >= 4.
use constant count => 100;

my $key  = 'commands';
my @keys = map "commands-$_", 1 .. count;

ok $memd->add( $key => 'foo' ), 'add';

# Delete/remove return whether they deleted anything.
ok $memd->delete($key), 'delete';
ok !$memd->remove($key), 'remove';

ok $memd->add( $key, 'v1', undef ), 'Add';
is $memd->get($key), 'v1', 'Fetch';

ok $memd->set( $key, 'v2', undef ), 'Set';
is $memd->get($key), 'v2', 'Fetch';

ok $memd->replace( $key, 'v3' ), 'Replace';
is $memd->get($key), 'v3', 'Fetch';

ok $memd->replace( $key, 0 ), 'replace with numeric';
ok $memd->incr($key), 'Incr';
ok $memd->get($key) == 1, 'Fetch';
ok $memd->incr( $key, 5 ), 'Incr';

ok !$memd->incr( 'no-such-key', 5 ), 'Incr no_such_key';
ok defined $memd->incr( 'no-such-key', 5 ),
    'Incr no_such_key returns defined value';

ok $memd->get($key) == 6, 'Fetch';
ok $memd->decr($key), 'Decr';
ok $memd->get($key) == 5, 'Fetch';
ok $memd->decr( $key, 2 ), 'Decr';
ok $memd->get($key) == 3, 'Fetch';
ok $memd->decr( $key, 100 ) == 0, 'Decr below zero';
ok $memd->decr( $key, 100 ), 'Decr below zero returns true value';
ok $memd->get($key) == 0, 'Fetch';

ok $memd->get_multi, 'get_multi() with empty list';

is { $memd->set_multi }, {}, 'list set_multi()';
is $memd->set_multi,     {}, 'scalar set_multi()';

my @res = $memd->set_multi( map { [ $_, $_ ] } @keys );
is @res, count;
is grep( { not $_ } @res ), 0;
my $res = $memd->set_multi( map { [ $_, $_ ] } @keys );
is keys %$res, count;
is grep( { not $_ } values %$res ), 0;

my @extra_keys = @keys;
splice @extra_keys, rand( @extra_keys + 1 ), 0, "no_such_key-$_"
    for 1 .. count;

is $memd->get_multi(@extra_keys), { map { $_ => $_ } @keys };

subtest 'cas/gets/append/prepend' => sub {
    plan skip_all => 'memcached 1.2.4 is required' if $memd_version < v1.2.4;

    ok $memd->set( $key, 'value' ),      'Store';
    ok $memd->append( $key, '-append' ), 'Append';
    is $memd->get($key), 'value-append', 'Fetch';
    ok $memd->prepend( $key, 'prepend-' ), 'Prepend';
    is $memd->get($key), 'prepend-value-append', 'Fetch';

    $res = $memd->gets($key);
    ok $res, 'Gets';
    is @$res, 2, 'Gets result is an array of two elements';
    ok $res->[0], 'CAS opaque defined';
    is $res->[1], 'prepend-value-append', 'Match value';
    $res->[1] = 'new value';
    ok $memd->cas( $key,  @$res ), 'First update success';
    ok !$memd->cas( $key, @$res ), 'Second update failure';
    is $memd->get($key), 'new value', 'Fetch';

    $res = $memd->gets_multi(@extra_keys);
    is keys %$res, @keys, 'Number of entries in result';
    my $count = 0;
    for my $k (@keys) {
        ++$count if ref( $res->{$k} ) eq 'ARRAY';
        ++$count if @{ $res->{$k} } == 2;
        ++$count if defined $res->{$k}->[0];
        ++$count if $res->{$k}->[1] eq $k;
    }
    is $count, count * 4;

    my $hash = $res;
    $res = $memd->cas_multi(
        [ $keys[0],      @{ $hash->{ $keys[0] } } ],
        [ 'no-such-key', 123, 'value', 10 ],
        [ $keys[1],      @{ $hash->{ $keys[1] } }, 1000 ]
    );
    is keys %$res, 3;
    ok $res->{ $keys[0] };
    ok defined $res->{'no-such-key'} && !$res->{'no-such-key'};
    ok $res->{ $keys[1] };

    my @res = $memd->cas_multi(
        [ $keys[2],      @{ $hash->{ $keys[2] } } ],
        [ 'no-such-key', 123, 'value', 10 ],
        [ $keys[3],      @{ $hash->{ $keys[3] } }, 1000 ]
    );
    is @res, 3;
    ok $res[0];
    ok !$res[1];
    ok $res[2];

    is $memd->cas_multi, {};
};

subtest gat => sub {
    plan skip_all => 'memcached 1.5.3 is required' if $memd_version < v1.5.3;

    # Avoiding immediately expiration by 2 seconds expiration_time.
    # Because memcached truncates XXX1.999 seconds to XXX1.0 seconds,
    # 1 second expiration_time potentially expire immediately.
    my $expire = 2;

    # Wait +1 seconds for test stability.
    my $wait_expire = $expire + 1;

    ok $memd->set( $key, 'value' ), 'Store';
    is $memd->gat( $expire, $key ),
        'value', 'Get and Touch expiration_time : undef -> $expire';
    sleep $wait_expire;
    ok !$memd->get($key), 'Expired';

    # expiration_time will updated by gat
    ok $memd->set( $key, 'value', $expire ), 'Store';
    ok $memd->gat( undef, $key ), 'gat expire_time : $expire -> undef';
    sleep $wait_expire;
    ok $memd->get($key), 'Not Expired';

    $memd->delete($key);
    ok !$memd->gat( undef, $key ), 'gat no-such-key';

    $memd->set( key1 => 'key1_value' );
    $memd->set( key2 => 'key2_value', $expire );

    is $memd->gat_multi( $expire, qw/key1 key2 no-key/ ),
        { key1 => 'key1_value', key2 => 'key2_value' };

    sleep $wait_expire;

    is $memd->gat_multi( $expire, qw/key1 key2 no-key/ ), {};
    is $memd->gat_multi,                                  {};

    ok $memd->set( $key, 'value' ), 'Store';
    my $res = $memd->gats( $expire, $key );
    ok $res, 'Gats';
    is @$res, 2, 'Gats result is an array of two elements';
    ok $res->[0], 'CAS opaque defined';
    is $res->[1], 'value', 'Match value';
    $res->[1] = 'new value';
    ok $memd->cas( $key,  @$res ), 'First update success';
    ok !$memd->cas( $key, @$res ), 'Second update failure';
    is $memd->get($key), 'new value', 'Fetch';

    $res = $memd->gats_multi( $expire, @extra_keys );

    is keys %$res, @keys, 'Number of entries in result';
    my $count = 0;
    for my $k (@keys) {
        $count++ if ref( $res->{$k} ) eq 'ARRAY';
        $count++ if @{ $res->{$k} } == 2;
        $count++ if defined $res->{$k}->[0];
        $count++ if $res->{$k}->[1] eq $k;
    }
    is $count, count * 4;

    my $hash = $res;
    $res = $memd->cas_multi(
        [ $keys[0],      @{ $hash->{ $keys[0] } } ],
        [ 'no-such-key', 123, 'value', 10 ],
        [ $keys[1],      @{ $hash->{ $keys[1] } }, 1000 ],
    );
    is keys %$res, 3;
    ok $res->{ $keys[0] };
    ok defined $res->{'no-such-key'} && !$res->{'no-such-key'};
    ok $res->{ $keys[1] };

    my @res = $memd->cas_multi(
        [ $keys[2],      @{ $hash->{ $keys[2] } } ],
        [ 'no-such-key', 123, 'value', 10 ],
        [ $keys[3],      @{ $hash->{ $keys[3] } }, 1000 ]
    );
    is \@res, [ T, F, T ];

    is $memd->cas_multi, {};
};

subtest touch => sub {
    plan skip_all => 'memcached 1.4.8 is required' if $memd_version < v1.4.8;

    # Avoiding immediately expiration by 2 seconds expiration_time.
    # Because memcached truncates XXX1.999 seconds to XXX1.0 seconds,
    # 1 second expiration_time potentially expire immediately.
    my $expire = 2;

    # Wait +1 seconds for test stability.
    my $wait_expire = $expire + 1;

    # expiration_time will updated by touch
    ok $memd->set( $key, 'value' ), 'Store';
    ok $memd->touch( $key, $expire ),
        'Touch expiration_time : undef -> $expire';
    sleep $wait_expire;
    ok !$memd->get($key), 'Expired';

    # expiration_time will updated by touch
    ok $memd->set( $key, 'value', $expire ), 'Store';
    ok $memd->touch($key), 'Touch expire_time : $expire -> undef';
    sleep $wait_expire;
    ok $memd->get($key), 'Not Expired';

    $memd->delete($key);
    ok !$memd->touch($key), 'Touch no-such-key';

    # test touch_multi in list context
    $memd->set( $keys[0], 'value' );
    $memd->set( $keys[1], 'value', $expire );

    my @res = $memd->touch_multi(
        [ $keys[0], $expire ],
        [ $keys[1] ],
        ['no-such-key'],
    );

    is \@res, [ 1, 1, '' ];

    sleep $wait_expire;

    is $memd->get( $keys[0] ), undef,   'Expired';
    is $memd->get( $keys[1] ), 'value', 'Not Expired';

    # test touch_multi in scalar context
    $memd->set( $keys[0], 'value' );
    $memd->set( $keys[1], 'value', $expire );

    my $res = $memd->touch_multi(
        [ $keys[0], $expire ],
        [ $keys[1] ],
        ['no-such-key'],
    );

    is $res, { $keys[0] => 1, $keys[1] => 1, 'no-such-key' => '' };

    sleep $wait_expire;

    is $memd->get( $keys[0] ), undef,   'Expired';
    is $memd->get( $keys[1] ), 'value', 'Not Expired';

    is $memd->touch_multi, {};
};

$memd->set( $key, 'value' );
$memd->set( $_,   'value' ) for @keys;

ok $memd->replace_multi( map { [ $_, 0 ] } @keys ),
    'replace_multi to reset to numeric';
$res = $memd->incr_multi( [ $keys[0], 2 ], [ $keys[1] ],
    @keys[ 2 .. $#keys ] );
is values %$res, @keys;
is grep( { $_ != 1 } values %$res ), 1;
is $res->{ $keys[0] }, 2;

$res = $memd->delete_multi($key);
ok $res->{$key};
$res = $memd->delete_multi( [ $keys[0] ], $keys[1] );
ok $res->{ $keys[0] } && $res->{ $keys[1] };

ok $memd->remove( $keys[2] );
@res = $memd->delete_multi(@keys);
is @res, count;
is grep( { not $_ } @res ), 3;

done_testing;
