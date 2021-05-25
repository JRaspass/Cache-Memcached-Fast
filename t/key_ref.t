use lib 't';
use strict;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected' unless $Memd::memd;

my $key   = "key_ref";
my $value = "value ref check";
ok( $Memd::memd->set( $key, $value ), 'Store' );
my $h = $Memd::memd->get_multi($key);
is( $h->{$key}, $value, 'Fetch' );

my $old_key = $key;
substr( $key, 3, 4, "" );
is( $h->{$old_key}, $value, 'Access with the old key' );
ok( !exists $h->{$key}, 'Access with modified key' );

ok( $Memd::memd->delete($old_key), 'Delete' );

done_testing;
