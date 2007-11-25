BEGIN { $| = 1; print "1..6\n"; }

no warnings;
use strict;

use EV;

for my $i (3..5) {
   EV::once undef, 0, $i * 0.05, sub {
      print $_[0] == EV::TIMEOUT ? "" : "not ", "ok $i\n";
   };
}

EV::once 1, EV::WRITE, 0.5, sub {
   print $_[0] == EV::WRITE ? "" : "not ", "ok 2\n";
};

print "ok 1\n";
EV::loop;
print "ok 6\n";
