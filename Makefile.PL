use 5.006;

use ExtUtils::MakeMaker;

print <<EOF;

***
*** You need to install libevent (http://monkey.org/~provos/libevent/) separately
*** first in a way so that the Makefile.PL can find both -levent and the event.h
*** and evdns.h include files.
*** 
*** Version 1.3e or higher is recommended, but older 1.3 versions likely work too.
*** 

EOF

WriteMakefile(
    dist	=> {
	            PREOP	=> 'pod2text EV.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
	            COMPRESS	=> 'gzip -9v',
	            SUFFIX	=> '.gz',
	           },
    LIBS => ["-levent"],
    NAME => "EV",
    VERSION_FROM => "EV.pm",
);

