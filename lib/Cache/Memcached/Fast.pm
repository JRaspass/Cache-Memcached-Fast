# See the end of the file for copyright and license.
#

package Cache::Memcached::Fast;

use 5.006;
use strict;
use warnings;


=head1 NAME

Cache::Memcached::Fast - Perl client for B<memcached>, in C language

=head1 VERSION

Version 0.21.

=cut

our $VERSION = '0.21';


=head1 SYNOPSIS

  use Cache::Memcached::Fast;

  my $memd = new Cache::Memcached::Fast({
      servers => [ { address => 'localhost:11211', weight => 2.5 },
                   '192.168.254.2:11211',
                   { address => '/path/to/unix.sock', noreply => 1 } ],
      namespace => 'my:',
      connect_timeout => 0.2,
      io_timeout => 0.5,
      close_on_error => 1,
      compress_threshold => 100_000,
      compress_ratio => 0.9,
      compress_methods => [ \&IO::Compress::Gzip::gzip,
                            \&IO::Uncompress::Gunzip::gunzip ],
      max_failures => 3,
      failure_timeout => 2,
      ketama_points => 150,
      nowait => 1,
      hash_namespace => 1,
      serialize_methods => [ \&Storable::freeze, \&Storable::thaw ],
      utf8 => ($^V ge v5.8.1 ? 1 : 0),
      max_size => 512 * 1024,
  });

  # Get server versions.
  my $versions = $memd->server_versions;
  while (my ($server, $version) = each %$versions) {
      #...
  }

  # Store scalars.
  $memd->add('skey', 'text');
  $memd->add_multi(['skey2', 'text2'], ['skey3', 'text3', 10]);

  $memd->replace('skey', 'val');
  $memd->replace_multi(['skey2', 'val2'], ['skey3', 'val3']);

  $memd->set('nkey', 5);
  $memd->set_multi(['nkey2', 10], ['skey3', 'text', 5]);

  # Store arbitrary Perl data structures.
  my %hash = (a => 1, b => 2);
  my @list = (1, 2);
  $memd->set('hash', \%hash);
  $memd->set_multi(['scalar', 1], ['list', \@list]);

  # Add to strings.
  $memd->prepend('skey', 'This is a ');
  $memd->prepend_multi(['skey2', 'This is a '], ['skey3', 'prefix ']);
  $memd->append('skey', 'ue.');
  $memd->append_multi(['skey2', 'ue.'], ['skey3', ' suffix']);

  # Do arithmetic.
  $memd->incr('nkey', 10);
  print "OK\n" if $memd->decr('nkey', 3) == 12;

  my @counters = qw(c1 c2);
  $memd->set_multi(map { [$_, 0] } @counters, 'c3', 'c4');
  $memd->incr_multi(['c3', 2], @counters, ['c4', 10]);

  # Retrieve values.
  my $val = $memd->get('skey');
  print "OK\n" if $val eq 'This is a value.';
  my $href = $memd->get_multi('hash', 'nkey');
  print "OK\n" if $href->{hash}->{b} == 2 and $href->{nkey} == 12;

  # Do atomic test-and-set operations.
  my $cas_val = $memd->gets('nkey');
  $$cas_val[1] = 0 if $$cas_val[1] == 12;
  if ($memd->cas('nkey', @$cas_val)) {
      print "OK, value updated\n";
  } else {
      print "Update failed, probably another client"
          . " has updated the value\n";
  }

  # Delete some data.
  $memd->delete('skey');

  my @keys = qw(k1 k2 k3);
  $memd->delete_multi(@keys);

  # Wait for all commands that were executed in nowait mode.
  $memd->nowait_push;

  # Wipe out all cached data.
  $memd->flush_all;


=head1 DESCRIPTION

