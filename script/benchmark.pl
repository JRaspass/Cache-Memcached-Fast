#! /usr/bin/perl
#
# Copyright (C) 2007-2008 Tomash Brechko.  All rights reserved.
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

my $count = ($ARGV[$#ARGV] =~ /^\d+$/ ? pop @ARGV : 250);

my @addrs = @ARGV;

use constant key_count => 100;
use constant repeat => 4;
use constant NOWAIT => 1;
use constant NOREPLY => 0;

my $max_keys = $count * key_count / 2;
my $value = 'x' x 40;


use Cache::Memcached::Fast;
use Benchmark qw(:hireswallclock timethese cmpthese);


use constant CAS => 1;


my $new = new Cache::Memcached::Fast {
    servers   => [@addrs],
    namespace => "Cache::Memcached::bench/$$/",
    ketama_points => 150,
    nowait => NOWAIT,
};

my $version = $new->server_versions;
if (keys %$version != @addrs) {
    warn "No server is running at "
        . join(', ', grep { not exists $version->{$_} }
               @{$new->{servers}})
        . "\n";
    exit 1;
}


@addrs = map { +{ address => $_, noreply => NOREPLY } } @addrs;

my $new_noreply = new Cache::Memcached::Fast {
    servers   => [@addrs],
    namespace => "Cache::Memcached::bench/$$/",
    ketama_points => 150,
};


sub get_key {
    int(rand($max_keys));
}


sub run {
    my ($method, $value, $cas) = @_;

    my ($res, @res);

    my $params = sub {
        my @params;
        push @params, $_[0] . '-' . get_key();
        push @params, 0 if $cas;
        push @params, $value if defined $value;
        return @params;
    };

    my $params_multi = sub {
        my @result;
        for (my $i = 0; $i < key_count; ++$i) {
            my @params;
            push @params, $_[0] . '-' . get_key();
            if ($cas or defined $value) {
                push @params, 0 if $cas;
                push @params, $value if defined $value;
                push @result, \@params;
            } else {
                push @result, @params;
            }
        }
        return @result;
    };

    my $method_multi = "${method}_multi";
    my @test = (
        "$method" => sub { $res = $new->$method(&$params('p$'))
                               foreach (1..$count * key_count) },
        "${method}_multi" . (defined $value ? ' (%h)' : '')
                => sub { $res = $new->$method_multi(&$params_multi('m%'))
                             foreach (1..$count) },
    );

    if (defined $value) {
        push @test, (
             "${method}_multi (\@a)"
                     => sub { @res = $new->$method_multi(&$params_multi('m@'))
                                  foreach (1..$count) },
        );
    }

    if (defined $value and NOWAIT) {
        # Below we call nowait_push.  Otherwise the time of gathering
        # the results would be added to the following commands.
        push @test, (
            "$method nowait"  => sub { $new->$method(&$params('pw'))
                                           foreach (1..$count * key_count);
                                       $new->nowait_push; },
            "${method}_multi nowait"
                     => sub { $new->$method_multi(&$params_multi('mw'))
                                  foreach (1..$count);
                              $new->nowait_push; },
        );
    }

    if (defined $value and NOREPLY) {
        push @test, (
            "$method noreply"  => sub { $new_noreply->$method(&$params('pr'))
                                            foreach (1..$count * key_count) },
            "${method}_multi noreply"
                     => sub { $new_noreply->$method_multi(&$params_multi('mr'))
                                  foreach (1..$count) },
        );
    }

    cmpthese(timethese(repeat, {@test}));
}


my @methods = (
    [add        => \&run, $value],
    [set        => \&run, $value],
    [append     => \&run, $value],
    [prepend    => \&run, $value],
    [replace    => \&run, $value],
    [cas        => \&run, $value, CAS],
    [get        => \&run], 
    [gets       => \&run],
    [incr       => \&run, 1],
    [decr       => \&run, 1],
    [delete     => \&run, 0],
);


print "Servers: @{[ keys %$version ]}\n";
print "Iteration count: ", $count * key_count, "/$count\n";
print 'Keys per iteration: 1/', key_count, "\n";
print 'Repeat count: ', repeat, "\n";
print 'Value size: ', length($value), " bytes\n";

srand(1);
foreach my $args (@methods) {
    my $sub = splice(@$args, 1, 1);
    &$sub(@$args);
}
