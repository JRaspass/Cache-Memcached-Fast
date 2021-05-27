use lib 't';
use strict;
use utf8;
use warnings;

use Memd;
use Test::More;

plan skip_all => 'Not connected'             unless $Memd::memd;
plan skip_all => 'Perl >= 5.8.1 is required' unless $^V ge v5.8.1;

my $memd_bytes = Cache::Memcached::Fast->new( { %Memd::params, utf8 => 0 } );

utf8::encode my $bytes = my $string = 'Кириллица в UTF-8 🐪';

subtest bytes => sub {
    ok !utf8::is_utf8 $bytes;

    ok $memd_bytes->set( bytes => $bytes );

    is $memd_bytes->get('bytes'), $bytes;

    is $Memd::memd->get('bytes'), $bytes;
};

subtest string => sub {
    ok utf8::is_utf8 $string;

    ok $Memd::memd->set( string => $string );

    is $Memd::memd->get('string'), $string;

    is $memd_bytes->get('string'), $bytes;

    eval { $memd_bytes->set( string => $string ) };
    is $@, 'Wide character in subroutine entry at '
        . ( __FILE__ . ' line ' . ( __LINE__ - 2 ) . ".\n" );
};

$Memd::memd->delete_multi(qw/bytes string/);

done_testing;
