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

=item EV::DNS::init

Called automatically when the module is firts used. Uses resolv.conf
and/or some obscure win32 ibterface to initialise the nameservers and
other parameters.

=item EV::DNS::shutdown $fail_requests = 1

Shuts the DNS client down.

=item $str = EV::DNS::err_to_string $errnum

=item EV::DNS::nameserver_add $adress_as_unteger

Use unpack "N", Socket::inet_aton "address".

=item $count = EV::DNS::count_nameservers

=item int EV::DNS::clear_nameservers_and_suspend

=item int EV::DNS::resume

=item int EV::DNS::nameserver_ip_add $address

=item int EV::DNS::resolve_ipv4 $hostname, $flags, $cb->($result, $type, $ttl, @addrs);

=item int EV::DNS::resolve_ipv6 $hostname, $flags, $cb->($result, $type, $ttl, @addrs);

resolve ipv6 crashes your program in libevent versions up and including at leats 1.3e.

=item int EV::DNS::resolve_reverse $4_or_6_bytes, $flagsm $cb->($result, $type, $ttl, @domains)

=item int EV::DNS::set_option $optionname, $value, $flags

   EV::DNS::set_option "ndots:", "4"

=item int EV::DNS::resolv_conf_parse $flags, $filename

=item int EV::DNS::config_windows_nameservers

=item EV::DNS::search_clear

=item EV::DNS::search_add $domain

=item EV::DNS::search_ndots_set $ndots

=back

=cut

init;

1;

=head1 SEE ALSO

L<EV>, have a look at adnshost, too, which is nice to pipe in and out of :)

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

