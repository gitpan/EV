=head1 NAME

EV - perl interface to libev, a high performance full-featured event loop

=head1 SYNOPSIS

  use EV;
  
  # TIMERS
  
  my $w = EV::timer 2, 0, sub {
     warn "is called after 2s";
  };
  
  my $w = EV::timer 2, 2, sub {
     warn "is called roughly every 2s (repeat = 2)";
  };
  
  undef $w; # destroy event watcher again
  
  my $w = EV::periodic 0, 60, 0, sub {
     warn "is called every minute, on the minute, exactly";
  };
  
  # IO
  
  my $w = EV::io *STDIN, EV::READ, sub {
     my ($w, $revents) = @_; # all callbacks receive the watcher and event mask
     warn "stdin is readable, you entered: ", <STDIN>;
  };
  
  # SIGNALS
  
  my $w = EV::signal 'QUIT', sub {
     warn "sigquit received\n";
  };
  
  # CHILD/PID STATUS CHANGES

  my $w = EV::child 666, sub {
     my ($w, $revents) = @_;
     my $status = $w->rstatus;
  };

  # STAT CHANGES
  my $w = EV::stat "/etc/passwd", 10, sub {
     my ($w, $revents) = @_;
     warn $w->path, " has changed somehow.\n";
  };
  
  # MAINLOOP
  EV::loop;           # loop until EV::unloop is called or all watchers stop
  EV::loop EV::LOOP_ONESHOT;  # block until at least one event could be handled
  EV::loop EV::LOOP_NONBLOCK; # try to handle same events, but do not block

=head1 DESCRIPTION

