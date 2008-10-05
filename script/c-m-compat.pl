#! /usr/bin/perl
#
# Copyright (C) 2008 Tomash Brechko.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.8
# or, at your option, any later version of Perl 5 you may have
# available.
#
use warnings;
use strict;

# NOTE: this test uses INSTANCE_COUNT x 2 file descriptors.  This
# means that normally spawning more than ~500 instances won't work.

use FindBin;

@ARGV >= 3
  or die "Usage: $FindBin::Script MIN_PORT INSTANCE_COUNT KEY_COUNT [SEED]\n";

my ($min_port, $instance_count, $key_count, $seed) = @ARGV;
$seed = time unless defined $seed;
srand($seed);

print "Instances: $instance_count, keys: $key_count, random seed: $seed\n";

my $host = '127.3.5.7';

use Cache::Memcached::Fast;
use Cache::Memcached;

my $max_port = $min_port + $instance_count - 1;
my @children;

END {
    kill 'SIGTERM', @children;
}

foreach my $port ($min_port..$max_port) {
    my $pid = fork;
    die "Can't fork: $!\n" unless defined $pid;
    if ($pid) {
        push @children, $pid;
    } else {
        exec('memcached', '-p', $port, '-m1') == 0
          or die "Can't exec memcached on $host:$port: $!\n";
    }
}

# Give memcached servers some time to become ready.
sleep(1);

my @addrs = map { "$host:$_" } ($min_port..$max_port);

my $cm = new Cache::Memcached({ servers => \@addrs,
                                select_timeout => 2 });
my $cmf = new Cache::Memcached::Fast({ servers => \@addrs,
                                       select_timeout => 2 });

foreach my $i (1..$key_count) {
    my $key = int(rand($key_count));
    $cmf->set($key, $i) or die "Can't set key $key\n";
    my $res = $cm->get($key);
    die "Fetch failed for key $key ($i), got @{[ defined $res
                                                 ? $res : '(undef)' ]}\n"
      unless defined $res and $res == $i;
}
