package Cache::Memcached::Fast;

use 5.006;
use strict;
use warnings;


our $VERSION = '0.02';


use Storable;

use constant F_STORABLE => 0x1;
use constant F_COMPRESS => 0x2;


require XSLoader;
XSLoader::load('Cache::Memcached::Fast', $VERSION);


our $AUTOLOAD;


# BIG FAT WARNING: Perl assignment copies the value, so below we try
# to avoid any copying.


my %compress_algo;


BEGIN {
    my @algo = (
        'Gzip'        =>  'Gunzip',
        'Zip'         =>  'Unzip',
        'Bzip2'       =>  'Bunzip2',
        'Deflate'     =>  'Inflate',
        'RawDeflate'  =>  'RawInflate',
        'Lzop'        =>  'UnLzop',
        'Lzf'         =>  'UnLzf',
    );

    while (my ($c, $u) = splice(@algo, 0, 2)) {
        my $key = lc $c;
        my $val = ["IO::Compress::$c", "IO::Compress::${c}::" . lc $c,
                   "IO::Uncompress::$u", "IO::Uncompress::${u}::" . lc $u];
        $compress_algo{$key} = $val;
    }
}


use fields qw(
    _xs
    compress_threshold compress_ratio compress_methods
);


sub new {
    my $class = shift;
    my ($conf) = @_;

    my $self = fields::new($class);

    # $conf->{compress_threshold} == 0 actually disables compression.
    $self->{compress_threshold} = $conf->{compress_threshold} || -1;
    $self->{compress_ratio} = $conf->{compress_ratio} || 0.8;
    $self->{compress_methods} =
      $compress_algo{lc($conf->{compress_algo} || 'gzip')};

    $self->{_xs} = new Cache::Memcached::Fast::_xs($conf);

    return $self;
}


sub DESTROY {
    # Do nothing.  Destructor is required for not to call destructor
    # of Cache::Memcached::Fast::_xs via AUTOLOAD.
}


sub enable_compress {
    my Cache::Memcached::Fast $self = shift;
    my ($enable) = @_;

    if ($self->{compress_threshold} > 0 xor $enable) {
        $self->{compress_threshold} = -$self->{compress_threshold};
    }
}


sub _pack_value {
    my Cache::Memcached::Fast $self = shift;

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

    use bytes;
    my $len = length $$val_ref;
    if ($self->{compress_threshold} > 0
        and $len >= $self->{compress_threshold}) {
        my $methods = $self->{compress_methods};
        if (eval "require $$methods[0]") {
            no strict 'refs';
            my $res = &{$$methods[1]}($val_ref, \my $compressed);
            if ($res
                and length $compressed <= $len * $self->{compress_ratio}) {
                $val_ref = \$compressed;
                $flags |= F_COMPRESS;
            }
        } else {
            warn "Can't find module $$methods[0]";
            $self->enable_compress(0);
        }
    }

    return ($val_ref, $flags);
}


sub _unpack_value {
    my Cache::Memcached::Fast $self = shift;

    if ($_[1] & F_COMPRESS) {
        my $methods = $self->{compress_methods};
        if (eval "require $$methods[2]") {
            no strict 'refs';
            my $res = &{$$methods[3]}($_[0], \my $uncompressed);
            return unless $res;
            $_[0] = \$uncompressed;
        } else {
            return;
        }
    }

    if ($_[1] & F_STORABLE) {
        eval {
            $_[0] = \Storable::thaw(${$_[0]});
        };
        return if $@;
    }

    return 1;
}


sub set {
    my Cache::Memcached::Fast $self = shift;
    splice(@_, 1, 1, _pack_value($self, $_[1]));
    return $self->{_xs}->set(@_);
}


sub cas {
    my Cache::Memcached::Fast $self = shift;
    splice(@_, 2, 1, _pack_value($self, $_[2]));
    return $self->{_xs}->cas(@_);
}


sub add {
    my Cache::Memcached::Fast $self = shift;
    splice(@_, 1, 1, _pack_value($self, $_[1]));
    return $self->{_xs}->add(@_);
}


sub replace {
    my Cache::Memcached::Fast $self = shift;
    splice(@_, 1, 1, _pack_value($self, $_[1]));
    return $self->{_xs}->replace(@_);
}


sub append {
    my Cache::Memcached::Fast $self = shift;
    # append() does not affect flags.
    splice(@_, 1, 1, \$_[1], 0);
    return $self->{_xs}->append(@_);
}


sub prepend {
    my Cache::Memcached::Fast $self = shift;
    # prepend() does not affect flags.
    splice(@_, 1, 1, \$_[1], 0);
    return $self->{_xs}->prepend(@_);
}


sub rget {
    my Cache::Memcached::Fast $self = shift;

    my ($val, $flags) = $self->{_xs}->get(@_);

    if (defined $val and _unpack_value($self, $val, $flags)) {
        return $val;
    } else {
        return undef;
    }
}


sub get {
    my $val_ref = rget(@_);

    if (defined $val_ref) {
        return $$val_ref;
    } else {
        return undef;
    }
}


sub get_multi {
    my Cache::Memcached::Fast $self = shift;

    my ($key_val, $flags) = $self->{_xs}->mget(@_);

    my $vi = 1;
    foreach my $f (@$flags) {
        if (_unpack_value($self, $$key_val[$vi], $f)) {
            $$key_val[$vi] = ${$$key_val[$vi]};
            $vi += 2;
        } else {
            splice(@$key_val, $vi - 1, 2);
        }
    }

    return Cache::Memcached::Fast::_xs::_rvav2rvhv($key_val);
}


sub gets {
    my Cache::Memcached::Fast $self = shift;

    my ($val, $flags) = $self->{_xs}->gets(@_);

    if (defined $val and _unpack_value($self, $$val[1], $flags)) {
        $$val[1] = ${$$val[1]};
        return $val;
    } else {
        return undef;
    }
}


sub gets_multi {
    my Cache::Memcached::Fast $self = shift;

    my ($key_val, $flags) = $self->{_xs}->mgets(@_);

    my $vi = 1;
    foreach my $f (@$flags) {
        if (_unpack_value($self, ${$$key_val[$vi]}[1], $f)) {
            ${$$key_val[$vi]}[1] = ${${$$key_val[$vi]}[1]};
            $vi += 2;
        } else {
            splice(@$key_val, $vi - 1, 2);
        }
    }

    return Cache::Memcached::Fast::_xs::_rvav2rvhv($key_val);
}


sub AUTOLOAD {
    my Cache::Memcached::Fast $self = shift;
    my ($method) = $AUTOLOAD =~ /::([^:]+)$/;
    return $self->{_xs}->$method(@_);
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
