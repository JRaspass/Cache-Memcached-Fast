use warnings;
use strict;

use Test::More;

use FindBin;

use lib "$FindBin::Bin";
use Memd;

if ($^V lt v5.8.0) {
   plan skip_all => 'Perl >= 5.8.0 is required';
}

if ($Memd::memd) {
    plan tests => 4;
} else {
    plan skip_all => 'Not connected';
}


my %params = %Memd::params;
delete $params{utf8};
my $memd_bytes = new Cache::Memcached::Fast(\%params);

use utf8;

my $str_bytes = "\x81";
my $str_utf8 = $str_bytes;
utf8::upgrade($str_utf8);
is($str_bytes, $str_utf8);

$memd_bytes->set('utf8-downgrade', $str_utf8);
my $str = $memd_bytes->get('utf8-downgrade');
is($str, $str_utf8);

my $str2 = $Memd::memd->get('utf8-downgrade');
is($str2, $str_utf8);

eval {
    $memd_bytes->set('utf8-downgrade', 'Привет');
};
like($@, qr/Wide character in subroutine entry at/);


$Memd::memd->delete('utf8-downgrade');
