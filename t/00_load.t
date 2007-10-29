BEGIN { $| = 1; print "1..4\n"; }

print eval { require EV            } ? "" : "not ", "ok 1\n";
print eval { require EV::DNS       } ? "" : "not ", "ok 2\n";
print eval { require EV::AnyEvent  } ? "" : "not ", "ok 3\n";
print eval { require EV::MakeMaker } ? "" : "not ", "ok 4\n";
