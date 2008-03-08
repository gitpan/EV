BEGIN { $| = 1; print "1..12\n"; }

no warnings;
use strict;

use EV;

 {
   my ($a1, $a2, $a3);

   $a3 = EV::async sub {
      print "not ok 1\n";
   };
   $a2 = EV::async sub {
      print "ok 4\n";
      $a1->cb (sub {
         print "ok 5\n";
         EV::unloop;
      });
      $a1->send;
   };
   $a1 = EV::async sub {
      print "ok 3\n";
      $a2->send;
   };

   print "ok 1\n";
   $a1->send;
   $a1->send;
   $a1->send;
   print "ok 2\n";
   EV::loop;
   print "ok 6\n";
}

{
   my $l = new EV::Loop;
   my ($a1, $a2, $a3);

   $a3 = $l->async (sub {
      print "not ok 7\n";
   });
   $a2 = $l->async (sub {
      print "ok 10\n";
      $a1->cb (sub {
         print "ok 11\n";
         $l->unloop;
      });
      $a1->send;
   });
   $a1 = $l->async (sub {
      print "ok 9\n";
      $a2->send;
   });

   print "ok 7\n";
   $a1->send;
   $a1->send;
   $a1->send;
   print "ok 8\n";
   $l->loop;
   print "ok 12\n";
}
