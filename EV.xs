#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*#include <netinet/in.h>*/

#define EV_PROTOTYPES 1
#include "EV/EVAPI.h"

/* fix perl api breakage */
#undef signal
#undef sigaction

#define EV_SELECT_IS_WINSOCKET 0
#ifdef _WIN32
# define EV_SELECT_USE_FD_SET 0
# define NFDBITS PERL_NFDBITS
# define fd_mask Perl_fd_mask
#endif
/* due to bugs in OS X we have to use libev/ explicitly here */
#include "libev/ev.c"
#include "event.c"

#ifndef _WIN32
#define DNS_USE_GETTIMEOFDAY_FOR_ID 1
#if !defined (WIN32) && !defined(__CYGWIN__)
# define HAVE_STRUCT_IN6_ADDR 1
#endif
#undef HAVE_STRTOK_R
#undef strtok_r
#define strtok_r fake_strtok_r
#include "evdns.h"
#include "evdns.c"
#endif

#ifndef _WIN32
# include <pthread.h>
#endif

#define WFLAG_KEEPALIVE 1

#define UNREF(w)				\
  if (!((w)->flags & WFLAG_KEEPALIVE)		\
      && !ev_is_active (w))			\
    ev_unref ();

#define REF(w)					\
  if (!((w)->flags & WFLAG_KEEPALIVE)		\
      && ev_is_active (w))			\
    ev_ref ();

#define START(type,w)				\
  do {						\
    UNREF (w);					\
    ev_ ## type ## _start (w);			\
  } while (0)

#define STOP(type,w)				\
  do {						\
    REF (w);					\
    ev_ ## type ## _stop (w);			\
  } while (0)

typedef int Signal;

static struct EVAPI evapi;

static HV
  *stash_watcher,
  *stash_io,
  *stash_timer,
  *stash_periodic,
  *stash_signal,
  *stash_idle,
  *stash_prepare,
  *stash_check,
  *stash_child;

#ifndef SIG_SIZE
/* kudos to Slaven Rezic for the idea */
static char sig_size [] = { SIG_NUM };
# define SIG_SIZE (sizeof (sig_size) + 1)
#endif

static int
sv_signum (SV *sig)
{
  int signum;

  SvGETMAGIC (sig);

  for (signum = 1; signum < SIG_SIZE; ++signum)
    if (strEQ (SvPV_nolen (sig), PL_sig_name [signum]))
      return signum;

  if (SvIV (sig) > 0)
    return SvIV (sig);

  return -1;
}

/////////////////////////////////////////////////////////////////////////////
// Event

static void e_cb (ev_watcher *w, int revents);

static int
sv_fileno (SV *fh)
{
  SvGETMAGIC (fh);

  if (SvROK (fh))
    fh = SvRV (fh);

  if (SvTYPE (fh) == SVt_PVGV)
    return PerlIO_fileno (IoIFP (sv_2io (fh)));

  if (SvOK (fh) && (SvIV (fh) >= 0) && (SvIV (fh) < 0x7fffffffL))
    return SvIV (fh);

  return -1;
}

static void *
e_new (int size, SV *cb_sv)
{
  ev_watcher *w;
  SV *self = NEWSV (0, size);
  SvPOK_only (self);
  SvCUR_set (self, size);

  w = (ev_watcher *)SvPVX (self);

  ev_init (w, e_cb);

  w->flags = WFLAG_KEEPALIVE;
  w->data  = 0;
  w->fh    = 0;
  w->cb_sv = newSVsv (cb_sv);
  w->self  = self;

  return (void *)w;
}

static void
e_destroy (void *w_)
{
  ev_watcher *w = (ev_watcher *)w_;

  SvREFCNT_dec (w->fh   ); w->fh    = 0;
  SvREFCNT_dec (w->cb_sv); w->cb_sv = 0;
  SvREFCNT_dec (w->data ); w->data  = 0;
}

static SV *
e_bless (ev_watcher *w, HV *stash)
{
  SV *rv;

  if (SvOBJECT (w->self))
    rv = newRV_inc (w->self);
  else
    {
      rv = newRV_noinc (w->self);
      sv_bless (rv, stash);
      SvREADONLY_on (w->self);
    }

  return rv;
}

static SV *sv_events_cache;

