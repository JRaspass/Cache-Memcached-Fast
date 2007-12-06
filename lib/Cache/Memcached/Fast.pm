package Cache::Memcached::Fast;

use 5.006;
use strict;
use warnings;


our $VERSION = '0.02';


require XSLoader;
XSLoader::load('Cache::Memcached::Fast', $VERSION);

# Preloaded methods go here.


# BIG FAT WARNING: Perl assignment copies the value, so below we try
# to avoid any copying.


sub set {
    my $flags = 0;

    # FIXME: set $flags here.

    splice(@_, 3, 0, $flags);
    return _xs_set(@_);
}


sub add {
    my $flags = 0;

    # FIXME: set $flags here.

    splice(@_, 3, 0, $flags);
    return _xs_add(@_);
}


sub replace {
    my $flags = 0;

    # FIXME: set $flags here.

    splice(@_, 3, 0, $flags);
    return _xs_replace(@_);
}


sub append {
    # append() does not affect flags.
    splice(@_, 3, 0, 0);
    return _xs_append(@_);
}


sub prepend {
    # prepend() does not affect flags.
    splice(@_, 3, 0, 0);
    return _xs_prepend(@_);
}


sub get {
    my ($val, $flags) = _xs_get(@_);

    # FIXME: process $flags here.

    return $val;
}


sub get_multi {
    my ($key_val, $flags) = _xs_mget(@_);

    # FIXME: process $flags here.

    return _xs_rvav2rvhv($key_val);
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
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
