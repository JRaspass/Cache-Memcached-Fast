use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 13;
} else {
    plan skip_all => 'Not connected';
}


use constant THRESHOLD => 1024 * 1024 - 1024;

my $key = 'big_value';
my $value = 'x' x THRESHOLD;
my $small_value = 'x' x (THRESHOLD - 2048);
my $big_value = 'x' x (THRESHOLD + 2048);

my %smaller_params = %Memd::params;
$smaller_params{max_size} = THRESHOLD - 2048;
$smaller_params{namespace} .= 'smaller/';
my $smaller_memd = new Cache::Memcached::Fast(\%smaller_params);

my %bigger_params = %Memd::params;
$bigger_params{max_size} = THRESHOLD + 2048;
$bigger_params{namespace} .= 'bigger/';
my $bigger_memd = new Cache::Memcached::Fast(\%bigger_params);

$Memd::memd->enable_compress(0);
$smaller_memd->enable_compress(0);
$bigger_memd->enable_compress(0);

ok($Memd::memd->set($key, $value), 'Store value uncompressed');
ok($Memd::memd->get($key) eq $value, 'Fetch');
ok(! $smaller_memd->set($key, $value),
   'Values equal to or greater than THRESHOLD should be rejected by module');
ok(! $bigger_memd->set($key, $big_value),
   'Values greater than 1MB should be rejected by server');

my @res = $smaller_memd->set_multi(["$key-1", $small_value],
                                   ["$key-2", $big_value],
                                   ["$key-3", $small_value]);
ok($res[0] and not defined $res[1] and $res[2]);
ok($smaller_memd->delete_multi("$key-1", "$key-3"));

SKIP: {
    my $warning;

    {
        local $SIG{__WARN__} = sub { die $_[0] };

        eval {
            $Memd::memd->enable_compress(1);
            $smaller_memd->enable_compress(1);
            $bigger_memd->enable_compress(1);
        }
    }

    if ($@) {
        if ($@ =~ /^Compression module was not found/) {
            skip $@, 6;
        } else {
            warn "$@\n";
        }
    }

    ok($smaller_memd->set($key, $value), 'Store compressed value');
    ok($bigger_memd->set($key, $big_value), 'Store compressed value');

    ok($smaller_memd->get($key) eq $value, 'Fetch and uncompress');
    ok($bigger_memd->get($key) eq $big_value, 'Fetch and uncompress');

    ok($smaller_memd->delete($key), 'Delete');
    ok($bigger_memd->delete($key), 'Delete');
}

ok($Memd::memd->delete($key), 'Delete');
