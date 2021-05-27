use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

use constant count => 1000;

my $another_memd = Cache::Memcached::Fast->new( \%Memd::params );

my @keys = map "nowait-$_", 1 .. count;

$Memd::memd->set( $_ => $_ ) for @keys;

$Memd::memd->replace( 'no-such-key', 1 );
$Memd::memd->replace( 'no-such-key', 1 );

my @extra_keys = @keys;
splice @extra_keys, rand( @extra_keys + 1 ), 0, "no_such_key-$_"
    for 1 .. count;

is_deeply $Memd::memd->get_multi(@extra_keys), { map { $_ => $_ } @keys };

is $another_memd->get( $keys[-1] ), $keys[-1];

$Memd::memd->delete($_) for @keys;

$Memd::memd->nowait_push;

is $another_memd->get( $keys[$#keys] ), undef;

done_testing;