This module provides an interface to libev
(L<http://software.schmorp.de/pkg/libev.html>). While the documentation
below is comprehensive, one might also consult the documentation of libev
itself (L<http://cvs.schmorp.de/libev/ev.html>) for more subtle details on
watcher semantics or some discussion on the available backends, or how to
force a specific backend with C<LIBEV_FLAGS>.

=cut

package EV;

use strict;

BEGIN {
   our $VERSION = '1.5';
   use XSLoader;
   XSLoader::load "EV", $VERSION;
}

@EV::IO::ISA       =
@EV::Timer::ISA    =
@EV::Periodic::ISA =
@EV::Signal::ISA   =
@EV::Child::ISA    =
@EV::Stat::ISA     =
@EV::Idle::ISA     =
@EV::Prepare::ISA  =
@EV::Check::ISA    =
@EV::Embed::ISA    =
@EV::Fork::ISA     =
   "EV::Watcher";

=head1 BASIC INTERFACE

=over 4

=item $EV::DIED

Must contain a reference to a function that is called when a callback
throws an exception (with $@ containing thr error). The default prints an
informative message and continues.

If this callback throws an exception it will be silently ignored.

=item $time = EV::time

Returns the current time in (fractional) seconds since the epoch.

=item $time = EV::now

Returns the time the last event loop iteration has been started. This
is the time that (relative) timers are based on, and refering to it is
usually faster then calling EV::time.

=item $method = EV::method

Returns an integer describing the backend used by libev (EV::METHOD_SELECT
or EV::METHOD_EPOLL).

=item EV::loop [$flags]

Begin checking for events and calling callbacks. It returns when a
callback calls EV::unloop.

The $flags argument can be one of the following:

   0                  as above
   EV::LOOP_ONESHOT   block at most once (wait, but do not loop)
   EV::LOOP_NONBLOCK  do not block at all (fetch/handle events but do not wait)

=item EV::unloop [$how]

When called with no arguments or an argument of EV::UNLOOP_ONE, makes the
innermost call to EV::loop return.

When called with an argument of EV::UNLOOP_ALL, all calls to EV::loop will return as
fast as possible.

=item EV::once $fh_or_undef, $events, $timeout, $cb->($revents)

This function rolls together an I/O and a timer watcher for a single
one-shot event without the need for managing a watcher object.

If C<$fh_or_undef> is a filehandle or file descriptor, then C<$events>
must be a bitset containing either C<EV::READ>, C<EV::WRITE> or C<EV::READ
| EV::WRITE>, indicating the type of I/O event you want to wait for. If
you do not want to wait for some I/O event, specify C<undef> for
C<$fh_or_undef> and C<0> for C<$events>).

If timeout is C<undef> or negative, then there will be no
timeout. Otherwise a EV::timer with this value will be started.

When an error occurs or either the timeout or I/O watcher triggers, then
the callback will be called with the received event set (in general
you can expect it to be a combination of C<EV:ERROR>, C<EV::READ>,
C<EV::WRITE> and C<EV::TIMEOUT>).

EV::once doesn't return anything: the watchers stay active till either
of them triggers, then they will be stopped and freed, and the callback
invoked.

=back

=head2 WATCHER OBJECTS

A watcher is an object that gets created to record your interest in some
event. For instance, if you want to wait for STDIN to become readable, you
would create an EV::io watcher for that:

  my $watcher = EV::io *STDIN, EV::READ, sub {
     my ($watcher, $revents) = @_;
     warn "yeah, STDIN should not be readable without blocking!\n"
  };

All watchers can be active (waiting for events) or inactive (paused). Only
active watchers will have their callbacks invoked. All callbacks will be
called with at least two arguments: the watcher and a bitmask of received
events.

Each watcher type has its associated bit in revents, so you can use the
same callback for multiple watchers. The event mask is named after the
type, i..e. EV::child sets EV::CHILD, EV::prepare sets EV::PREPARE,
EV::periodic sets EV::PERIODIC and so on, with the exception of IO events
(which can set both EV::READ and EV::WRITE bits), and EV::timer (which
uses EV::TIMEOUT).

In the rare case where one wants to create a watcher but not start it at
the same time, each constructor has a variant with a trailing C<_ns> in
its name, e.g. EV::io has a non-starting variant EV::io_ns and so on.

Please note that a watcher will automatically be stopped when the watcher
object is destroyed, so you I<need> to keep the watcher objects returned by
the constructors.

Also, all methods changing some aspect of a watcher (->set, ->priority,
->fh and so on) automatically stop and start it again if it is active,
which means pending events get lost.

=head2 COMMON WATCHER METHODS

This section lists methods common to all watchers.

=over 4

=item $w->start

Starts a watcher if it isn't active already. Does nothing to an already
active watcher. By default, all watchers start out in the active state
(see the description of the C<_ns> variants if you need stopped watchers).

=item $w->stop

Stop a watcher if it is active. Also clear any pending events (events that
have been received but that didn't yet result in a callback invocation),
regardless of wether the watcher was active or not.

=item $bool = $w->is_active

Returns true if the watcher is active, false otherwise.

=item $current_data = $w->data

=item $old_data = $w->data ($new_data)

Queries a freely usable data scalar on the watcher and optionally changes
it. This is a way to associate custom data with a watcher:

   my $w = EV::timer 60, 0, sub {
      warn $_[0]->data;
   };
   $w->data ("print me!");

=item $current_cb = $w->cb

=item $old_cb = $w->cb ($new_cb)

Queries the callback on the watcher and optionally changes it. You can do
this at any time without the watcher restarting.

=item $current_priority = $w->priority

=item $old_priority = $w->priority ($new_priority)

Queries the priority on the watcher and optionally changes it. Pending
watchers with higher priority will be invoked first. The valid range of
priorities lies between EV::MAXPRI (default 2) and EV::MINPRI (default
-2). If the priority is outside this range it will automatically be
normalised to the nearest valid priority.

The default priority of any newly-created watcher is 0.

Note that the priority semantics have not yet been fleshed out and are
subject to almost certain change.

=item $w->trigger ($revents)

Call the callback *now* with the given event mask.

=item $previous_state = $w->keepalive ($bool)

Normally, C<EV::loop> will return when there are no active watchers
(which is a "deadlock" because no progress can be made anymore). This is
convinient because it allows you to start your watchers (and your jobs),
call C<EV::loop> once and when it returns you know that all your jobs are
finished (or they forgot to register some watchers for their task :).

Sometimes, however, this gets in your way, for example when you the module
that calls C<EV::loop> (usually the main program) is not the same module
as a long-living watcher (for example a DNS client module written by
somebody else even). Then you might want any outstanding requests to be
handled, but you would not want to keep C<EV::loop> from returning just
because you happen to have this long-running UDP port watcher.

In this case you can clear the keepalive status, which means that even
though your watcher is active, it won't keep C<EV::loop> from returning.

The initial value for keepalive is true (enabled), and you cna change it
any time.

Example: Register an IO watcher for some UDP socket but do not keep the
event loop from running just because of that watcher.

   my $udp_socket = ...
   my $udp_watcher = EV::io $udp_socket, EV::READ, sub { ... };
   $udp_watcher->keepalive (0);

=back


=head2 WATCHER TYPES

Each of the following subsections describes a single watcher type.

=head3 IO WATCHERS - is this file descriptor readable or writable?

=over 4

=item $w = EV::io $fileno_or_fh, $eventmask, $callback

=item $w = EV::io_ns $fileno_or_fh, $eventmask, $callback

As long as the returned watcher object is alive, call the C<$callback>
when at least one of events specified in C<$eventmask> occurs.

The $eventmask can be one or more of these constants ORed together:

  EV::READ     wait until read() wouldn't block anymore
  EV::WRITE    wait until write() wouldn't block anymore

The C<io_ns> variant doesn't start (activate) the newly created watcher.

=item $w->set ($fileno_or_fh, $eventmask)

Reconfigures the watcher, see the constructor above for details. Can be
called at any time.

=item $current_fh = $w->fh

=item $old_fh = $w->fh ($new_fh)

Returns the previously set filehandle and optionally set a new one.

=item $current_eventmask = $w->events

=item $old_eventmask = $w->events ($new_eventmask)

Returns the previously set event mask and optionally set a new one.

=back


=head3 TIMER WATCHERS - relative and optionally repeating timeouts

=over 4

=item $w = EV::timer $after, $repeat, $callback

=item $w = EV::timer_ns $after, $repeat, $callback

Calls the callback after C<$after> seconds (which may be fractional). If
C<$repeat> is non-zero, the timer will be restarted (with the $repeat
value as $after) after the callback returns.

This means that the callback would be called roughly after C<$after>
seconds, and then every C<$repeat> seconds. The timer does his best not
to drift, but it will not invoke the timer more often then once per event
loop iteration, and might drift in other cases. If that isn't acceptable,
look at EV::periodic, which can provide long-term stable timers.

The timer is based on a monotonic clock, that is, if somebody is sitting
in front of the machine while the timer is running and changes the system
clock, the timer will nevertheless run (roughly) the same time.

The C<timer_ns> variant doesn't start (activate) the newly created watcher.

=item $w->set ($after, $repeat)

Reconfigures the watcher, see the constructor above for details. Can be called at
any time.

=item $w->again

Similar to the C<start> method, but has special semantics for repeating timers:

If the timer is active and non-repeating, it will be stopped.

If the timer is active and repeating, reset the timeout to occur
C<$repeat> seconds after now.

If the timer is inactive and repeating, start it using the repeat value.

Otherwise do nothing.

This behaviour is useful when you have a timeout for some IO
operation. You create a timer object with the same value for C<$after> and
C<$repeat>, and then, in the read/write watcher, run the C<again> method
on the timeout.

=back


=head3 PERIODIC WATCHERS - to cron or not to cron?

=over 4

=item $w = EV::periodic $at, $interval, $reschedule_cb, $callback

=item $w = EV::periodic_ns $at, $interval, $reschedule_cb, $callback

Similar to EV::timer, but is not based on relative timeouts but on
absolute times. Apart from creating "simple" timers that trigger "at" the
specified time, it can also be used for non-drifting absolute timers and
more complex, cron-like, setups that are not adversely affected by time
jumps (i.e. when the system clock is changed by explicit date -s or other
means such as ntpd). It is also the most complex watcher type in EV.

It has three distinct "modes":

=over 4

=item * absolute timer ($interval = $reschedule_cb = 0)

This time simply fires at the wallclock time C<$at> and doesn't repeat. It
will not adjust when a time jump occurs, that is, if it is to be run
at January 1st 2011 then it will run when the system time reaches or
surpasses this time.

=item * non-repeating interval timer ($interval > 0, $reschedule_cb = 0)

In this mode the watcher will always be scheduled to time out at the
next C<$at + N * $interval> time (for some integer N) and then repeat,
regardless of any time jumps.

This can be used to create timers that do not drift with respect to system
time:

   my $hourly = EV::periodic 0, 3600, 0, sub { print "once/hour\n" };

That doesn't mean there will always be 3600 seconds in between triggers,
but only that the the clalback will be called when the system time shows a
full hour (UTC).

Another way to think about it (for the mathematically inclined) is that
EV::periodic will try to run the callback in this mode at the next
possible time where C<$time = $at (mod $interval)>, regardless of any time
jumps.

=item * manual reschedule mode ($reschedule_cb = coderef)

In this mode $interval and $at are both being ignored. Instead, each
time the periodic watcher gets scheduled, the reschedule callback
($reschedule_cb) will be called with the watcher as first, and the current
time as second argument.

I<This callback MUST NOT stop or destroy this or any other periodic
watcher, ever>. If you need to stop it, return 1e30 and stop it
afterwards.

It must return the next time to trigger, based on the passed time value
(that is, the lowest time value larger than to the second argument). It
will usually be called just before the callback will be triggered, but
might be called at other times, too.

This can be used to create very complex timers, such as a timer that
triggers on each midnight, local time (actually 24 hours after the last
midnight, to keep the example simple. If you know a way to do it correctly
in about the same space (without requiring elaborate modules), drop me a
note :):

   my $daily = EV::periodic 0, 0, sub {
      my ($w, $now) = @_;

      use Time::Local ();
      my (undef, undef, undef, $d, $m, $y) = localtime $now;
      86400 + Time::Local::timelocal 0, 0, 0, $d, $m, $y
   }, sub {
      print "it's midnight or likely shortly after, now\n";
   };

=back

The C<periodic_ns> variant doesn't start (activate) the newly created watcher.

=item $w->set ($at, $interval, $reschedule_cb)

Reconfigures the watcher, see the constructor above for details. Can be called at
any time.

=item $w->again

Simply stops and starts the watcher again.

=back


=head3 SIGNAL WATCHERS - signal me when a signal gets signalled!

=over 4

=item $w = EV::signal $signal, $callback

=item $w = EV::signal_ns $signal, $callback

Call the callback when $signal is received (the signal can be specified by
number or by name, just as with C<kill> or C<%SIG>).

EV will grab the signal for the process (the kernel only allows one
component to receive a signal at a time) when you start a signal watcher,
and removes it again when you stop it. Perl does the same when you
add/remove callbacks to C<%SIG>, so watch out.

You can have as many signal watchers per signal as you want.

The C<signal_ns> variant doesn't start (activate) the newly created watcher.

=item $w->set ($signal)

Reconfigures the watcher, see the constructor above for details. Can be
called at any time.

=item $current_signum = $w->signal

=item $old_signum = $w->signal ($new_signal)

Returns the previously set signal (always as a number not name) and
optionally set a new one.

=back


=head3 CHILD WATCHERS - watch out for process status changes

=over 4

=item $w = EV::child $pid, $callback

=item $w = EV::child_ns $pid, $callback

Call the callback when a status change for pid C<$pid> (or any pid if
C<$pid> is 0) has been received. More precisely: when the process receives
a C<SIGCHLD>, EV will fetch the outstanding exit/wait status for all
changed/zombie children and call the callback.

It is valid (and fully supported) to install a child watcher after a child
has exited but before the event loop has started its next iteration (for
example, first you C<fork>, then the new child process might exit, and
only then do you install a child watcher in the parent for the new pid).

You can access both exit (or tracing) status and pid by using the
C<rstatus> and C<rpid> methods on the watcher object.

You can have as many pid watchers per pid as you want, they will all be
called.

The C<child_ns> variant doesn't start (activate) the newly created watcher.

=item $w->set ($pid)

Reconfigures the watcher, see the constructor above for details. Can be called at
any time.

=item $current_pid = $w->pid

=item $old_pid = $w->pid ($new_pid)

Returns the previously set process id and optionally set a new one.

=item $exit_status = $w->rstatus

Return the exit/wait status (as returned by waitpid, see the waitpid entry
in perlfunc).

=item $pid = $w->rpid

Return the pid of the awaited child (useful when you have installed a
watcher for all pids).

=back


=head3 STAT WATCHERS - did the file attributes just change?

=over 4

=item $w = EV::stat $path, $interval, $callback

=item $w = EV::stat_ns $path, $interval, $callback

Call the callback when a file status change has been detected on
C<$path>. The C<$path> does not need to exist, changing from "path exists"
to "path does not exist" is a status change like any other.

The C<$interval> is a recommended polling interval for systems where
OS-supported change notifications don't exist or are not supported. If
you use C<0> then an unspecified default is used (which is highly
recommended!), which is to be expected to be around five seconds usually.

This watcher type is not meant for massive numbers of stat watchers,
as even with OS-supported change notifications, this can be
resource-intensive.

The C<stat_ns> variant doesn't start (activate) the newly created watcher.

=item ... = $w->stat

This call is very similar to the perl C<stat> built-in: It stats (using
C<lstat>) the path specified in the watcher and sets perls stat cache (as
well as EV's idea of the current stat values) to the values found.

In scalar context, a boolean is return indicating success or failure of
the stat. In list context, the same 13-value list as with stat is returned
(except that the blksize and blocks fields are not reliable).

In the case of an error, errno is set to C<ENOENT> (regardless of the
actual error value) and the C<nlink> value is forced to zero (if the stat
was successful then nlink is guaranteed to be non-zero).

See also the next two entries for more info.

=item ... = $w->attr

Just like C<< $w->stat >>, but without the initial stat'ing: this returns
the values most recently detected by EV. See the next entry for more info.

=item ... = $w->prev

Just like C<< $w->stat >>, but without the initial stat'ing: this returns
the previous set of values, before the change.

That is, when the watcher callback is invoked, C<< $w->prev >> will be set
to the values found I<before> a change was detected, while C<< $w->attr >>
returns the values found leading to the change detection. The difference (if any)
between C<prev> and C<attr> is what triggered the callback.

If you did something to the filesystem object and do not want to trigger
yet another change, you can call C<stat> to update EV's idea of what the
current attributes are.

=item $w->set ($path, $interval)

Reconfigures the watcher, see the constructor above for details. Can be
called at any time.

=item $current_path = $w->path

=item $old_path = $w->path ($new_path)

Returns the previously set path and optionally set a new one.

=item $current_interval = $w->interval

=item $old_interval = $w->interval ($new_interval)

Returns the previously set interval and optionally set a new one. Can be
used to query the actual interval used.

=back


=head3 IDLE WATCHERS - when you've got nothing better to do...

=over 4

=item $w = EV::idle $callback

=item $w = EV::idle_ns $callback

Call the callback when there are no pending io, timer/periodic, signal or
child events, i.e. when the process is idle.

The process will not block as long as any idle watchers are active, and
they will be called repeatedly until stopped.

The C<idle_ns> variant doesn't start (activate) the newly created watcher.

=back


=head3 PREPARE WATCHERS - customise your event loop!

=over 4

=item $w = EV::prepare $callback

=item $w = EV::prepare_ns $callback

Call the callback just before the process would block. You can still
create/modify any watchers at this point.

See the EV::check watcher, below, for explanations and an example.

The C<prepare_ns> variant doesn't start (activate) the newly created watcher.

=back


=head3 CHECK WATCHERS - customise your event loop even more!

=over 4

=item $w = EV::check $callback

=item $w = EV::check_ns $callback

Call the callback just after the process wakes up again (after it has
gathered events), but before any other callbacks have been invoked.

This is used to integrate other event-based software into the EV
mainloop: You register a prepare callback and in there, you create io and
timer watchers as required by the other software. Here is a real-world
example of integrating Net::SNMP (with some details left out):

   our @snmp_watcher;

   our $snmp_prepare = EV::prepare sub {
      # do nothing unless active
      $dispatcher->{_event_queue_h}
         or return;

      # make the dispatcher handle any outstanding stuff
      ... not shown

      # create an IO watcher for each and every socket
      @snmp_watcher = (
         (map { EV::io $_, EV::READ, sub { } }
             keys %{ $dispatcher->{_descriptors} }),

         EV::timer +($event->[Net::SNMP::Dispatcher::_ACTIVE]
                     ? $event->[Net::SNMP::Dispatcher::_TIME] - EV::now : 0),
                    0, sub { },
      );
   };

The callbacks are irrelevant (and are not even being called), the
only purpose of those watchers is to wake up the process as soon as
one of those events occurs (socket readable, or timer timed out). The
corresponding EV::check watcher will then clean up:

   our $snmp_check = EV::check sub {
      # destroy all watchers
      @snmp_watcher = ();

      # make the dispatcher handle any new stuff
      ... not shown
   };

The callbacks of the created watchers will not be called as the watchers
are destroyed before this cna happen (remember EV::check gets called
first).

The C<check_ns> variant doesn't start (activate) the newly created watcher.

=back


=head3 FORK WATCHERS - the audacity to resume the event loop after a fork

Fork watchers are called when a C<fork ()> was detected. The invocation
is done before the event loop blocks next and before C<check> watchers
are being called, and only in the child after the fork.

=over 4

=item $w = EV::fork $callback

=item $w = EV::fork_ns $callback

Call the callback before the event loop is resumed in the child process
after a fork.

The C<fork_ns> variant doesn't start (activate) the newly created watcher.

=back


=head1 THREADS

Threads are not supported by this module in any way. Perl pseudo-threads
is evil stuff and must die. As soon as Perl gains real threads I will work
on thread support for it.

=head1 FORK

Most of the "improved" event delivering mechanisms of modern operating
systems have quite a few problems with fork(2) (to put it bluntly: it is
not supported and usually destructive). Libev makes it possible to work
around this by having a function that recreates the kernel state after
fork in the child.

On non-win32 platforms, this module requires the pthread_atfork
functionality to do this automatically for you. This function is quite
buggy on most BSDs, though, so YMMV. The overhead for this is quite
negligible, because everything the function currently does is set a flag
that is checked only when the event loop gets used the next time, so when
you do fork but not use EV, the overhead is minimal.

On win32, there is no notion of fork so all this doesn't apply, of course.

=cut

our $DIED = sub {
   warn "EV: error in callback (ignoring): $@";
};

default_loop
   or die 'EV: cannot initialise libev backend. bad $ENV{LIBEV_METHODS}?';

1;

=head1 SEE ALSO

L<EV::DNS>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

