use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($Memd::memd) {
    plan tests => 6;
} else {
    plan skip_all => 'Not connected';
}


my $key = 'big_value';
my $value = 'x' x 500_000;

$Memd::memd->enable_compress(0);

ok(! $Memd::memd->set($key, $value x 4),
   'Values over 1MB should be rejected');
ok($Memd::memd->set($key, $value), 'Store value uncompressed');
ok($Memd::memd->get($key) eq $value, 'Fetch');

$Memd::memd->enable_compress(1);

SKIP: {
    my $warning;

    {
        local $SIG{__WARN__} = sub { $warning = $_[0] };

        ok($Memd::memd->set($key, $value), 'Store value possibly compressed');
    }

    if (defined $warning) {
        if ($warning =~ /^Can't find module IO::Compress::/) {
            skip $warning, 1;
        } else {
            warn "$warning\n";
        }
    }

    ok($Memd::memd->get($key) eq $value, 'Fetch and uncompress');
}

ok($Memd::memd->delete($key), 'Delete');