static void
e_cb (ev_watcher *w, int revents)
{
  dSP;
  I32 mark = SP - PL_stack_base;
  SV *sv_self, *sv_events;

  sv_self = newRV_inc (w->self); /* w->self MUST be blessed by now */

  if (sv_events_cache)
    {
      sv_events = sv_events_cache; sv_events_cache = 0;
      SvIV_set (sv_events, revents);
    }
  else
    sv_events = newSViv (revents);

  PUSHMARK (SP);
  EXTEND (SP, 2);
  PUSHs (sv_self);
  PUSHs (sv_events);

  PUTBACK;
  call_sv (w->cb_sv, G_DISCARD | G_VOID | G_EVAL);

  SvREFCNT_dec (sv_self);

  if (sv_events_cache)
    SvREFCNT_dec (sv_events);
  else
    sv_events_cache = sv_events;

  if (SvTRUE (ERRSV))
    {
      PUSHMARK (SP);
      PUTBACK;
      call_sv (get_sv ("EV::DIED", 1), G_DISCARD | G_VOID | G_EVAL | G_KEEPERR);
    }

  SP = PL_stack_base + mark;
  PUTBACK;
}

static void
e_once_cb (int revents, void *arg)
{
  dSP;
  I32 mark = SP - PL_stack_base;
  SV *sv_events;

  if (sv_events_cache)
    {
      sv_events = sv_events_cache; sv_events_cache = 0;
      SvIV_set (sv_events, revents);
    }
  else
    sv_events = newSViv (revents);

  PUSHMARK (SP);
  XPUSHs (sv_events);

  PUTBACK;
  call_sv ((SV *)arg, G_DISCARD | G_VOID | G_EVAL);

  SvREFCNT_dec ((SV *)arg);

  if (sv_events_cache)
    SvREFCNT_dec (sv_events);
  else
    sv_events_cache = sv_events;

  if (SvTRUE (ERRSV))
    {
      PUSHMARK (SP);
      PUTBACK;
      call_sv (get_sv ("EV::DIED", 1), G_DISCARD | G_VOID | G_EVAL | G_KEEPERR);
    }

  SP = PL_stack_base + mark;
  PUTBACK;
}

static ev_tstamp
e_periodic_cb (ev_periodic *w, ev_tstamp now)
{
  ev_tstamp retval;
  int count;
  dSP;

  ENTER;
  SAVETMPS;

  PUSHMARK (SP);
  EXTEND (SP, 2);
  PUSHs (newRV_inc (w->self)); /* w->self MUST be blessed by now */
  PUSHs (newSVnv (now));

  PUTBACK;
  count = call_sv (w->fh, G_SCALAR | G_EVAL);
  SPAGAIN;

  if (SvTRUE (ERRSV))
    {
      PUSHMARK (SP);
      PUTBACK;
      call_sv (get_sv ("EV::DIED", 1), G_DISCARD | G_VOID | G_EVAL | G_KEEPERR);
      SPAGAIN;
    }

  if (count > 0)
    {
      retval = SvNV (TOPs);

      if (retval < now)
        retval = now;
    }
  else
    retval = now;

  FREETMPS;
  LEAVE;

  return retval;
}

/////////////////////////////////////////////////////////////////////////////
// DNS

#ifndef _WIN32
static void
dns_cb (int result, char type, int count, int ttl, void *addresses, void *arg)
{
  dSP;
  SV *cb = (SV *)arg;

  ENTER;
  SAVETMPS;
  PUSHMARK (SP);
  EXTEND (SP, count + 3);
  PUSHs (sv_2mortal (newSViv (result)));

  if (result == DNS_ERR_NONE && ttl >= 0)
    {
      int i;

      PUSHs (sv_2mortal (newSViv (type)));
      PUSHs (sv_2mortal (newSViv (ttl)));

      for (i = 0; i < count; ++i)
        switch (type)
          {
            case DNS_IPv6_AAAA:
              PUSHs (sv_2mortal (newSVpvn (i * 16 + (char *)addresses, 16)));
              break;
            case DNS_IPv4_A:
              PUSHs (sv_2mortal (newSVpvn (i *  4 + (char *)addresses,  4)));
              break;
            case DNS_PTR:
              PUSHs (sv_2mortal (newSVpv (*(char **)addresses, 0)));
              break;
          }
    }

  PUTBACK;
  call_sv (sv_2mortal (cb), G_DISCARD | G_VOID | G_EVAL);

  FREETMPS;

  if (SvTRUE (ERRSV))
    {
      PUSHMARK (SP);
      PUTBACK;
      call_sv (get_sv ("EV::DIED", 1), G_DISCARD | G_VOID | G_EVAL | G_KEEPERR);
    }

  LEAVE;
}
#endif

