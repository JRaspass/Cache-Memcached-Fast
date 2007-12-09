package Cache::Memcached::Fast;

use 5.006;
use strict;
use warnings;


our $VERSION = '0.02';


use Storable;

use constant F_STORABLE => 0x1;


require XSLoader;
XSLoader::load('Cache::Memcached::Fast', $VERSION);


# BIG FAT WARNING: Perl assignment copies the value, so below we try
# to avoid any copying.


sub _pack_value {
    my $flags = 0;
    my $val_ref;

    # We use $val_ref to avoid both modifying original argument and
    # copying the value when it is not a reference.
    if (ref($_[0])) {
        $val_ref = \Storable::nfreeze($_[0]);
        $flags |= F_STORABLE;
    } else {
        $val_ref = \$_[0];
    }

    return ($$val_ref, $flags);
}


sub _unpack_value {
    if ($_[1] & F_STORABLE) {
        eval {
            $_[0] = Storable::thaw($_[0]);
        };
        return $@ if $@;
    }
}


sub set {
    splice(@_, 2, 1, _pack_value($_[2]));
    return _xs_set(@_);
}


sub cas {
    splice(@_, 3, 1, _pack_value($_[3]));
    return _xs_cas(@_);
}


sub add {
    splice(@_, 2, 1, _pack_value($_[2]));
    return _xs_add(@_);
}


sub replace {
    splice(@_, 2, 1, _pack_value($_[2]));
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

    my $error = _unpack_value($val, $flags) if defined $val;
    return if $error;

    return $val;
}


sub get_multi {
    my ($key_val, $flags) = _xs_mget(@_);

    my $vi = 1;
    foreach my $f (@$flags) {
        my $error = _unpack_value($$key_val[$vi], $f);
        if ($error) {
            splice(@$key_val, $vi - 1, 2);
        } else {
            $vi += 2;
        }
    }

    return _xs_rvav2rvhv($key_val);
}


sub gets {
    my ($val, $flags) = _xs_gets(@_);

    my $error = _unpack_value($$val[1], $flags) if defined $val;
    return if $error;

    return $val;
}


sub gets_multi {
    my ($key_val, $flags) = _xs_mgets(@_);

    my $vi = 1;
    foreach my $f (@$flags) {
        my $error = _unpack_value(${$$key_val[$vi]}[1], $f);
        if ($error) {
            splice(@$key_val, $vi - 1, 2);
        } else {
            $vi += 2;
        }
    }

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
