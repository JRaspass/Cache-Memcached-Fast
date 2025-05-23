use v5.12;
use warnings;

use ExtUtils::MakeMaker;

my %args = (
    ABSTRACT_FROM => 'lib/Cache/Memcached/Fast.pm',
    AUTHOR        => 'Tomash Brechko <tomash.brechko@gmail.com>',
    DEFINE        => '-Wall -Wextra',
    LICENSE       => 'perl_5',
    MYEXTLIB      => 'src/libclient$(LIB_EXT)',
    NAME          => 'Cache::Memcached::Fast',
    PREREQ_PM     => {
        'Carp'     => '1.25',    # For trailing dot.
        'XSLoader' => '0.14',    # For XSLoader::load with no arguments.
    },
    VERSION_FROM => 'lib/Cache/Memcached/Fast.pm',
    META_MERGE   => {
        'meta-spec' => { version => 2 },
        'resources' => {
            repository => {
                type => 'git',
                url  => 'git://github.com/JRaspass/Cache-Memcached-Fast.git',
                web  => 'https://github.com/JRaspass/Cache-Memcached-Fast',
            },
        },
    },
    BUILD_REQUIRES => {
        'ExtUtils::ParseXS' => '3.12',    # For embedded typemaps.
    },
    TEST_REQUIRES => {
        'Test2::Suite' => '0.000072',     # For Test2::V0.
    },
);

# Merge *_REQUIRES into PREREQ_PM if EU::MM is too old to understand.
for ( [ BUILD_REQUIRES => '6.55_03' ], [ TEST_REQUIRES => '6.64' ] ) {
    my ( $key, $ver ) = @$_;
    $args{PREREQ_PM} = { %{ $args{PREREQ_PM} }, %{ delete $args{$key} } }
        unless eval { ExtUtils::MakeMaker->VERSION($ver) };
}

WriteMakefile(%args);

sub MY::postamble {<<'MAKE'}
$(MYEXTLIB): src/Makefile
	cd src && $(MAKE) $(PASTHRU)

bench: all
	$(PERL) -I./blib/lib -I./blib/arch script/benchmark.pl \
	    localhost:11211 127.0.0.1:11211
MAKE
