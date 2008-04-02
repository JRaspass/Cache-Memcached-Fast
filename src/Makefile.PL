use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Cache::Memcached::Fast::libclient',
    VERSION_FROM      => '../lib/Cache/Memcached/Fast.pm',
    AUTHOR            => 'Tomash Brechko <tomash.brechko@gmail.com>',
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
    OBJECT            => 'parse_keyword$(OBJ_EXT) compute_crc32$(OBJ_EXT)
                          $(O_FILES)',
    clean             => { FILES => 'compute_crc32.c compute_crc32.h
                                     parse_keyword.c parse_keyword.h' },
);

sub MY::top_targets {
'
all :: static

pure_all :: static

static :: libclient$(LIB_EXT)

libclient$(LIB_EXT): $(OBJECT)
	$(AR) cr libclient$(LIB_EXT) $(OBJECT)
	$(RANLIB) libclient$(LIB_EXT)

parse_keyword.c parse_keyword.h :: genparser.pl reply.kw
	$(PERL) genparser.pl reply.kw parse_keyword.c parse_keyword.h

compute_crc32.c compute_crc32.h :: gencrc32.pl
	$(PERL) gencrc32.pl compute_crc32.c compute_crc32.h
'
}
