package EV::MakeMaker;

BEGIN { eval { require warnings } && warnings->unimport ("uninitialized") }

use Config;
use base 'Exporter';

@EXPORT_OK = qw(&ev_args $installsitearch);

my %opt;

for my $opt (split /:+/, $ENV{PERL_MM_OPT}) {
   my ($k,$v) = split /=/, $opt;
   $opt{$k} = $v;
}

my $extra = $Config{sitearch};

$extra =~ s/$Config{prefix}/$opt{PREFIX}/ if
    exists $opt{PREFIX};

for my $d ($extra, @INC) {
   if (-e "$d/EV/EVAPI.h") {
      $installsitearch = $d;
      last;
   }
}

sub ev_args {
   my %arg = @_;
   $arg{INC} .= " -I$installsitearch/EV";
   %arg;
}

1;
__END__

=head1 NAME

EV::MakeMaker - MakeMaker glue for the C-level EV API

=head1 SYNOPSIS

This allows you to access some libevent functionality from other perl
modules.

=head1 DESCRIPTION

For optimal performance, hook into EV at the C-level.  You'll need
to make changes to your C<Makefile.PL> and add code to your C<xs> /
C<c> file(s).

=head1 HOW TO

=head2 Makefile.PL

  use EV::MakeMaker qw(ev_args);

  # ... set up %args ...

  WriteMakefile (ev_args (%args));

=head2 XS

  #include "EVAPI.h"

  BOOT:
    I_EV_API ("YourModule");

=head2 API

See the EVAPI.h header.

=cut
