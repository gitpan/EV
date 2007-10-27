=head1 NAME

EV::DNS - perl interface to libevent's evdns module

=head1 SYNOPSIS

 use EV::DNS;

   EV::DNS::resolve_reverse +(Socket::inet_aton "129.13.162.95"), 0, sub {
      my ($result, $type, $ttl, @ptrs) = @_;
      warn "resolves to @ptrs";
   };

   EV::DNS::resolve_ipv4 "www.goof.com", 0, sub {
      my ($result, $type, $ttl, @ptrs) = @_;
      warn "resolves to " . Socket::inet_ntoa $ptrs[0]
         if @ptrs;
   };

=head1 DESCRIPTION

This module provides an interface to libevent's evdns module, see
(L<http://monkey.org/~provos/libevent/>).

=cut

package EV::DNS;

use strict;

use EV;

=head1 FUNCTIONAL INTERFACE

TODO

=over 4

=back


=head1 BUGS

  * At least up to version 1.3e of libevent, resolve_reverse_ipv6 will
    always crash the program with an assertion failure.
  * use'ing this module will keep events registered so the event loop
    will never return unless loopexit is called.

=cut

init;

1;

=head1 SEE ALSO

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

