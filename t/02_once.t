BEGIN {
   if (exists $ENV{AUTOMATED_TESTING}) {
      print "1..0 # Skipped: Too many broken cpan tester setups.\n";
      exit;
   }
}

BEGIN { $| = 1; print "1..6\n"; }

no warnings;
use strict;
use Socket;

use EV;

for my $i (3..5) {
   EV::once undef, 0, ($i - 3) * 0.5 + 1.0, sub {
      print $_[0] == EV::TIMEOUT ? "" : "not ", "ok $i\n";
   };
}

socketpair my $s1, my $s2, AF_UNIX, SOCK_STREAM, PF_UNSPEC;

EV::once $s1, EV::WRITE, 0.5, sub {
   print $_[0] & EV::WRITE ? "" : "not ", "ok 2\n";
};

print "ok 1\n";
EV::loop;
print "ok 6\n";