B<Cache::Memcached::Fast> is a Perl client for B<memcached>, a memory
cache daemon (L<http://www.danga.com/memcached/>).  Module core is
implemented in C and tries hard to minimize number of system calls and
to avoid any key/value copying for speed.  As a result, it has very
low CPU consumption.

API is largely compatible with L<Cache::Memcached|Cache::Memcached>,
original pure Perl client, most users of the original module may start
using this module by installing it and adding I<"::Fast"> to the old
name in their scripts (see L</"Compatibility with Cache::Memcached">
below for full details).


=cut


use Carp;
use Storable;

require XSLoader;
XSLoader::load('Cache::Memcached::Fast', $VERSION);


=head1 CONSTRUCTOR

=over

=item C<new>

  my $memd = new Cache::Memcached::Fast($params);

Create new client object.  I<$params> is a reference to a hash with
client parameters.  Currently recognized keys are:

=over

=item I<servers>

  servers => [ { address => 'localhost:11211', weight => 2.5 },
               '192.168.254.2:11211',
               { address => '/path/to/unix.sock', noreply => 1 } ],
  (default: none)

The value is a reference to an array of server addresses.  Each
address is either a scalar, a hash reference, or an array reference
(for compatibility with Cache::Memcached, deprecated).  If hash
reference, the keys are I<address> (scalar), I<weight> (positive
rational number), and I<noreply> (boolean flag).  The server address
is in the form I<host:port> for network TCP connections, or
F</path/to/unix.sock> for local Unix socket connections.  When weight
is not given, 1 is assumed.  Client will distribute keys across
servers proportionally to server weights.

If you want to get key distribution compatible with Cache::Memcached,
all server weights should be integer, and their sum should be less
than 32768.

When I<noreply> is enabled, commands executed in a void context will
instruct the server to not send the reply.  Compare with L</nowait>
below.  B<memcached> server implements I<noreply> starting with
version 1.2.5.  If you enable I<noreply> for earlier server versions,
things will go wrongly, and the client will eventually block.  Use
with care.


=item I<namespace>

  namespace => 'my::'
  (default: '')

The value is a scalar that will be prepended to all key names passed
to the B<memcached> server.  By using different namespaces clients
avoid interference with each other.


=item I<hash_namespace>

  hash_namespace => 1
  (default: disabled)

The value is a boolean which enables (true) or disables (false) the
hashing of the namespace key prefix.  By default for compatibility
with B<Cache::Memcached> namespace prefix is not hashed along with the
key.  Thus

  namespace => 'prefix/',
  ...
  $memd->set('key', $val);

may use different B<memcached> server than

  namespace => '',
  ...
  $memd->set('prefix/key', $val);

because hash values of I<'key'> and I<'prefix/key'> may be different.

However sometimes is it necessary to hash the namespace prefix, for
instance for interoperability with other clients that do not have the
notion of the namespace.  When I<hash_namespace> is enabled, both
examples above will use the same server, the one that I<'prefix/key'>
is mapped to.  Note that there's no performance penalty then, as
namespace prefix is hashed only once.  See L</namespace>.


=item I<nowait>

  nowait => 1
  (default: disabled)

The value is a boolean which enables (true) or disables (false)
I<nowait> mode.  If enabled, when you call a method that only returns
its success status (like L</set>), B<I<in a void context>>, it sends
the request to the server and returns immediately, not waiting the
reply.  This avoids the round-trip latency at a cost of uncertain
command outcome.

Internally there is a counter of how many outstanding replies there
should be, and on any command the client reads and discards any
replies that have already arrived.  When you later execute some method
in a non-void context, all outstanding replies will be waited for, and
then the reply for this command will be read and returned.


=item I<connect_timeout>

  connect_timeout => 0.7
  (default: 0.25 seconds)

The value is a non-negative rational number of seconds to wait for
connection to establish.  Applies only to network connections.  Zero
disables timeout, but keep in mind that operating systems have their
own heuristic connect timeout.

Note that network connect process consists of several steps:
destination host address lookup, which may return several addresses in
general case (especially for IPv6, see
L<http://people.redhat.com/drepper/linux-rfc3484.html> and
L<http://people.redhat.com/drepper/userapi-ipv6.html>), then the
attempt to connect to one of those addresses.  I<connect_timeout>
applies only to one such connect, i.e. to one I<connect(2)>
call.  Thus overall connect process may take longer than
I<connect_timeout> seconds, but this is unavoidable.


=item I<io_timeout> (or deprecated I<select_timeout>)

  io_timeout => 0.5
  (default: 1.0 seconds)

The value is a non-negative rational number of seconds to wait before
giving up on communicating with the server(s).  Zero disables timeout.

Note that for commands that communicate with more than one server
(like L</get_multi>) the timeout applies per server set, not per each
server.  Thus it won't expire if one server is quick enough to
communicate, even if others are silent.  But if some servers are dead
those alive will finish communication, and then dead servers would
timeout.


=item I<close_on_error>

  close_on_error => 0
  (default: enabled)

The value is a boolean which enables (true) or disables (false)
I<close_on_error> mode.  When enabled, any error response from the
B<memcached> server would make client close the connection.  Note that
such "error response" is different from "negative response".  The
latter means the server processed the command and yield negative
result.  The former means the server failed to process the command for
some reason.  I<close_on_error> is enabled by default for safety.
Consider the following scenario:

=over

=item 1 Client want to set some value, but mistakenly sends malformed
        command (this can't happen with current module of course ;)):

  set key 10\r\n
  value_data\r\n

=item 2 Memcached server reads first line, 'set key 10', and can't
        parse it, because there's wrong number of tokens in it.  So it
        sends

  ERROR\r\n

=item 3 Then the server reads 'value_data' while it is in
        accept-command state!  It can't parse it either (hopefully),
        and sends another

  ERROR\r\n

=back

But the client expects one reply per command, so after sending the
next command it will think that the second 'ERROR' is a reply for this
new command.  This means that all replies will shift, including
replies for L</get> commands!  By closing the connection we eliminate
such possibility.

When connection dies, or the client receives the reply that it can't
understand, it closes the socket regardless the I<close_on_error>
setting.


=item I<compress_threshold>

  compress_threshold => 10_000
  (default: -1)

The value is an integer.  When positive it denotes the threshold size
in bytes: data with the size equal or larger than this should be
compressed.  See L</compress_ratio> and L</compress_methods> below.

Negative value disables compression.


=item I<compress_ratio>

  compress_ratio => 0.9
  (default: 0.8)

The value is a fractional number between 0 and 1.  When
L</compress_threshold> triggers the compression, compressed size
should be less or equal to S<(original-size * I<compress_ratio>)>.
Otherwise the data will be stored uncompressed.


=item I<compress_methods>

  compress_methods => [ \&IO::Compress::Gzip::gzip,
                        \&IO::Uncompress::Gunzip::gunzip ]
  (default: [ sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
              sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) } ]
   when Compress::Zlib is available)

The value is a reference to an array holding two code references for
compression and decompression routines respectively.

Compression routine is called when the size of the I<$value> passed to
L</set> method family is greater than or equal to
L</compress_threshold> (also see L</compress_ratio>).  The fact that
compression was performed is remembered along with the data, and
decompression routine is called on data retrieval with L</get> method
family.  The interface of these routines should be the same as for
B<IO::Compress> family (for instance see
L<IO::Compress::Gzip::gzip|IO::Compress::Gzip/gzip> and
L<IO::Uncompress::Gunzip::gunzip|IO::Uncompress::Gunzip/gunzip>).
I.e. compression routine takes a reference to scalar value and a
reference to scalar where compressed result will be stored.
Decompression routine takes a reference to scalar with compressed data
and a reference to scalar where uncompressed result will be stored.
Both routines should return true on success, and false on error.

By default we use L<Compress::Zlib|Compress::Zlib> because as of this
writing it appears to be much faster than
L<IO::Uncompress::Gunzip|IO::Uncompress::Gunzip>.


=item I<max_failures>

  max_failures => 3
  (default: 0)

The value is a non-negative integer.  When positive, if there happened
I<max_failures> in I<failure_timeout> seconds, the client does not try
to connect to this particular server for another I<failure_timeout>
seconds.  Value of zero disables this behaviour.


=item I<failure_timeout>

  failure_timeout => 30
  (default: 10 seconds)

The value is a positive integer number of seconds.  See
L</max_failures>.


=item I<ketama_points>

  ketama_points => 150
  (default: 0)

The value is a non-negative integer.  When positive, enables the
B<Ketama> consistent hashing algorithm
(L<http://www.last.fm/user/RJ/journal/2007/04/10/392555/>), and
specifies the number of points the server with weight 1 will be mapped
to.  Thus each server will be mapped to S<I<ketama_points> *
I<weight>> points in continuum.  Larger value will result in more
uniform distribution.  Note that the number of internal bucket
structures, and hence memory consumption, will be proportional to sum
of such products.  But bucket structures themselves are small (two
integers each), so you probably shouldn't worry.

Zero value disables the Ketama algorithm.  See also server weight in
L</servers> above.


=item I<serialize_methods>

  serialize_methods => [ \&Storable::freeze, \&Storable::thaw ],
  (default: [ \&Storable::nfreeze, \&Storable::thaw ])

The value is a reference to an array holding two code references for
serialization and deserialization routines respectively.

Serialization routine is called when the I<$value> passed to L</set>
method family is a reference.  The fact that serialization was
performed is remembered along with the data, and deserialization
routine is called on data retrieval with L</get> method family.  The
interface of these routines should be the same as for
L<Storable::nfreeze|Storable/nfreeze> and
L<Storable::thaw|Storable/thaw>.  I.e. serialization routine takes a
reference and returns a scalar string; it should not fail.
Deserialization routine takes scalar string and returns a reference;
if deserialization fails (say, wrong data format) it should throw an
exception (call I<die>).  The exception will be caught by the module
and L</get> will then pretend that the key hasn't been found.


=item I<utf8> (B<experimental, Perl 5.8.1 and later>)

  utf8 => 1
  (default: disabled)

The value is a boolean which enables (true) or disables (false) the
conversion of Perl character strings to octet sequences in UTF-8
encoding on store, and the reverse conversion on fetch (when the
retrieved data is marked as being UTF-8 octet sequence).  See
L<perlunicode|perlunicode>.


=item I<max_size>

  max_size => 512 * 1024
  (default: 1024 * 1024)

The value is a maximum size of an item to be stored in memcached.
When trying to set a key to a value longer than I<max_size> bytes
(after serialization and compression) nothing is sent to the server,
and I<set> methods return I<undef>.

Note that the real maximum on the server is less than 1MB, and depends
on key length among other things.  So some values in the range
S<I<[1MB - N bytes, 1MB]>>, where N is several hundreds, will still be
sent to the server, and rejected there.  You may set I<max_size> to a
smaller value to avoid this.


=item I<check_args>

  check_args => 'skip'
  (default: not 'skip')

The value is a string.  Currently the only recognized string is
I<'skip'>.

By default all constructor parameter names are checked to be
recognized, and a warning is given for unknown parameter.  This will
catch spelling errors that otherwise might go unnoticed.

When set to I<'skip'>, the check will be bypassed.  This may be
desired when you share the same argument hash among different client
versions, or among different clients.


=back

=back

=cut

our %known_params = (
    servers => [ { address => 1, weight => 1, noreply => 1 } ],
    namespace => 1,
    nowait => 1,
    hash_namespace => 1,
    connect_timeout => 1,
    io_timeout => 1,
    select_timeout => 1,
    close_on_error => 1,
    compress_threshold => 1,
    compress_ratio => 1,
    compress_methods => 1,
    compress_algo => sub {
        carp "compress_algo has been removed in 0.08,"
          . " use compress_methods instead"
    },
    max_failures => 1,
    failure_timeout => 1,
    ketama_points => 1,
    serialize_methods => 1,
    utf8 => 1,
    max_size => 1,
    check_args => 1,
);


sub _check_args {
    my ($checker, $args, $level) = @_;

    $level = 0 unless defined $level;

    my @unknown;

    if (ref($args) ne 'HASH') {
        if (ref($args) eq 'ARRAY' and ref($checker) eq 'ARRAY') {
            foreach my $v (@$args) {
                push @unknown, _check_args($checker->[0], $v, $level + 1);
            }
        }
        return @unknown;
    }

    if (exists $args->{check_args}
        and lc($args->{check_args}) eq 'skip') {
        return;
    }

    while (my ($k, $v) = each %$args) {
        if (exists $checker->{$k}) {
            if (ref($checker->{$k}) eq 'CODE') {
                $checker->{$k}->($args, $k, $v);
            } elsif (ref($checker->{$k})) {
                push @unknown, _check_args($checker->{$k}, $v, $level + 1);
            }
        } else {
            push @unknown, $k;
        }
    }

    if ($level > 0) {
        return @unknown;
    } else {
        carp "Unknown parameter: @unknown" if @unknown;
    }
}


our %instance;

sub new {
    my Cache::Memcached::Fast $class = shift;
    my ($conf) = @_;

    _check_args(\%known_params, $conf);

    if (not $conf->{compress_methods}
        and defined $conf->{compress_threshold}
        and $conf->{compress_threshold} >= 0
        and eval "require Compress::Zlib") {
        # Note that the functions below can't return false when
        # operation succeed.  This is because "" and "0" compress to a
        # longer values (because of additional format data), and
        # compress_ratio will force them to be stored uncompressed,
        # thus decompression will never return them.
        $conf->{compress_methods} = [
            sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
            sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) }
        ];
    }

    if ($conf->{utf8} and $^V lt v5.8.1) {
        carp "'utf8' may be enabled only for Perl >= 5.8.1, disabled";
        undef $conf->{utf8};
    }

    $conf->{serialize_methods} ||= [ \&Storable::nfreeze, \&Storable::thaw ];

    my $memd = Cache::Memcached::Fast::_new($class, $conf);

    if (eval "require Scalar::Util") {
        my $context = [$memd, $conf];
        Scalar::Util::weaken($context->[0]);
        $instance{$$memd} = $context;
    }

    return $memd;
}


