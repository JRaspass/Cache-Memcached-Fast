#! /usr/bin/perl
#
use warnings;
use strict;


use FindBin;

@ARGV >= 1
    or die "Usage: $FindBin::Script HOST:PORT... [COUNT]\n";

# Note that it's better to run the test over the wire, because for
# localhost the task may become CPU bound.

my $count = ($ARGV[$#ARGV] =~ /^\d+$/ ? pop @ARGV : 100_000);

my @addrs = @ARGV;

my $max_keys = 5000;
my $keys_multi = 100;
my $value = 'x' x 40;


use Cache::Memcached::Fast;
use Cache::Memcached;
use Benchmark qw(:hireswallclock timethese cmpthese);


my $new = new Cache::Memcached::Fast {
    servers   => [@addrs],
    namespace => 'Cache::Memcached::New',
    noreply   => 1,
};


my $old = new Cache::Memcached {
    servers   => [@addrs],
    namespace => 'Cache::Memcached::Old',
};
$old->enable_compress(0);


sub compare {
    my ($method, $keys, $value, $noreply) = @_;

    my $title = "$method";
    if (defined $value) {
        use bytes;
        $title .= '(' . length($value) . ' bytes)';
    } elsif ($keys > 1) {
        $title .= "($keys keys)";
    }

    my $res;
    my @params;

    @params = map { int(rand($max_keys)) } (1 .. $keys);
    push @params, $value if defined $value;

    my @test = (
        "Old $title"  => sub { $res = $old->$method(@params) },
        "New $title"  => sub { $res = $new->$method(@params) },
    );

    @params = map { int(rand($max_keys)) } (1 .. $keys);
    push @params, $value if defined $value;

    if ($noreply) {
        push @test, (
             "Old $title noreply"  => sub { $old->$method(@params) },
             "New $title noreply"  => sub { $new->$method(@params) },
        );
    }

    cmpthese(timethese(int($count / $keys), {@test}));
}


sub compare_multi {
    my ($method, $keys) = @_;

    my $method_multi = "${method}_multi";

    my $res;
    my @params = (int(rand($max_keys)));
    my @params_multi = map { int(rand($max_keys)) } (1 .. $keys);

    my @test = (
        "Old $method x $keys"
                => sub { $res = $old->$method(@params) for (1 .. $keys) },
        "New $method x $keys"
                => sub { $res = $new->$method(@params) for (1 .. $keys) },
        "Old $method_multi($keys)"
                => sub { $res = $old->$method_multi(@params_multi) },
        "New $method_multi($keys)"
                => sub { $res = $new->$method_multi(@params_multi) },
    );

    cmpthese(timethese(int($count / $keys), {@test}));
}


my @methods = (
    [add        => \&compare, 1, $value, 1],
    [set        => \&compare, 1, $value, 1],
    [replace    => \&compare, 1, $value, 1],
    [get        => \&compare, 1],
    [get_multi  => \&compare, $keys_multi],
    [get        => \&compare_multi, $keys_multi],
    [delete     => \&compare, 1, undef, 1],
);


srand(1);
foreach my $args (@methods) {
    my $sub = splice(@$args, 1, 1);
    &$sub(@$args);
}
