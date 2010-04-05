use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 9;
} else {
    plan skip_all => 'Not connected';
}


use Tie::Scalar;
use Tie::Array;
use Tie::Hash;

tie my $scalar, 'Tie::StdScalar';
tie my @array, 'Tie::StdArray';
tie my %hash, 'Tie::StdHash';

%hash = %Memd::params;
@array = @{$hash{servers}};
$hash{servers} = \@array;
my $memd = new Cache::Memcached::Fast(\%hash);

use utf8;

my $key = "Кириллица.в.UTF-8";
$scalar = $key;
ok($memd->set($scalar, $scalar));
ok(exists $memd->get_multi($scalar)->{$scalar});
is($memd->get($scalar), $key);
is($memd->get($key), $scalar);


package MyScalar;
use base 'Tie::StdScalar';

sub FETCH {
    "Другой.ключ"
}

package main;

tie my $scalar2, 'MyScalar';

ok($memd->set($scalar2, $scalar2));
ok(exists $memd->get_multi($scalar2)->{$scalar2});

SKIP: {
    eval { require Readonly };
    skip "Skipping Readonly tests because the module is not present", 3
      if $@;

    # 'require Readonly' as above can be used to test if the module is
    # present, but won't actually work.  So below we 'use Readonly',
    # but in a string eval.
    eval q{
        use Readonly;

        Readonly my $expires => 3;

        Readonly my $key2 => "Третий.ключ";
        ok($memd->set($key2, $key2, $expires));
        ok(exists $memd->get_multi($key2)->{$key2});
        sleep(4);
        ok(! exists $memd->get_multi($key2)->{$key2});
    };
}