#define CHECK_REPEAT(repeat) if (repeat < 0.) \
  croak (# repeat " value must be >= 0");

#define CHECK_FD(fh,fd) if ((fd) < 0) \
  croak ("illegal file descriptor or filehandle (either no attached file descriptor or illegal value): %s", SvPV_nolen (fh));

/////////////////////////////////////////////////////////////////////////////
// XS interface functions

MODULE = EV		PACKAGE = EV		PREFIX = ev_

PROTOTYPES: ENABLE

BOOT:
{
  HV *stash = gv_stashpv ("EV", 1);

  static const struct {
    const char *name;
    IV iv;
  } *civ, const_iv[] = {
#   define const_iv(pfx, name) { # name, (IV) pfx ## name },
    const_iv (EV_, MINPRI)
    const_iv (EV_, MAXPRI)

    const_iv (EV_, UNDEF)
    const_iv (EV_, NONE)
    const_iv (EV_, TIMEOUT)
    const_iv (EV_, READ)
    const_iv (EV_, WRITE)
    const_iv (EV_, SIGNAL)
    const_iv (EV_, IDLE)
    const_iv (EV_, CHECK)
    const_iv (EV_, ERROR)

    const_iv (EV, LOOP_ONESHOT)
    const_iv (EV, LOOP_NONBLOCK)
    const_iv (EV, UNLOOP_ONE)
    const_iv (EV, UNLOOP_ALL)

    const_iv (EV, BACKEND_SELECT)
    const_iv (EV, BACKEND_POLL)
    const_iv (EV, BACKEND_EPOLL)
    const_iv (EV, BACKEND_KQUEUE)
    const_iv (EV, BACKEND_DEVPOLL)
    const_iv (EV, BACKEND_PORT)
    const_iv (EV, FLAG_AUTO)
    const_iv (EV, FLAG_NOENV)
  };

  for (civ = const_iv + sizeof (const_iv) / sizeof (const_iv [0]); civ-- > const_iv; )
    newCONSTSUB (stash, (char *)civ->name, newSViv (civ->iv));

  stash_watcher  = gv_stashpv ("EV::Watcher" , 1);
  stash_io       = gv_stashpv ("EV::IO"      , 1);
  stash_timer    = gv_stashpv ("EV::Timer"   , 1);
  stash_periodic = gv_stashpv ("EV::Periodic", 1);
  stash_signal   = gv_stashpv ("EV::Signal"  , 1);
  stash_idle     = gv_stashpv ("EV::Idle"    , 1);
  stash_prepare  = gv_stashpv ("EV::Prepare" , 1);
  stash_check    = gv_stashpv ("EV::Check"   , 1);
  stash_child    = gv_stashpv ("EV::Child"   , 1);

  {
    SV *sv = perl_get_sv ("EV::API", TRUE);
             perl_get_sv ("EV::API", TRUE); /* silence 5.10 warning */

    /* the poor man's shared library emulator */
    evapi.ver            = EV_API_VERSION;
    evapi.rev            = EV_API_REVISION;
    evapi.sv_fileno      = sv_fileno;
    evapi.sv_signum      = sv_signum;
    evapi.now            = ev_now;
    evapi.backend        = ev_backend;
    evapi.unloop         = ev_unloop;
    evapi.time           = ev_time;
    evapi.loop           = ev_loop;
    evapi.once           = ev_once;
    evapi.io_start       = ev_io_start;
    evapi.io_stop        = ev_io_stop;
    evapi.timer_start    = ev_timer_start;
    evapi.timer_stop     = ev_timer_stop;
    evapi.timer_again    = ev_timer_again;
    evapi.periodic_start = ev_periodic_start;
    evapi.periodic_stop  = ev_periodic_stop;
    evapi.signal_start   = ev_signal_start;
    evapi.signal_stop    = ev_signal_stop;
    evapi.idle_start     = ev_idle_start;
    evapi.idle_stop      = ev_idle_stop;
    evapi.prepare_start  = ev_prepare_start;
    evapi.prepare_stop   = ev_prepare_stop;
    evapi.check_start    = ev_check_start;
    evapi.check_stop     = ev_check_stop;
    evapi.child_start    = ev_child_start;
    evapi.child_stop     = ev_child_stop;
    evapi.ref            = ev_ref;
    evapi.unref          = ev_unref;

    sv_setiv (sv, (IV)&evapi);
    SvREADONLY_on (sv);
  }
#ifndef _WIN32
  pthread_atfork (0, 0, ev_default_fork);
#endif
}

NV ev_now ()

unsigned int ev_backend ()

NV ev_time ()

unsigned int ev_default_loop (unsigned int flags = ev_supported_backends ())

void ev_loop (int flags = 0)

void ev_unloop (int how = 1)

ev_io *io (SV *fh, int events, SV *cb)
	ALIAS:
        io_ns = 1
	CODE:
{
	int fd = sv_fileno (fh);
        CHECK_FD (fh, fd);

        RETVAL = e_new (sizeof (ev_io), cb);
        RETVAL->fh = newSVsv (fh);
        ev_io_set (RETVAL, fd, events);
        if (!ix) START (io, RETVAL);
}
	OUTPUT:
        RETVAL

ev_timer *timer (NV after, NV repeat, SV *cb)
	ALIAS:
        timer_ns = 1
        INIT:
        CHECK_REPEAT (repeat);
	CODE:
        RETVAL = e_new (sizeof (ev_timer), cb);
        ev_timer_set (RETVAL, after, repeat);
        if (!ix) START (timer, RETVAL);
	OUTPUT:
        RETVAL

SV *periodic (NV at, NV interval, SV *reschedule_cb, SV *cb)
	ALIAS:
        periodic_ns = 1
        INIT:
        CHECK_REPEAT (interval);
	CODE:
{
  	ev_periodic *w;
        w = e_new (sizeof (ev_periodic), cb);
        w->fh = SvTRUE (reschedule_cb) ? newSVsv (reschedule_cb) : 0;
        ev_periodic_set (w, at, interval, w->fh ? e_periodic_cb : 0);
        RETVAL = e_bless ((ev_watcher *)w, stash_periodic);
        if (!ix) START (periodic, w);
}
	OUTPUT:
        RETVAL

ev_signal *signal (Signal signum, SV *cb)
	ALIAS:
        signal_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_signal), cb);
        ev_signal_set (RETVAL, signum);
        if (!ix) START (signal, RETVAL);
	OUTPUT:
        RETVAL