sub CLONE {
    my ($class) = @_;

    my @contexts = values %instance;
    %instance = ();
    foreach my $context (@contexts) {
        my $memd = Cache::Memcached::Fast::_new($class, $context->[1]);
        ${$context->[0]} = $$memd;
        $instance{$$memd} = $context;
        $$memd = 0;
    }
}


sub DESTROY {
    my ($memd) = @_;

    return unless $$memd;

    delete $instance{$$memd};

    Cache::Memcached::Fast::_destroy($memd);
}


=head1 METHODS

=over

=item C<enable_compress>

  $memd->enable_compress($enable);

Enable compression when boolean I<$enable> is true, disable when
false.

Note that you can enable compression only when you set
L</compress_threshold> to some positive value and L</compress_methods>
is set.

I<Return:> none.

=cut

# See Fast.xs.


=item C<namespace>

  $memd->namespace;
  $memd->namespace($string);

Without the argument return the current namespace prefix.  With the
argument set the namespace prefix to I<$string>, and return the old
prefix.

I<Return:> scalar, the namespace prefix that was in effect before the
call.

=cut

# See Fast.xs.


=item C<set>

  $memd->set($key, $value);
  $memd->set($key, $value, $expiration_time);

Store the I<$value> on the server under the I<$key>.  I<$key> should
be a scalar.  I<$value> should be defined and may be of any Perl data
type.  When it is a reference, the referenced Perl data structure will
be transparently serialized by routines specified with
L</serialize_methods>, which see.

