package Cache::Memcached::Fast;

use 5.006;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Cache::Memcached::Fast ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.02';

require XSLoader;
XSLoader::load('Cache::Memcached::Fast', $VERSION);

# Preloaded methods go here.


sub set {
    my ($self, $key, $val, $exptime) = @_;
    my $flags = 0;

    # FIXME: set $flags here.

    return _xs_set($self, $key, $val, $flags, $exptime);
}


sub add {
    my ($self, $key, $val, $exptime) = @_;
    my $flags = 0;

    # FIXME: set $flags here.

    return _xs_add($self, $key, $val, $flags, $exptime);
}


sub replace {
    my ($self, $key, $val, $exptime) = @_;
    my $flags = 0;

    # FIXME: set $flags here.

    return _xs_replace($self, $key, $val, $flags, $exptime);
}


sub append {
    my ($self, $key, $val, $exptime) = @_;

    # append() does not affect flags.
    return _xs_append($self, $key, $val, 0, $exptime);
}


sub prepend {
    my ($self, $key, $val, $exptime) = @_;

    # prepend() does not affect flags.
    return _xs_prepend($self, $key, $val, 0, $exptime);
}


sub get {
    my ($val, $flags) = _xs_get(@_);

    # FIXME: process $flags here.

    return $val;
}


sub get_multi {
    my ($key_val, $flags) = _xs_mget(@_);

    # FIXME: process $flags here.

    my %res = @$key_val;
    return \%res;
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Cache::Memcached::Fast - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Cache::Memcached::Fast;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Cache::Memcached::Fast, created by h2xs. It
looks like the author of the extension was negligent enough to leave
the stub unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Tomash Brechko, E<lt>tomash.brechko@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Tomash Brechko

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
