# Cache::Memcached::Fast

[![Coverage Status](https://coveralls.io/repos/github/JRaspass/Cache-Memcached-Fast/badge.svg?branch=master)](https://coveralls.io/github/JRaspass/Cache-Memcached-Fast?branch=master)

[Cache::Memcached::Fast] is a [Perl] client for [memcached], a memory cache
daemon. Module core is implemented in C and tries hard to minimize the number
of system calls and to avoid any key/value copying for speed. As a result, it
has very low CPU consumption.

API is largely compatible with [Cache::Memcached], the original pure Perl
client, most users of the original module may start using this module by
installing it and adding "::Fast" to the old name in their scripts (see
"Compatibility with Cache::Memcached" section in the module documentation for
full details).

The module does not depend on any external library, it contains custom
memcached client implementation in C designed for efficient interaction with
Perl (actually client code has well defined generic API and may be used by
itself).

The module should compile and work on any Unix-derived system. Win32 support
is based on the patch by Yasuhiro Matsumoto---thanks!, and is (expected to be)
supported by community. Note: on Win32 below Windows Vista max number of
memcached servers is 64. See comment on FD_SETSIZE in src/socket_win32.h to
learn how to increase this value if you need to connect to more than 64
servers.

Despite the low version number (which mainly reflects release history) the
module is considered to be beta (see BUGS below on how to report bugs).
See "Compatibility with Cache::Memcached" section in the module documentation
for the description of what is missing compared to Cache::Memcached.

## INSTALLATION

To install this module type the following:

    perl Makefile.PL
    make
    make test
    make install

Don't forget to start the memcached daemon on local host port 11211 (the
default) before running `make test`.

## DOCUMENTATION

You can find documentation for this module on [CPAN][Cache::Memcached::Fast].
Or, after installing, with the perldoc command:

    perldoc Cache::Memcached::Fast

## BUGS

Please report any bugs or feature requests to bug-cache-memcached-fast at
rt.cpan.org, or through the web interface at
http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Cache-Memcached-Fast.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

## COPYRIGHT AND LICENCE

Copyright (C) 2007-2010 Tomash Brechko. All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself, either Perl version 5.8.8 or, at your option,
any later version of Perl 5 you may have available.

When C client is used as a standalone library:

This library is free software; you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the Free
Software Foundation; either version 2.1 of the License, or (at your option)
any later version.

This library is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
details.

[Cache::Memcached::Fast]: https://metacpan.org/pod/Cache::Memcached::Fast
[Cache::Memcached]:       https://metacpan.org/pod/Cache::Memcached
[Perl]:                   https://www.perl.org
[memcached]:              https://memcached.org
