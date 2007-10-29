=head1 NAME

EV - perl interface to libevent, monkey.org/~provos/libevent/

=head1 SYNOPSIS

  use EV;
  
  # TIMER
  
  my $w = EV::timer 2, 0, sub {
     warn "is called after 2s";
  };
  
  my $w = EV::timer 2, 1, sub {
     warn "is called roughly every 2s (repeat = 1)";
  };
  
  undef $w; # destroy event watcher again
  
  my $w = EV::timer_abs 0, 60, sub {
     warn "is called every minute, on the minute, exactly";
  };
  
  # IO
  
  my $w = EV::io \*STDIN, EV::READ | EV::PERSIST, sub {
     my ($w, $events) = @_; # all callbacks get the watcher object and event mask
     if ($events & EV::TIMEOUT) {
        warn "nothing received on stdin for 10 seconds, retrying";
     } else {
        warn "stdin is readable, you entered: ", <STDIN>;
     }
  };
  $w->timeout (10);
  
  my $w = EV::timed_io \*STDIN, EV::READ, 30, sub {
     my ($w, $events) = @_;
     if ($_[1] & EV::TIMEOUT) {
        warn "nothing entered within 30 seconds, bye bye.\n";
        $w->stop;
     } else {
        my $line = <STDIN>;
        warn "you entered something, you again have 30 seconds.\n";
     }
  };
  
  # SIGNALS
  
  my $w = EV::signal 'QUIT', sub {
     warn "sigquit received\n";
  };
  
  my $w = EV::signal 3, sub {
     warn "sigquit received (this is GNU/Linux, right?)\n";
  };
  
  # MAINLOOP
  EV::dispatch; # loop as long as watchers are active
  EV::loop;     # the same thing
  EV::loop EV::LOOP_ONCE;     # block until some events could be handles
  EV::loop EV::LOOP_NONBLOCK; # check and handle some events, but do not wait

=head1 DESCRIPTION

