BEGIN { $| = 1; print "1..7\n"; }

no warnings;
use strict;

use EV;

my $timer = EV::timer_ns 0, 0, sub { print "ok 6\n" };

$timer->keepalive (1);

print "ok 1\n";
EV::loop;
print "ok 2\n";

$timer->start;

$timer->keepalive (0);

$timer->again;
$timer->stop;
$timer->start;

print "ok 3\n";
EV::loop;
print "ok 4\n";

$timer->keepalive (1);

print "ok 5\n";
EV::loop;
print "ok 7\n";

