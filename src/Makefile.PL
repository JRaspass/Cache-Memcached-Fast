use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Cache::Memcached1::client',
    VERSION_FROM      => '../lib/Cache/Memcached1.pm', # finds $VERSION
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (AUTHOR         => 'Tomash Brechko <tomash@localdomain>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
    OBJECT            => '$(O_FILES)', # link all the C files too
);

sub MY::top_targets {
'
all :: static

pure_all :: static

static :: libclient$(LIB_EXT)

libclient$(LIB_EXT): $(O_FILES)
	$(AR) cr libclient$(LIB_EXT) $(O_FILES)
	$(RANLIB) libclient$(LIB_EXT)
'
}
