BEGIN { $| = 1; print "1..3\n"; }

$^W = 0; # work around some bugs in perl

print eval { require EV            } ? "" : "not ", "ok 1 # $@\n";
if ($^O eq "linux") {
   print eval { require EV::DNS       } ? "" : "not ", "ok 2 # $@\n";
} else {
   print "ok 2 # skipped on non-gnu/linux\n";
}
print eval { require EV::MakeMaker } ? "" : "not ", "ok 3 # $@\n";