Optional I<$expiration_time> is a positive integer number of seconds
after which the value will expire and wouldn't be accessible any
longer.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<set_multi>

  $memd->set_multi(
      [$key, $value],
      [$key, $value, $expiration_time],
      ...
  );

Like L</set>, but operates on more than one key.  Takes the list of
references to arrays each holding I<$key>, I<$value> and optional
I<$expiration_time>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</set> to
learn what the result value is.

=cut

# See Fast.xs.


=item C<cas>

  $memd->cas($key, $cas, $value);
  $memd->cas($key, $cas, $value, $expiration_time);

Store the I<$value> on the server under the I<$key>, but only if CAS
(I<Consistent Access Storage>) value associated with this key is equal
to I<$cas>.  I<$cas> is an opaque object returned with L</gets> or
L</gets_multi>.

See L</set> for I<$key>, I<$value>, I<$expiration_time> parameters
description.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.  Thus if the key
exists on the server, false would mean that some other client has
updated the value, and L</gets>, L</cas> command sequence should be
repeated.

B<cas> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<cas_multi>

  $memd->cas_multi(
      [$key, $cas, $value],
      [$key, $cas, $value, $expiration_time],
      ...
  );

Like L</cas>, but operates on more than one key.  Takes the list of
references to arrays each holding I<$key>, I<$cas>, I<$value> and
optional I<$expiration_time>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</cas> to
learn what the result value is.