ev_idle *idle (SV *cb)
	ALIAS:
        idle_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_idle), cb);
        ev_idle_set (RETVAL);
        if (!ix) START (idle, RETVAL);
	OUTPUT:
        RETVAL

ev_prepare *prepare (SV *cb)
	ALIAS:
        prepare_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_prepare), cb);
        ev_prepare_set (RETVAL);
        if (!ix) START (prepare, RETVAL);
	OUTPUT:
        RETVAL

ev_check *check (SV *cb)
	ALIAS:
        check_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_check), cb);
        ev_check_set (RETVAL);
        if (!ix) START (check, RETVAL);
	OUTPUT:
        RETVAL

ev_child *child (int pid, SV *cb)
	ALIAS:
        child_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_child), cb);
        ev_child_set (RETVAL, pid);
        if (!ix) START (child, RETVAL);
	OUTPUT:
        RETVAL

void once (SV *fh, int events, SV *timeout, SV *cb)
	CODE:
        ev_once (
           sv_fileno (fh), events,
           SvOK (timeout) ? SvNV (timeout) : -1.,
           e_once_cb,
           newSVsv (cb)
        );

PROTOTYPES: DISABLE

MODULE = EV		PACKAGE = EV::Watcher	PREFIX = ev_

int ev_is_active (ev_watcher *w)

int ev_is_pending (ev_watcher *w)

int keepalive (ev_watcher *w, int new_value = 0)
	CODE:
{
        RETVAL = w->flags & WFLAG_KEEPALIVE;
        new_value = new_value ? WFLAG_KEEPALIVE : 0;

        if (items > 1 && ((new_value ^ w->flags) & WFLAG_KEEPALIVE))
          {
            REF (w);
            w->flags = (w->flags & ~WFLAG_KEEPALIVE) | new_value;
            UNREF (w);
          }
}
	OUTPUT:
        RETVAL

SV *cb (ev_watcher *w, SV *new_cb = 0)
	CODE:
{
        RETVAL = newSVsv (w->cb_sv);

        if (items > 1)
          sv_setsv (w->cb_sv, new_cb);
}
	OUTPUT:
        RETVAL

