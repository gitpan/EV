BEGIN { $| = 1; print "1..2\n"; }

$^W = 0; # work around some bugs in perl

print eval { require EV            } ? "" : "not ", "ok 1 # $@\n";
print eval { require EV::MakeMaker } ? "" : "not ", "ok 2 # $@\n";