B<cas> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<add>

  $memd->add($key, $value);
  $memd->add($key, $value, $expiration_time);

Store the I<$value> on the server under the I<$key>, but only if the
key B<doesn't> exists on the server.

See L</set> for I<$key>, I<$value>, I<$expiration_time> parameters
description.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<add_multi>

  $memd->add_multi(
      [$key, $value],
      [$key, $value, $expiration_time],
      ...
  );

Like L</add>, but operates on more than one key.  Takes the list of
references to arrays each holding I<$key>, I<$value> and optional
I<$expiration_time>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</add> to
learn what the result value is.

=cut

# See Fast.xs.


=item C<replace>

 $memd->replace($key, $value);
 $memd->replace($key, $value, $expiration_time);

Store the I<$value> on the server under the I<$key>, but only if the
key B<does> exists on the server.

See L</set> for I<$key>, I<$value>, I<$expiration_time> parameters
description.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<replace_multi>

  $memd->replace_multi(
      [$key, $value],
      [$key, $value, $expiration_time],
      ...
  );

Like L</replace>, but operates on more than one key.  Takes the list
of references to arrays each holding I<$key>, I<$value> and optional
I<$expiration_time>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</replace> to
learn what the result value is.

=cut

# See Fast.xs.


=item C<append>

  $memd->append($key, $value);