SV *data (ev_watcher *w, SV *new_data = 0)
	CODE:
{
	RETVAL = w->data ? newSVsv (w->data) : &PL_sv_undef;

        if (items > 1)
          {
            SvREFCNT_dec (w->data);
            w->data = newSVsv (new_data);
          }
}
	OUTPUT:
        RETVAL

void trigger (ev_watcher *w, int revents = EV_NONE)
	CODE:
        w->cb (w, revents);

int priority (ev_watcher *w, int new_priority = 0)
	CODE:
{
        RETVAL = w->priority;

        if (items > 1)
          {
            int active = ev_is_active (w);

            if (new_priority < EV_MINPRI || new_priority > EV_MAXPRI)
              croak ("watcher priority out of range, value must be between %d and %d, inclusive", EV_MINPRI, EV_MAXPRI);

            if (active)
              {
                /* grrr. */
                PUSHMARK (SP);
                XPUSHs (ST (0));
                call_method ("stop", G_DISCARD | G_VOID);
              }

            ev_set_priority (w, new_priority);

            if (active)
              {
                PUSHMARK (SP);
                XPUSHs (ST (0));
                call_method ("start", G_DISCARD | G_VOID);
              }
          }
}
	OUTPUT:
        RETVAL

MODULE = EV		PACKAGE = EV::IO	PREFIX = ev_io_

void ev_io_start (ev_io *w)
	CODE:
        START (io, w);

void ev_io_stop (ev_io *w)
	CODE:
        STOP (io, w);

void DESTROY (ev_io *w)
	CODE:
        STOP (io, w);
        e_destroy (w);

void set (ev_io *w, SV *fh, int events)
	CODE:
{
        int active = ev_is_active (w);
	int fd = sv_fileno (fh);
        CHECK_FD (fh, fd);

        if (active) STOP (io, w);

        sv_setsv (w->fh, fh);
        ev_io_set (w, fd, events);

        if (active) START (io, w);
}

SV *fh (ev_io *w, SV *new_fh = 0)
	CODE:
{
        RETVAL = newSVsv (w->fh);

        if (items > 1)
          {
            int active = ev_is_active (w);
            if (active) STOP (io, w);

            sv_setsv (w->fh, new_fh);
            ev_io_set (w, sv_fileno (w->fh), w->events);

            if (active) START (io, w);
          }
}
	OUTPUT:
        RETVAL

int events (ev_io *w, int new_events = EV_UNDEF)
	CODE:
{
        RETVAL = w->events;

        if (items > 1)
          {
            int active = ev_is_active (w);
            if (active) STOP (io, w);

            ev_io_set (w, w->fd, new_events);

            if (active) START (io, w);
          }
}
	OUTPUT:
        RETVAL

MODULE = EV		PACKAGE = EV::Signal	PREFIX = ev_signal_

void ev_signal_start (ev_signal *w)
	CODE:
        START (signal, w);

void ev_signal_stop (ev_signal *w)
	CODE:
        STOP (signal, w);

void DESTROY (ev_signal *w)
	CODE:
        STOP (signal, w);
        e_destroy (w);

void set (ev_signal *w, SV *signal)
	CODE:
{
	Signal signum = sv_signum (signal); /* may croak here */
        int active = ev_is_active (w);

        if (active) STOP (signal, w);

        ev_signal_set (w, signum);

        if (active) START (signal, w);
}

int signal (ev_signal *w, SV *new_signal = 0)
	CODE:
{
        RETVAL = w->signum;

        if (items > 1)
          {
            Signal signum = sv_signum (new_signal); /* may croak here */
            int active = ev_is_active (w);
            if (active) STOP (signal, w);

            ev_signal_set (w, signum);

            if (active) START (signal, w);
          }
}
	OUTPUT:
        RETVAL

MODULE = EV		PACKAGE = EV::Timer	PREFIX = ev_timer_

void ev_timer_start (ev_timer *w)
        INIT:
        CHECK_REPEAT (w->repeat);
	CODE:
        START (timer, w);

void ev_timer_stop (ev_timer *w)
	CODE:
        STOP (timer, w);

void ev_timer_again (ev_timer *w)
        INIT:
        CHECK_REPEAT (w->repeat);
        CODE:
        REF (w);
        ev_timer_again (w);
        UNREF (w);

