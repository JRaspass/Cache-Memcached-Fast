#! /usr/bin/perl
#
# Copyright (C) 2007 Tomash Brechko.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.8
# or, at your option, any later version of Perl 5 you may have
# available.
#
use warnings;
use strict;


use FindBin;

@ARGV >= 1
    or die "Usage: $FindBin::Script HOST:PORT... [COUNT]\n";

my $count = ($ARGV[$#ARGV] =~ /^\d+$/ ? pop @ARGV : 100_000);

my @addrs = @ARGV;

my $max_keys = $count / 2;
my $keys_multi = 100;
my $value = 'x' x 40;


use Cache::Memcached::Fast;
use Cache::Memcached;
use Benchmark qw(:hireswallclock timethese cmpthese);


use constant NOREPLY => 0;
use constant CAS => 1;


my $new = new Cache::Memcached::Fast {
    servers   => [@addrs],
    namespace => 'Cache::Memcached::New',
    noreply   => NOREPLY,
};


my $old = new Cache::Memcached {
    servers   => [@addrs],
    namespace => 'Cache::Memcached::Old',
};
$old->enable_compress(0);


sub get_key {
    int(rand($max_keys));
}


sub compare {
    my ($method, $keys, $noreply, $value, $cas) = @_;

    my $title = "$method";
    if (defined $value) {
        use bytes;
        $title .= '(' . length($value) . ' bytes)';
    } elsif ($keys > 1) {
        $title .= "($keys keys)";
    }

    my $res;

    my $params = sub {
        my @params = map { get_key() } (1 .. $keys);
        push @params, 0 if $cas;
        push @params, $value if defined $value;
        return @params;
    };

    my @test = (
        "Old $title"  => sub { $res = $old->$method(&$params) },
        "New $title"  => sub { $res = $new->$method(&$params) },
    );

    if ($noreply) {
        push @test, (
             "Old $title noreply"  => sub { $old->$method(&$params) },
             "New $title noreply"  => sub { $new->$method(&$params) },
        );
    }

    cmpthese(timethese(int($count / $keys), {@test}));
}


sub compare_multi {
    my ($method, $keys) = @_;

    my $method_multi = "${method}_multi";

    my $res;

    my @keys = map { int(rand($max_keys)) } (1 .. $keys);

    my @test = (
        "Old $method x $keys"
                => sub { $res = $old->$method($_) foreach (@keys) },
        "New $method x $keys"
                => sub { $res = $new->$method($_) foreach (@keys) },
        "Old $method_multi($keys)"
                => sub { $res = $old->$method_multi(@keys) },
        "New $method_multi($keys)"
                => sub { $res = $new->$method_multi(@keys) },
    );

    cmpthese(timethese(int($count / $keys), {@test}));
}


# Cache::Memcached doesn't support append/prepend, cas, gets, gets_multi yet.
my @methods = (
    [add        => \&compare, 1, NOREPLY, $value],
    [set        => \&compare, 1, NOREPLY, $value],
#    [append     => \&compare, 1, NOREPLY, $value],
#    [prepend    => \&compare, 1, NOREPLY, $value],
    [replace    => \&compare, 1, NOREPLY, $value],
#    [cas        => \&compare, 1, NOREPLY, $value, CAS],
    [get        => \&compare, 1],
    [get_multi  => \&compare, $keys_multi],
#    [gets       => \&compare, 1],
#    [gets_multi => \&compare, $keys_multi],
    [get        => \&compare_multi, $keys_multi],
#    [gets       => \&compare_multi, $keys_multi],
    [incr       => \&compare, 1, NOREPLY],
    [decr       => \&compare, 1, NOREPLY],
    [delete     => \&compare, 1, NOREPLY],
);


srand(1);
foreach my $args (@methods) {
    my $sub = splice(@$args, 1, 1);
    &$sub(@$args);
}
