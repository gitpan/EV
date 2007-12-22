BEGIN { $| = 1; print "1..6\n"; }

no warnings;
use strict;
use Socket;

use EV;

my $l = new EV::Loop;

for my $i (3..5) {
   $l->once (undef, 0, $i * 0.2, sub {
      print $_[0] == EV::TIMEOUT ? "" : "not ", "ok $i\n";
   });
}

socketpair my $s1, my $s2, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

$l->once ($s1, EV::WRITE, 0.5, sub {
   print $_[0] & EV::WRITE ? "" : "not ", "ok 2\n";
});

print "ok 1\n";
$l->loop;
print "ok 6\n";
