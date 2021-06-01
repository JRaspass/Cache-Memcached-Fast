use lib 't';

use Memd;
use Test2::V0 -target => 'Cache::Memcached::Fast';

use constant count => 1000;

my $another_memd = CLASS->new( \%Memd::params );

my @keys = map "nowait-$_", 1 .. count;

$memd->set( $_ => $_ ) for @keys;

$memd->replace( 'no-such-key', 1 );
$memd->replace( 'no-such-key', 1 );

my @extra_keys = @keys;
splice @extra_keys, rand( @extra_keys + 1 ), 0, "no_such_key-$_"
    for 1 .. count;

is $memd->get_multi(@extra_keys), { map { $_ => $_ } @keys };

is $another_memd->get( $keys[-1] ), $keys[-1];

$memd->delete($_) for @keys;

$memd->nowait_push;

is $another_memd->get( $keys[$#keys] ), undef;

done_testing;