This module provides an interface to libevent
(L<http://monkey.org/~provos/libevent/>). You probably should acquaint
yourself with its documentation and source code to be able to use this
module fully.

Please note thta this module disables the libevent EPOLL method by
default, see BUGS, below, if you need to enable it.

=cut

package EV;

use strict;

BEGIN {
   our $VERSION = '0.03';
   use XSLoader;
   XSLoader::load "EV", $VERSION;
}

=head1 BASIC INTERFACE

=over 4

=item $EV::NPRI

How many priority levels are available.

=item $EV::DIED

Must contain a reference to a function that is called when a callback
throws an exception (with $@ containing thr error). The default prints an
informative message and continues.

If this callback throws an exception it will be silently ignored.

=item $time = EV::now

Returns the time in (fractional) seconds since the epoch.

=item $version = EV::version

=item $method = EV::method

Return version string and event polling method used.

=item EV::loop $flags  # EV::LOOP_ONCE, EV::LOOP_ONESHOT

=item EV::loopexit $after

Exit any active loop or dispatch after C<$after> seconds or immediately if
C<$after> is missing or zero.

=item EV::dispatch

Same as C<EV::loop 0>.

=item EV::event $callback

Creates a new event watcher waiting for nothing, calling the given callback.

=item my $w = EV::io $fileno_or_fh, $eventmask, $callback

=item my $w = EV::io_ns $fileno_or_fh, $eventmask, $callback

As long as the returned watcher object is alive, call the C<$callback>
when the events specified in C<$eventmask> happen. Initially, the timeout
is disabled.

You can additionall set a timeout to occur on the watcher, but note that
this timeout will not be reset when you get an I/O event in the EV::PERSIST
case, and reaching a timeout will always stop the watcher even in the
EV::PERSIST case.

If you want a timeout to occur only after a specific time of inactivity, set
a repeating timeout and do NOT use EV::PERSIST.

Eventmask can be one or more of these constants ORed together:

  EV::READ     wait until read() wouldn't block anymore
  EV::WRITE    wait until write() wouldn't block anymore
  EV::PERSIST  stay active after a (non-timeout) event occured

The C<io_ns> variant doesn't add/start the newly created watcher.

=item my $w = EV::timed_io $fileno_or_fh, $eventmask, $timeout, $callback

=item my $w = EV::timed_io_ns $fileno_or_fh, $eventmask, $timeout, $callback

Same as C<io> and C<io_ns>, but also specifies a timeout (as if there was
a call to C<< $w->timeout ($timout, 1) >>. The persist flag is not allowed
and will automatically be cleared. The watcher will be restarted after each event.

If the timeout is zero or undef, no timeout will be set, and a normal
watcher (with the persist flag set!) will be created.

This has the effect of timing out after the specified period of inactivity
has happened.

Due to the design of libevent, this is also relatively inefficient, having
one or two io watchers and a separate timeout watcher that you reset on
activity (by calling its C<start> method) is usually more efficient.

=item my $w = EV::timer $after, $repeat, $callback

=item my $w = EV::timer_ns $after, $repeat, $callback

Calls the callback after C<$after> seconds. If C<$repeat> is true, the
timer will be restarted after the callback returns. This means that the
callback would be called roughly every C<$after> seconds, prolonged by the
time the callback takes.

The C<timer_ns> variant doesn't add/start the newly created watcher.

=item my $w = EV::timer_abs $at, $interval, $callback

=item my $w = EV::timer_abs_ns $at, $interval, $callback

Similar to EV::timer, but the time is given as an absolute point in time
(C<$at>), plus an optional C<$interval>.

If the C<$interval> is zero, then the callback will be called at the time
C<$at> if that is in the future, or as soon as possible if its in the
past. It will not automatically repeat.

If the C<$interval> is nonzero, then the watcher will always be scheduled
to time out at the next C<$at + integer * $interval> time.

This can be used to schedule a callback to run at very regular intervals,
as long as the processing time is less then the interval (otherwise
obviously events will be skipped).

Another way to think about it (for the mathematically inclined) is that
C<timer_abs> will try to tun the callback at the next possible time where
C<$time = $at (mod $interval)>, regardless of any time jumps.

The C<timer_abs_ns> variant doesn't add/start the newly created watcher.

=item my $w = EV::signal $signal, $callback

=item my $w = EV::signal_ns $signal, $callback

Call the callback when $signal is received (the signal can be specified
by number or by name, just as with kill or %SIG). Signal watchers are
persistent no natter what.

EV will grab the signal for the process (the kernel only allows one
component to receive signals) when you start a signal watcher, and
removes it again when you stop it. Pelr does the same when you add/remove
callbacks to %SIG, so watch out.

Unfortunately, only one handler can be registered per signal. Screw
libevent.

The C<signal_ns> variant doesn't add/start the newly created watcher.

=back

=head1 THE EV::Event CLASS

All EV functions creating an event watcher (designated by C<my $w =>
above) support the following methods on the returned watcher object:

=over 4

=item $w->add ($timeout)

Stops and (re-)starts the event watcher, setting the optional timeout to
the given value, or clearing the timeout if none is given.

=item $w->start

Stops and (re-)starts the event watcher without touching the timeout.

=item $w->del

=item $w->stop

Stop the event watcher if it was started.

=item $current_callback = $w->cb

=item $old_callback = $w->cb ($new_callback)

Return the previously set callback and optionally set a new one.

=item $current_fh = $w->fh

=item $old_fh = $w->fh ($new_fh)

Returns the previously set filehandle and optionally set a new one (also
clears the EV::SIGNAL flag when setting a filehandle).

=item $current_signal = $w->signal

=item $old_signal = $w->signal ($new_signal)

Returns the previously set signal number and optionally set a new one (also sets
the EV::SIGNAL flag when setting a signal).

=item $current_eventmask = $w->events

=item $old_eventmask = $w->events ($new_eventmask)

Returns the previously set event mask and optionally set a new one.

=item $w->timeout ($after, $repeat)

Resets the timeout (see C<EV::timer> for details).

=item $w->timeout_abs ($at, $interval)

Resets the timeout (see C<EV::timer_abs> for details).

=item $w->priority_set ($priority)

Set the priority of the watcher to C<$priority> (0 <= $priority < $EV::NPRI).

=back

=head1 BUGS

Lots. Libevent itself isn't well tested and rather buggy, and this module
is quite new at the moment.

Please note that the epoll method is not, in general, reliable in programs
that use fork (even if no libveent calls are being made in the forked
process). If your program behaves erratically, try setting the environment
variable C<EVENT_NOEPOLL> first when running the program.

In general, if you fork, then you can only use the EV module in one of the
children.

=cut

our $DIED = sub {
   warn "EV: error in callback (ignoring): $@";
};

our $NPRI = 4;
our $BASE = init;
priority_init $NPRI;

push @AnyEvent::REGISTRY, [EV => "EV::AnyEvent"];

1;

=head1 SEE ALSO

  L<EV::DNS>, L<event(3)>, L<event.h>, L<evdns.h>.
  L<EV::AnyEvent>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

