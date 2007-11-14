BEGIN { $| = 1; print "1..3002\n"; }

use EV;

my $id = 1;
my @timer;

my $base = EV::now;
my $prev = EV::now;

for (1..1000) {
   my $t = $_ * $_ * 1.735435336; $t -= int $t;
   push @timer, EV::timer $t, 0, sub {
      print EV::now >= $prev ? "" : "not ", "ok ", ++$id, "\n";
      print EV::now >= $base + $t ? "" : "not ", "ok ", ++$id, "\n";

      unless ($id % 3) {
         $_[0]->set ($t * 0.0625);
         $t *= 1.0625;
         $_[0]->start;
      }
   };
}

print "ok 1\n";
EV::loop;
print "ok 3002\n";

