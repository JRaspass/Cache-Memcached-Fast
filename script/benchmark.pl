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


# NOTE: at least on Linux (kernel 2.6.18.2) there is a certain
# artifact that affects wallclock time (but not CPU time) of some
# benchmarks: when send/receive rate changes dramatically, the system
# doesn't adopt to it right away.  Instead, for some time a lot of
# small-range ACK packets are being sent, and this increases the
# latency.  Because of this '*_multi (%h)', which comes first, has
# bigger wallclock time than '*_multi (%h)', which comes next.  I
# tried pre-warming the connection, but this doesn't help in all
# cases.  Seems like 'noreply' mode is also affected, and maybe
# 'nowait'.


use constant default_iteration_count => 1_000;
use constant key_count => 100;
use constant NOWAIT => 1;
use constant NOREPLY => 0;

my $value = 'x' x 40;


use FindBin;

@ARGV >= 1
    or die("Usage: $FindBin::Script HOST:PORT... [COUNT] [\"compare\"]\n"
           . "\n"
           . "HOST:PORT...  - list of memcached server addresses.\n"
           . "COUNT         - number of iterations (default "
                              . default_iteration_count . ").\n"
           . "                (each iteration will process "
                              . key_count . " keys).\n"
           . "\"compare\"     - literal string to enable comparison with\n"
           . "                Cache::Memcached.\n");

my $compare = ($ARGV[$#ARGV] =~ /^compare$/);
pop @ARGV if $compare;

my $count = ($ARGV[$#ARGV] =~ /^\d+$/ ? pop @ARGV : default_iteration_count);
my $max_keys = $count * key_count / 2;

my @addrs = @ARGV;

use Cache::Memcached::Fast;
use Benchmark qw(:hireswallclock timethese cmpthese timeit timesum timestr);

my $old;
my $old_method = qr/^(?:add|set|replace|incr|decr|delete|get)$/;
my $old_method_multi = qr/^get$/;
if ($compare) {
    require Cache::Memcached;

    $old = new Cache::Memcached {
        servers   => [@addrs],
        namespace => "Cache::Memcached::bench/$$/",
        connect_timeout => 5,
        select_timeout => 5,
    };
    $old->enable_compress(0);
}


my $new = new Cache::Memcached::Fast {
    servers   => [@addrs],
    namespace => "Cache::Memcached::bench/$$/",
    ketama_points => 150,
    nowait => NOWAIT,
    connect_timeout => 5,
    io_timeout => 5,
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
    connect_timeout => 5,
    io_timeout => 5,
};


sub get_key {
    int(rand($max_keys));
}


sub merge_hash {
    my ($h1, $h2) = @_;

    while (my ($k, $v) = each %$h2) {
        $h1->{$k} = $v;
    }
}


sub run {
    my ($method, $value, $cas) = @_;

    my $params = sub {
        my @params;
        push @params, $_[0] . '-' . get_key();
        push @params, 0 if $cas;
        push @params, $value if defined $value;
        return @params;
    };

    my $params_multi = sub {
        my @res;
        for (my $i = 0; $i < key_count; ++$i) {
            my @params;
            push @params, $_[0] . '-' . get_key();
            if ($cas or defined $value) {
                push @params, 0 if $cas;
                push @params, $value if defined $value;
                push @res, \@params;
            } else {
                push @res, @params;
            }
        }
        return @res;
    };

    my @test = (
        "$method" => sub { my $res = $new->$method(&$params('p$'))
                             foreach (1..key_count) },
    );

    push @test, (
        "old $method" => sub { my $res = $old->$method(&$params('o$'))
                                 foreach (1..key_count) },
    ) if defined $old and $method =~ /$old_method/o;

    if (defined $value and NOREPLY) {
        push @test, (
            "$method noreply" => sub { $new_noreply->$method(&$params('pr'))
                                         foreach (1..key_count) },
        );

        push @test, (
            "old $method noreply" => sub { $old->$method(&$params('or'))
                                             foreach (1..key_count) },
        ) if defined $old and $method =~ /$old_method/o;
    }

    my $bench = timethese($count, {@test});

    if (defined $value and NOWAIT) {
        my $title = "$method nowait";
        print "Benchmark: timing $count iterations of $title...\n";
        my $b1 = timeit($count, sub { $new->$method(&$params('pw'))
                                        foreach (1..key_count) });

        # We call nowait_push here.  Otherwise the time of gathering
        # the results would be added to the following commands.
        my $b2 = timeit(1, sub { $new->nowait_push });

        my $res = timesum($b1, $b2);
        print "$title: ", timestr($res, 'auto'), "\n";

        merge_hash($bench, { $title => $res });
    }

    my $method_multi = "${method}_multi";
    @test = (
        "$method_multi" . (defined $value ? ' (%h)' : '')
            => sub { my $res = $new->$method_multi(&$params_multi('m%')) },
    );

    # We use the same 'm%' prefix here as for the new module because
    # old module doesn't have set_multi, and we want to retrieve
    # something.
    push @test, (
        "old $method_multi"
            => sub { my $res = $old->$method_multi(&$params_multi('m%')) },
    ) if defined $old and $method =~ /$old_method_multi/o;

    push @test, (
        "$method_multi (\@a)"
             => sub { my @res = $new->$method_multi(&$params_multi('m@')) },
    ) if defined $value;

    if (defined $value and NOREPLY) {
        push @test, (
            "$method_multi noreply"
                => sub { $new_noreply->$method_multi(&$params_multi('mr')) },
        );
    }

    merge_hash($bench, timethese($count, {@test}));

    if (defined $value and NOWAIT) {
        my $title = "$method_multi nowait";
        print "Benchmark: timing $count iterations of $title...\n";
        my $b1 = timeit($count,
                        sub { $new->$method_multi(&$params_multi('mw')) });

        # We call nowait_push here.  Otherwise the time of gathering
        # the results would be added to the following commands.
        my $b2 = timeit(1, sub { $new->nowait_push });

        my $res = timesum($b1, $b2);
        print "$title: ", timestr($res, 'auto'), "\n";

        merge_hash($bench, { $title => $res });
    }

    cmpthese($bench);
}


my @methods = (
    [add        => \&run, $value],
    [set        => \&run, $value],
    [append     => \&run, $value],
    [prepend    => \&run, $value],
    [replace    => \&run, $value],
    [cas        => \&run, $value, 'CAS'],
    [get        => \&run], 
    [gets       => \&run],
    [incr       => \&run, 1],
    [decr       => \&run, 1],
    [delete     => \&run, 0],
);


print "Servers: @{[ keys %$version ]}\n";
print "Iteration count: $count\n";
print 'Keys per iteration: ', key_count, "\n";
print 'Value size: ', length($value), " bytes\n";

srand(1);
foreach my $args (@methods) {
    my $sub = splice(@$args, 1, 1);
    &$sub(@$args);
}