B<Append> the I<$value> to the current value on the server under the
I<$key>.

I<$key> and I<$value> should be scalars, as well as current value on
the server.  C<append> doesn't affect expiration time of the value.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.

B<append> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<append_multi>

  $memd->append_multi(
      [$key, $value],
      ...
  );

Like L</append>, but operates on more than one key.  Takes the list of
references to arrays each holding I<$key>, I<$value>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</append> to
learn what the result value is.

B<append> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<prepend>

  $memd->prepend($key, $value);

B<Prepend> the I<$value> to the current value on the server under the
I<$key>.

I<$key> and I<$value> should be scalars, as well as current value on
the server.  C<prepend> doesn't affect expiration time of the value.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.

B<prepend> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<prepend_multi>

  $memd->prepend_multi(
      [$key, $value],
      ...
  );

Like L</prepend>, but operates on more than one key.  Takes the list
of references to arrays each holding I<$key>, I<$value>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</prepend> to
learn what the result value is.

B<prepend> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<get>

  $memd->get($key);

Retrieve the value for a I<$key>.  I<$key> should be a scalar.

I<Return:> value associated with the I<$key>, or nothing.

=cut

# See Fast.xs.


=item C<get_multi>

  $memd->get_multi(@keys);

Retrieve several values associated with I<@keys>.  I<@keys> should be
an array of scalars.

I<Return:> reference to hash, where I<$href-E<gt>{$key}> holds
corresponding value.

=cut

# See Fast.xs.


=item C<gets>

  $memd->gets($key);

Retrieve the value and its CAS for a I<$key>.  I<$key> should be a
scalar.

I<Return:> reference to an array I<[$cas, $value]>, or nothing.  You
may conveniently pass it back to L</cas> with I<@$res>:

  my $cas_val = $memd->gets($key);
  # Update value.
  if (defined $cas_val) {
      $$cas_val[1] = 3;
      $memd->cas($key, @$cas_val);
  }

B<gets> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<gets_multi>

  $memd->gets_multi(@keys);

Retrieve several values and their CASs associated with I<@keys>.
I<@keys> should be an array of scalars.

I<Return:> reference to hash, where I<$href-E<gt>{$key}> holds a
reference to an array I<[$cas, $value]>.  Compare with L</gets>.

B<gets> command first appeared in B<memcached> 1.2.4.

=cut

# See Fast.xs.


=item C<incr>

  $memd->incr($key);
  $memd->incr($key, $increment);

Increment the value for the I<$key>.  Starting with B<memcached> 1.3.3
I<$key> should be set to a number or the command will fail.  An
optional I<$increment> should be a positive integer, when not given 1
is assumed.  Note that the server doesn't check for overflow.

I<Return:> unsigned integer, new value for the I<$key>, or false for
negative server reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<incr_multi>

  $memd->incr_multi(
      @keys,
      [$key],
      [$key, $increment],
      ...
  );

Like L</incr>, but operates on more than one key.  Takes the list of
keys and references to arrays each holding I<$key> and optional
I<$increment>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</incr> to
learn what the result value is.

=cut

# See Fast.xs.


=item C<decr>

  $memd->decr($key);
  $memd->decr($key, $decrement);

Decrement the value for the I<$key>.  Starting with B<memcached> 1.3.3
I<$key> should be set to a number or the command will fail.  An
optional I<$decrement> should be a positive integer, when not given 1
is assumed.  Note that the server I<does> check for underflow, attempt
to decrement the value below zero would set the value to zero.
Similar to L<DBI|DBI>, zero is returned as I<"0E0">, and evaluates to
true in a boolean context.

