#! /usr/bin/perl
# -*- cperl -*-
#
# Copyright (C) 2009 Tomash Brechko.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.8
# or, at your option, any later version of Perl 5 you may have
# available.
#
use warnings;
use strict;

=head1 NAME

ketama-distr.pl - compute relative distribution of keys.

=head1 SYNOPSIS

  ketama-distr.pl OPTIONS

=head1 OPTIONS

=over

=item C<--ketama_points, -k NUM>

B<Required, greater than zero.> Number of ketama points per server of
weight 1.

=item C<--server, -s HOST:PORT[:WEIGHT]>

B<Two or more.>  Specifies a server.  May be given multiple
times.  Default I<WEIGHT> is 1.

=back

=cut


use Getopt::Long qw(:config gnu_getopt);
use Pod::Usage;

my %options;
if (! GetOptions(\%options,
                 qw(ketama_points|k=i server|s=s@))
    || @ARGV || grep({ not defined } @options{qw(ketama_points server)})
    || $options{ketama_points} <= 0 || @{$options{server}} < 2) {
    pod2usage(1);
}


use String::CRC32;


sub compute_old {
    my ($server, $index, $prev) = @_;

    $server =~ s/:/\0/;

    my $point = crc32($server . pack("V", $index));

    return $point;
}


sub compute_new {
    my ($server, $index, $prev) = @_;

    $server =~ s/:/\0/;

    my $point = crc32($server . pack("V", $prev));

    return $point;
}


sub compute {
    my ($compute_point) = @_;

    my @continuum;

    my $j = 0;
    foreach my $s (@{$options{server}}) {
        ++$j;
        my ($server, $weight) = $s =~ /^([^:]+:[^:]+)(?::(.+))?$/;

        die "$s should be HOST:PORT" unless defined $server;

        $weight = 1 unless defined $weight;

        my $prev = 0;
        for (my $i = 0; $i < $options{ketama_points} * $weight; ++$i) {
            my $point = $compute_point->($server, $i, $prev);
            push @continuum, [$point, "$j: $server"];
            $prev = $point;
        }
    }

    use sort 'stable';
    @continuum = sort {$a->[0] <=> $b->[0]} @continuum;

    my $prev_point = 0;
    my $first_server = '';
    my %server_share;
    foreach my $c (@continuum) {
        $first_server = $c->[1] unless $first_server;
        $server_share{$c->[1]} += $c->[0] - $prev_point;
        $prev_point = $c->[0];
    }
    # Wraparound case.
    $server_share{$first_server} += 2**32 - 1 - $prev_point;

    foreach my $s (sort keys %server_share) {
        my $share = $server_share{$s};
        printf("server %s  total = % 10u (%.2f%%)\n",
               $s, $share, $share * 100 / (2**32 - 1));
    }

    return @continuum;
}


print "Old:\n";
compute(\&compute_old);
print "\n";
print "New:\n";
my $total_points = compute(\&compute_new);
print "\n";
my $int_size = 4;
print "Continuum array size = ", $total_points * $int_size * 2, " bytes\n";
