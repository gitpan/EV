use 5.006;

use Config;
use ExtUtils::MakeMaker;


unless (-e "libev/ev_epoll.c") {
   print <<EOF;

***
*** ERROR: libev is missing or damaged. If you used a CVS check-out of EV,
*** you also have to check-out the "libev" module from the same CVS
*** repository into the EV dir (i.e. EV/libev from outside).
***

EOF
   exit 1;
}

print <<EOF;


*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

Welcome to EV configuration. If you are in a hurry, just press return here
and hope for the best. The defaults should usually do.

EOF

if (prompt ("Skip further questions and use defaults (y/n)?", "y") =~ /[yY]/) {
   $ENV{PERL_MM_USE_DEFAULT} = 1;
}

print <<EOF;


*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

POSIX optionally offers support for a monotonic clock source. EV can
take advantage of this clock source to detect time jumps reliably. This
will usually slow down EV a tiny amount, but this is usually
well-invested. Unfortunately, some systems are bound to be broken, so
you can disable this here. Whatever your reasons, you can completely
disable the detection and use of this monotonic clock by answering 'n'
here. Support for this clock type will otherwise be autodetected at both
compile- and runtime.

EOF

if (prompt ("Enable optional support for CLOCK_MONOTONIC (y/n)?", "y") =~ /[yY]/) {
   $DEFINE .= " -DEV_USE_MONOTONIC";
}

print <<EOF;


*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

POSIX optionally offers support for a (potentially) high-resolution
realtime clock interface. In a good implementation, using it is faster
than the normal method of using gettimeofday. Unfortunately, this option
is also bound to be broken on some systems, so you can disable use and
probing of this feature altogether here. Otherwise support for this clock
type will be autodetected at compiletime.

EOF

if (prompt ("Prefer clock_gettime (CLOCK_REALTIME) over gettimeofday (y/n)?", "y") !~ /[yY]/) {
   $DEFINE .= " -DEV_USE_REALTIME=0";
}

print <<EOF;


*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

EV needs the functions pthread_atfork and clock_gettime. On most systems
you need some special libraries for this (such as -lrt and -lpthread). You can
specify additional libraries to provide these calls now, or accept the default.

EOF

$LIBS = prompt "Extra libraries for pthread_atfork and clock_gettime?", "-lpthread -lrt";


print <<EOF;


*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

EV needs the functions pthread_atfork and clock_gettime. On most systems
you need some special libraries for this (such as -lrt and -lpthread). You can
specify additional libraries to provide these calls now, or accept the default.

EOF

if (prompt ("Enable epoll backend (y/n)?", (-e "/usr/include/sys/epoll.h") ? "y" : "n") =~ /[yY]/) {
   $DEFINE .= " -DEV_USE_EPOLL";
} 

print <<EOF;


*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

EOF

WriteMakefile(
    dist	=> {
	            PREOP	=> 'pod2text EV.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
	            COMPRESS	=> 'gzip -9v',
	            SUFFIX	=> '.gz',
	           },
    depend => {
       "EV.c" => "EV/EVAPI.h "
               . "libev/ev.c libev/ev.h libev/ev_epoll.c libev/ev_select.c "
               . "libev/event.h libev/event.c libev/evdns.h libev/evdns.c",
    },
    INC       => "-Ilibev",
    DEFINE    => "$DEFINE",
    NAME => "EV",
    LIBS => [$LIBS],
    VERSION_FROM => "EV.pm",
    PM           => {
    		    'EV.pm'		=> '$(INST_LIBDIR)/EV.pm',
    		    'EV/AnyEvent.pm'	=> '$(INST_LIBDIR)/EV/AnyEvent.pm',
                    'EV/DNS.pm'		=> '$(INST_LIBDIR)/EV/DNS.pm',
    		    'EV/EVAPI.h'	=> '$(INST_LIBDIR)/EV/EVAPI.h',
    		    'EV/MakeMaker.pm'	=> '$(INST_LIBDIR)/EV/MakeMaker.pm',
    		    'libev/ev.h'	=> '$(INST_LIBDIR)/EV/ev.h',
                 },
);


