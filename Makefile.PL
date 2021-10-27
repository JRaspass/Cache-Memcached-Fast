use v5.8.1;
use strict;
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
        'XSLoader' => '0',
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
    TEST_REQUIRES => {
        'Test2::Suite' => '0.000072',    # For Test2::V0.
        'version'      => '0.77',        # For version->parse.
    },
);

# Merge TEST_REQUIRES into PREREQ_PM if EU::MM is too old to understand.
$args{PREREQ_PM} = { %{ $args{PREREQ_PM} }, %{ delete $args{TEST_REQUIRES} } }
    unless eval { ExtUtils::MakeMaker->VERSION('6.64') };

WriteMakefile(%args);

sub MY::postamble { <<'MAKE' }
$(MYEXTLIB): src/Makefile
	cd src && $(MAKE) $(PASTHRU)

bench: all
	$(PERL) -I./blib/lib -I./blib/arch script/benchmark.pl \
	    localhost:11211 127.0.0.1:11211
MAKE
