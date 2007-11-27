BEGIN { $| = 1; print "1..6\n"; }

no warnings;
use strict;

use File::Temp;

use EV;

my $fh = new File::Temp UNLINK => 1;

my $w = EV::stat "$fh", 0.1, sub {
   print "ok 5\n";
   EV::unloop;
};

my $t = EV::timer 0.2, 0, sub {
   print "ok 2\n";
   EV::unloop;
};

print "ok 1\n";
EV::loop;
print "ok 3\n";

syswrite $fh, "size change";
undef $fh; # work around bugs in windows not updating stat info

my $t = EV::timer 0.2, 0, sub {
   print "no ok 5\n";
   EV::unloop;
};

print "ok 4\n";
EV::loop;
print "ok 6\n";

