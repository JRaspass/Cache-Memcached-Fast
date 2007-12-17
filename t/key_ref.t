use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 5;
} else {
    plan skip_all => 'Not connected';
}


my $key = "key_ref";
my $value = "value ref check";
ok($Memd::memd->set($key, $value), 'Store');
my $h = $Memd::memd->get_multi($key);
is($h->{$key}, $value, 'Fetch');

my $old_key = $key;
substr($key, 3, 4, "");
is($h->{$old_key}, $value, 'Access with the old key');
ok(! exists $h->{$key}, 'Access with modified key');

ok($Memd::memd->delete($old_key), 'Delete');