I<Return:> unsigned integer, new value for the I<$key>, or false for
negative server reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<decr_multi>

  $memd->decr_multi(
      @keys,
      [$key],
      [$key, $decrement],
      ...
  );

Like L</decr>, but operates on more than one key.  Takes the list of
keys and references to arrays each holding I<$key> and optional
I<$decrement>.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</decr> to
learn what the result value is.

=cut

# See Fast.xs.


=item C<delete>

  $memd->delete($key);

Delete I<$key> and its value from the cache.

I<Return:> boolean, true for positive server reply, false for negative
server reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<remove> (B<deprecated>)

Alias for L</delete>, for compatibility with B<Cache::Memcached>.

=cut

*remove = \&delete;


=item C<delete_multi>

  $memd->delete_multi(@keys);

Like L</delete>, but operates on more than one key.  Takes the list of
keys.

Note that multi commands are not all-or-nothing, some operations may
succeed, while others may fail.

I<Return:> in list context returns the list of results, each
I<$list[$index]> is the result value corresponding to the argument at
position I<$index>.  In scalar context, hash reference is returned,
where I<$href-E<gt>{$key}> holds the result value.  See L</delete> to
learn what the result value is.

=cut

# See Fast.xs.


=item C<flush_all>

  $memd->flush_all;
  $memd->flush_all($delay);

Flush all caches the client knows about.  This command invalidates all
items in the caches, none of them will be returned on subsequent
retrieval command.  I<$delay> is an optional non-negative integer
number of seconds to delay the operation.  The delay will be
distributed across the servers.  For instance, when you have three
servers, and call C<flush_all(30)>, the servers would get 30, 15, 0
seconds delays respectively.  When omitted, zero is assumed,
i.e. flush immediately.

I<Return:> reference to hash, where I<$href-E<gt>{$server}> holds
corresponding result value.  I<$server> is either I<host:port> or
F</path/to/unix.sock>, as described in L</servers>.  Result value is a
boolean, true for positive server reply, false for negative server
reply, or I<undef> in case of some error.

=cut

# See Fast.xs.


=item C<nowait_push>

  $memd->nowait_push;

Push all pending requests to the server(s), and wait for all replies.
When L</nowait> mode is enabled, the requests issued in a void context
may not reach the server(s) immediately (because the reply is not
waited for).  Instead they may stay in the send queue on the local
host, or in the receive queue on the remote host(s), for quite a long
time.  This method ensures that they are delivered to the server(s),
processed there, and the replies have arrived (or some error has
happened that caused some connection(s) to be closed).

Destructor will call this method to ensure that all requests are
processed before the connection is closed.

I<Return:> nothing.

=cut

# See Fast.xs.


=item C<server_versions>

  $memd->server_versions;

Get server versions.

I<Return:> reference to hash, where I<$href-E<gt>{$server}> holds
corresponding server version.  I<$server> is either I<host:port> or
F</path/to/unix.sock>, as described in L</servers>.

=cut

# See Fast.xs.


=item C<disconnect_all>

  $memd->disconnect_all;

Closes all open sockets to memcached servers.  Must be called after
L<perlfunc/fork> if the parent process has open sockets to memcacheds (as the
child process inherits the socket and thus two processes end up using the same
socket which leads to protocol errors.)

I<Return:> nothing.

=cut

# See Fast.xs.


1;

__END__

=back


=head1 Compatibility with Cache::Memcached

This module is designed to be a drop in replacement for
L<Cache::Memcached|Cache::Memcached>.  Where constructor parameters
are the same as in Cache::Memcached, the default values are also the
same, and new parameters are disabled by default (the exception is
L</close_on_error>, which is absent in Cache::Memcached and enabled by
default in this module, and L</check_args>, which see).  Internally
Cache::Memcached::Fast uses the same hash function as
Cache::Memcached, and thus should distribute the keys across several
servers the same way.  So both modules may be used interchangeably.
Most users of the original module should be able to use this module
after replacing I<"Cache::Memcached"> with
I<"Cache::Memcached::Fast">, without further code modifications.
However, as of this release, the following features of
Cache::Memcached are not supported by Cache::Memcached::Fast (and some
of them will never be):


=head2 Constructor parameters

=over

=item I<no_rehash>

Current implementation never rehashes keys, instead L</max_failures>
and L</failure_timeout> are used.