void DESTROY (ev_timer *w)
	CODE:
        STOP (timer, w);
        e_destroy (w);

void set (ev_timer *w, NV after, NV repeat = 0.)
        INIT:
        CHECK_REPEAT (repeat);
	CODE:
{
        int active = ev_is_active (w);
        if (active) STOP (timer, w);
        ev_timer_set (w, after, repeat);
        if (active) START (timer, w);
}

MODULE = EV		PACKAGE = EV::Periodic	PREFIX = ev_periodic_

void ev_periodic_start (ev_periodic *w)
        INIT:
        CHECK_REPEAT (w->interval);
	CODE:
        START (periodic, w);

void ev_periodic_stop (ev_periodic *w)
	CODE:
        STOP (periodic, w);

void ev_periodic_again (ev_periodic *w)
	CODE:
        REF (w);
        ev_periodic_again (w);
        UNREF (w);

void DESTROY (ev_periodic *w)
	CODE:
        STOP (periodic, w);
        e_destroy (w);

void set (ev_periodic *w, NV at, NV interval = 0., SV *reschedule_cb = &PL_sv_undef)
        INIT:
        CHECK_REPEAT (interval);
	CODE:
{
        int active = ev_is_active (w);
        if (active) STOP (periodic, w);

        SvREFCNT_dec (w->fh);
        w->fh = SvTRUE (reschedule_cb) ? newSVsv (reschedule_cb) : 0;
        ev_periodic_set (w, at, interval, w->fh ? e_periodic_cb : 0);

        if (active) START (periodic, w);
}

MODULE = EV		PACKAGE = EV::Idle	PREFIX = ev_idle_

void ev_idle_start (ev_idle *w)
	CODE:
        START (idle, w);

void ev_idle_stop (ev_idle *w)
	CODE:
        STOP (idle, w);

void DESTROY (ev_idle *w)
	CODE:
        STOP (idle, w);
        e_destroy (w);

MODULE = EV		PACKAGE = EV::Prepare	PREFIX = ev_check_

void ev_prepare_start (ev_prepare *w)
	CODE:
        START (prepare, w);

void ev_prepare_stop (ev_prepare *w)
	CODE:
        STOP (prepare, w);

void DESTROY (ev_prepare *w)
	CODE:
        STOP (prepare, w);
        e_destroy (w);

MODULE = EV		PACKAGE = EV::Check	PREFIX = ev_check_

void ev_check_start (ev_check *w)
	CODE:
        START (check, w);

void ev_check_stop (ev_check *w)
	CODE:
        STOP (check, w);

void DESTROY (ev_check *w)
	CODE:
        STOP (check, w);
        e_destroy (w);

MODULE = EV		PACKAGE = EV::Child	PREFIX = ev_child_

void ev_child_start (ev_child *w)
	CODE:
        START (child, w);

void ev_child_stop (ev_child *w)
	CODE:
        STOP (child, w);

void DESTROY (ev_child *w)
	CODE:
        STOP (child, w);
        e_destroy (w);

void set (ev_child *w, int pid)
	CODE:
{
        int active = ev_is_active (w);
        if (active) STOP (child, w);

        ev_child_set (w, pid);

        if (active) START (child, w);
}

int pid (ev_child *w, int new_pid = 0)
	CODE:
{
        RETVAL = w->pid;

        if (items > 1)
          {
            int active = ev_is_active (w);
            if (active) STOP (child, w);

            ev_child_set (w, new_pid);

            if (active) START (child, w);
          }
}
	OUTPUT:
        RETVAL


int rstatus (ev_child *w)
	ALIAS:
        rpid = 1
	CODE:
        RETVAL = ix ? w->rpid : w->rstatus;
	OUTPUT:
        RETVAL

#ifndef _WIN32

MODULE = EV		PACKAGE = EV::DNS	PREFIX = evdns_

