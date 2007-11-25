use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Cache::MemcachedFast',
    VERSION_FROM      => 'lib/Cache/MemcachedFast.pm', # finds $VERSION
    PREREQ_PM         => {'Test::More'  =>  0}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Cache/MemcachedFast.pm', # retrieve abstract from module
       AUTHOR         => 'Tomash Brechko <tomash.brechko@gmail.com>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
    MYEXTLIB          => 'src/libclient$(LIB_EXT)',
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);

sub MY::postamble {
'
$(MYEXTLIB): src/Makefile
	cd src && $(MAKE) $(PASSTHRU)
'
}
