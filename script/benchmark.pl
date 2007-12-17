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
use Benchmark qw(:hireswallclock timethese cmpthese);


use constant NOREPLY => 0;
use constant CAS => 1;


my $new = new Cache::Memcached::Fast {
    servers   => [@addrs],
    namespace => 'Cache::Memcached::New',
    ketama_points => 150,
    noreply   => NOREPLY,
};


sub get_key {
    int(rand($max_keys));
}


sub run {
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
        "$title"  => sub { $res = $new->$method(&$params) },
    );

    if ($noreply) {
        push @test, (
             "$title noreply"  => sub { $new->$method(&$params) },
        );
    }

    cmpthese(timethese(int($count / $keys), {@test}));
}


sub run_multi {
    my ($method, $keys) = @_;

    my $method_multi = "${method}_multi";

    my $res;

    my @keys = map { int(rand($max_keys)) } (1 .. $keys);

    my @test = (
        "$method x $keys"
                => sub { $res = $new->$method($_) foreach (@keys) },
        "$method_multi($keys)"
                => sub { $res = $new->$method_multi(@keys) },
    );

    cmpthese(timethese(int($count / $keys), {@test}));
}


my @methods = (
    [add        => \&run, 1, NOREPLY, $value],
    [set        => \&run, 1, NOREPLY, $value],
    [append     => \&run, 1, NOREPLY, $value],
    [prepend    => \&run, 1, NOREPLY, $value],
    [replace    => \&run, 1, NOREPLY, $value],
    [cas        => \&run, 1, NOREPLY, $value, CAS],
    [get        => \&run, 1],
    [get_multi  => \&run, $keys_multi],
    [gets       => \&run, 1],
    [gets_multi => \&run, $keys_multi],
    [get        => \&run_multi, $keys_multi],
    [gets       => \&run_multi, $keys_multi],
    [incr       => \&run, 1, NOREPLY],
    [decr       => \&run, 1, NOREPLY],
    [delete     => \&run, 1, NOREPLY],
);


srand(1);
foreach my $args (@methods) {
    my $sub = splice(@$args, 1, 1);
    &$sub(@$args);
}
