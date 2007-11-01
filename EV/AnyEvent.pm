=head1 NAME

EV::AnyEvent - anyevent adaptor for EV

=head1 SYNOPSIS

  use AnyEvent;
  use EV;

  # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't
have to do anything to make EV work with AnyEvent except by loading it
before creating the first AnyEvent watcher.

=cut

package EV::AnyEvent;

use strict;

use EV;

sub timer {
   my ($class, %arg) = @_;

   EV::timer $arg{after}, 0, $arg{cb}
}

sub io {
   my ($class, %arg) = @_;

   my $cb = $arg{cb};

   EV::io
      fileno $arg{fh},
      ($arg{poll} =~ /r/ ? EV::READ : 0) | ($arg{poll} =~ /w/ ? EV::WRITE : 0),
      sub {
         $cb->( ($_[1] & EV::READ ? "r" : "") . ($_[1] & EV::WRITE ? "w" : "") );
      }
}

sub signal {
   my ($class, %arg) = @_;

   EV::signal $arg{signal}, $arg{cb}
}

sub child {
   my ($class, %arg) = @_;

   EV::child $arg{pid}, $arg{cb}
}

sub condvar {
   bless \my $flag, "EV::AnyEvent"
}

sub broadcast {
   ${$_[0]}++;
}

sub wait {
   EV::loop EV::LOOP_ONESHOT
      while !${$_[0]};
}

sub one_event {
   EV::loop EV::LOOP_ONESHOT;
}

1;

=head1 SEE ALSO

  L<AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