BOOT:
{
  HV *stash = gv_stashpv ("EV::DNS", 1);

  static const struct {
    const char *name;
    IV iv;
  } *civ, const_iv[] = {
#   define const_iv(pfx, name) { # name, (IV) pfx ## name },
    const_iv (DNS_, ERR_NONE)
    const_iv (DNS_, ERR_FORMAT)
    const_iv (DNS_, ERR_SERVERFAILED)
    const_iv (DNS_, ERR_NOTEXIST)
    const_iv (DNS_, ERR_NOTIMPL)
    const_iv (DNS_, ERR_REFUSED)
    const_iv (DNS_, ERR_TRUNCATED)
    const_iv (DNS_, ERR_UNKNOWN)
    const_iv (DNS_, ERR_TIMEOUT)
    const_iv (DNS_, ERR_SHUTDOWN)
    const_iv (DNS_, IPv4_A)
    const_iv (DNS_, PTR)
    const_iv (DNS_, IPv6_AAAA)
    const_iv (DNS_, QUERY_NO_SEARCH)
    const_iv (DNS_, OPTION_SEARCH)
    const_iv (DNS_, OPTION_NAMESERVERS)
    const_iv (DNS_, OPTION_MISC)
    const_iv (DNS_, OPTIONS_ALL)
    const_iv (DNS_, NO_SEARCH)
  };

  for (civ = const_iv + sizeof (const_iv) / sizeof (const_iv [0]); civ-- > const_iv; )
    newCONSTSUB (stash, (char *)civ->name, newSViv (civ->iv));
}

int evdns_init ()

void evdns_shutdown (int fail_requests = 1)

const char *evdns_err_to_string (int err)

int evdns_nameserver_add (U32 address)

int evdns_count_nameservers ()

int evdns_clear_nameservers_and_suspend ()

int evdns_resume ()

int evdns_nameserver_ip_add (char *ip_as_string)

int evdns_resolve_ipv4 (const char *name, int flags, SV *cb)
	C_ARGS: name, flags, dns_cb, (void *)SvREFCNT_inc (cb)

int evdns_resolve_ipv6 (const char *name, int flags, SV *cb)
	C_ARGS: name, flags, dns_cb, (void *)SvREFCNT_inc (cb)

int evdns_resolve_reverse (SV *addr, int flags, SV *cb)
	ALIAS:
        evdns_resolve_reverse_ipv6 = 1
        CODE:
{
        STRLEN len;
        char *data = SvPVbyte (addr, len);
        if (len != (ix ? 16 : 4))
          croak ("ipv4/ipv6 address to be resolved must be given as 4/16 byte octet string");

        RETVAL = ix
          ? evdns_resolve_reverse_ipv6 ((struct in6_addr *)data, flags, dns_cb, (void *)SvREFCNT_inc (cb))
          : evdns_resolve_reverse      ((struct in_addr  *)data, flags, dns_cb, (void *)SvREFCNT_inc (cb));
}
	OUTPUT:
        RETVAL

int evdns_set_option (char *option, char *val, int flags)

int evdns_resolv_conf_parse (int flags, const char *filename)

#ifdef _WIN32

int evdns_config_windows_nameservers ()

#endif

void evdns_search_clear ()

void evdns_search_add (char *domain)

void evdns_search_ndots_set (int ndots)

#if 0

MODULE = EV		PACKAGE = EV::HTTP	PREFIX = evhttp_

BOOT:
{
  HV *stash = gv_stashpv ("EV::HTTP", 1);

  static const struct {
    const char *name;
    IV iv;
  } *civ, const_iv[] = {
#   define const_iv(pfx, name) { # name, (IV) pfx ## name },
    const_iv (HTTP_, OK)
    const_iv (HTTP_, NOCONTENT)
    const_iv (HTTP_, MOVEPERM)
    const_iv (HTTP_, MOVETEMP)
    const_iv (HTTP_, NOTMODIFIED)
    const_iv (HTTP_, BADREQUEST)
    const_iv (HTTP_, NOTFOUND)
    const_iv (HTTP_, SERVUNAVAIL)
    const_iv (EVHTTP_, REQ_OWN_CONNECTION)
    const_iv (EVHTTP_, PROXY_REQUEST)
    const_iv (EVHTTP_, REQ_GET)
    const_iv (EVHTTP_, REQ_POST)
    const_iv (EVHTTP_, REQ_HEAD)
    const_iv (EVHTTP_, REQUEST)
    const_iv (EVHTTP_, RESPONSE)
  };

  for (civ = const_iv + sizeof (const_iv) / sizeof (const_iv [0]); civ-- > const_iv; )
    newCONSTSUB (stash, (char *)civ->name, newSViv (civ->iv));
}

MODULE = EV		PACKAGE = EV::HTTP::Request	PREFIX = evhttp_request_

#HttpRequest new (SV *klass, SV *cb)

#void DESTROY (struct evhttp_request *req);

#endif

#endif