If the client would rehash the keys, a consistency problem would
arise: when the failure occurs the client can't tell whether the
server is down, or there's a (transient) network failure.  While some
clients might fail to reach a particular server, others may still
reach it, so some clients will start rehashing, while others will not,
and they will no longer agree which key goes where.


=item I<readonly>

Not supported.  Easy to add.  However I'm not sure about the demand
for it, and it will slow down things a bit (because from design point
of view it's better to add it on Perl side rather than on XS side).


=item I<debug>

Not supported.  Since the implementation is different, there can't be
any compatibility on I<debug> level.

=back


=head2 Methods

=over

=item Passing keys

Every key should be a scalar.  The syntax when key is a reference to
an array I<[$precomputed_hash, $key]> is not supported.


=item C<set_servers>

Not supported.  Server set should not change after client object
construction.


=item C<set_debug>

Not supported.  See L</debug>.


=item C<set_readonly>

Not supported.  See L</readonly>.


=item C<set_norehash>

Not supported.  See L</no_rehash>.


=item C<set_compress_threshold>

Not supported.  Easy to add.  Currently you specify
I<compress_threshold> during client object construction.


=item C<stats>

Not supported.  Perhaps will appear in the future releases.


=back


=head1 Tainted data

In current implementation tainted flag is neither tested nor
preserved, storing tainted data and retrieving it back would clear
tainted flag.  See L<perlsec|perlsec>.


=head1 Threads

This module is thread-safe when used with Perl >= 5.7.2.  As with
other Perl data each thread gets its own copy of
Cache::Memcached::Fast object that is in scope when the thread is
created.  Such copies share no state, and may be used concurrently.
For example:

  use threads;

  my $memd = new Cache::Memcached::Fast({...});

  sub thread_job {
    $memd->set("key", "thread value");
  }

  threads->new(\&thread_job);
  $memd->set("key", "main value");

Here both C<set>s will be executed concurrently, and the value of
I<key> will be either I<main value> or I<thread value>, depending on
the timing of operations.  Note that C<$memd> inside C<thread_job>
internally refers to a different Cache::Memcached::Fast object than
C<$memd> from the outer scope.  Each object has its own connections to
servers, its own counter of outstanding replies for L</nowait> mode,
etc.

New object copy is created with the same constructor arguments, but
initially is not connected to any server (even when master copy has
open connections).  No file descriptor is allocated until the command
is executed through this new object.

You may safely create Cache::Memcached::Fast object from threads other
than main thread, and/or pass them as parameters to threads::new().
However you can't return the object from top-level thread function.
I.e., the following won't work:

  use threads;

  sub thread_job {
    return new Cache::Memcached::Fast({...});
  }

  my $thread = threads->new(\&thread_job);

  my $memd = $thread->join;  # The object will be destroyed here.

This is a Perl limitation (see L<threads/"BUGS AND LIMITATIONS">).


=head1 BUGS

Please report any bugs or feature requests to
C<bug-cache-memcached-fast at rt.cpan.org>, or through the web
interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Cache-Memcached-Fast>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Cache::Memcached::Fast


You can also look for information at:

=over 4

=item * Project home

L<http://openhack.ru/Cache-Memcached-Fast>


=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Cache-Memcached-Fast>


=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Cache-Memcached-Fast>


=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Cache-Memcached-Fast>


=item * Search CPAN

L<http://search.cpan.org/dist/Cache-Memcached-Fast>


=back


=head1 SEE ALSO

L<http://openhack.ru/Cache-Memcached-Fast> - project home.  Latest
development tree can be found there.

L<Cache::Memcached|Cache::Memcached> - original pure Perl B<memcached>
client.

L<http://www.danga.com/memcached/> - B<memcached> website.


=head1 AUTHORS

S<Tomash Brechko>, C<< <tomash.brechko at gmail.com> >> - design and
implementation.

S<Michael Monashev>, C<< <postmaster at softsearch.ru> >> - project
management, design suggestions, testing.


=head1 ACKNOWLEDGEMENTS

Development of this module was sponsored by S<Monashev Co. Ltd.>

Thanks to S<Peter J. Holzer> for enlightening on UTF-8 support.

Thanks to S<Yasuhiro Matsumoto> for initial Win32 patch.


=head1 WARRANTY

There's B<NONE>, neither explicit nor implied.  But you knew it already
;).


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007-2010 Tomash Brechko.  All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
