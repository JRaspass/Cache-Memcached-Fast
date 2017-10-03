use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Cache::Memcached::Fast',
    LICENSE           => 'perl_5',
    VERSION_FROM      => 'lib/Cache/Memcached/Fast.pm',
    PREREQ_PM         => {
       'Test::More'  =>  0,
    },
    ABSTRACT_FROM     => 'lib/Cache/Memcached/Fast.pm',
    AUTHOR            => 'Tomash Brechko <tomash.brechko@gmail.com>',
    MYEXTLIB          => 'src/libclient$(LIB_EXT)',
    META_MERGE        => {
        resources => {
            repository => 'https://github.com/kroki/Cache-Memcached-Fast',
        },
    },
);

sub MY::cflags {
  my $self = shift;
  my $orig = $self->MM::cflags(@_);
  $orig =~ s/-flto\b//g;
  return $orig;
}

sub MY::postamble {
'
$(MYEXTLIB): src/Makefile
	cd src && $(MAKE) $(PASTHRU)

bench: all
	$(PERL) -I./blib/lib -I./blib/arch script/benchmark.pl \
	  localhost:11211 127.0.0.1:11211
'
}
