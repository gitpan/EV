#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/*#include <netinet/in.h>*/

/* fix perl api breakage */
#undef signal
#undef sigaction

#define EV_PROTOTYPES 1
#define EV_USE_NANOSLEEP EV_USE_MONOTONIC
#define EV_H <ev.h>
#include "EV/EVAPI.h"

#define EV_SELECT_IS_WINSOCKET 0
#ifdef _WIN32
# define EV_SELECT_USE_FD_SET 0
# define NFDBITS PERL_NFDBITS
# define fd_mask Perl_fd_mask
#endif
/* due to bugs in OS X we have to use libev/ explicitly here */
#include "libev/ev.c"

#ifndef _WIN32
# include <pthread.h>
#endif

/* 5.10.0 */
#ifndef SvREFCNT_inc_NN
# define SvREFCNT_inc_NN(sv) SvREFCNT_inc (sv)
#endif

/* 5.6.x */
#ifndef SvRV_set
# define SvRV_set(a,b) SvRV ((a)) = (b)
#endif

#if __GNUC__ >= 3
# define expect(expr,value) __builtin_expect ((expr),(value))
#else
# define expect(expr,value) (expr)
#endif

#define expect_false(expr) expect ((expr) != 0, 0)
#define expect_true(expr)  expect ((expr) != 0, 1)

#define e_loop(w) INT2PTR (struct ev_loop *, SvIVX ((w)->loop))

#define WFLAG_KEEPALIVE 1

#define UNREF(w)				\
  if (!((w)->e_flags & WFLAG_KEEPALIVE)		\
      && !ev_is_active (w))			\
    ev_unref (e_loop (w));

#define REF(w)					\
  if (!((w)->e_flags & WFLAG_KEEPALIVE)		\
      && ev_is_active (w))			\
    ev_ref (e_loop (w));

#define START(type,w)				\
  do {						\
    UNREF (w);					\
    ev_ ## type ## _start (e_loop (w), w);	\
  } while (0)

#define STOP(type,w)				\
  do {						\
    REF (w);					\
    ev_ ## type ## _stop (e_loop (w), w);	\
  } while (0)

#define RESET(type,w,seta)			\
 do {                                           \
   int active = ev_is_active (w);               \
   if (active) STOP (type, w);                  \
   ev_ ## type ## _set seta;                    \
   if (active) START (type, w);                 \
 } while (0)

typedef int Signal;

static SV *default_loop_sv;

static struct EVAPI evapi;

static HV
  *stash_loop,
  *stash_watcher,
  *stash_io,
  *stash_timer,
  *stash_periodic,
  *stash_signal,
  *stash_child,
  *stash_stat,
  *stash_idle,
  *stash_prepare,
  *stash_check,
  *stash_embed,
  *stash_fork,
  *stash_async;

#ifndef SIG_SIZE
/* kudos to Slaven Rezic for the idea */
static char sig_size [] = { SIG_NUM };
# define SIG_SIZE (sizeof (sig_size) + 1)
#endif

static Signal
sv_signum (SV *sig)
{
  Signal signum;

  SvGETMAGIC (sig);

  for (signum = 1; signum < SIG_SIZE; ++signum)
    if (strEQ (SvPV_nolen (sig), PL_sig_name [signum]))
      return signum;

  signum = SvIV (sig);

  if (signum > 0 && signum < SIG_SIZE)
    return signum;

  return -1;
}

/////////////////////////////////////////////////////////////////////////////
// Event

static void e_cb (EV_P_ ev_watcher *w, int revents);

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

static SV *
e_get_cv (SV *cb_sv)
{
  HV *st;
  GV *gvp;
  CV *cv = sv_2cv (cb_sv, &st, &gvp, 0);

  if (!cv)
    croak ("EV watcher callback must be a CODE reference");

  return (SV *)cv;
}

static void *
e_new (int size, SV *cb_sv, SV *loop)
{
  SV *cv = cb_sv ? e_get_cv (cb_sv) : 0;
  ev_watcher *w;
  SV *self = NEWSV (0, size);
  SvPOK_only (self);
  SvCUR_set (self, size);

  w = (ev_watcher *)SvPVX (self);

  ev_init (w, cv ? e_cb : 0);

  w->loop    = SvREFCNT_inc (SvRV (loop));
  w->e_flags = WFLAG_KEEPALIVE;
  w->data    = 0;
  w->fh      = 0;
  w->cb_sv   = SvREFCNT_inc (cv);
  w->self    = self;

  return (void *)w;
}

static void
e_destroy (void *w_)
{
  ev_watcher *w = (ev_watcher *)w_;

  SvREFCNT_dec (w->loop ); w->loop  = 0;
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

static SV *sv_self_cache, *sv_events_cache;

static void
e_cb (EV_P_ ev_watcher *w, int revents)
{
  dSP;
  I32 mark = SP - PL_stack_base;
  SV *sv_self, *sv_events;

  if (expect_true (sv_self_cache))
    {
      sv_self = sv_self_cache; sv_self_cache = 0;
      SvRV_set (sv_self, SvREFCNT_inc_NN (w->self));
    }
  else
    {
      sv_self = newRV_inc (w->self); /* w->self MUST be blessed by now */
      SvREADONLY_on (sv_self);
    }

  if (expect_true (sv_events_cache))
    {
      sv_events = sv_events_cache; sv_events_cache = 0;
      SvIV_set (sv_events, revents);
    }
  else
    {
      sv_events = newSViv (revents);
      SvREADONLY_on (sv_events);
    }

  PUSHMARK (SP);
  EXTEND (SP, 2);
  PUSHs (sv_self);
  PUSHs (sv_events);

  PUTBACK;
  call_sv (w->cb_sv, G_DISCARD | G_VOID | G_EVAL);

  if (expect_false (SvREFCNT (sv_self) != 1 || sv_self_cache))
    SvREFCNT_dec (sv_self);
  else
    {
      SvREFCNT_dec (SvRV (sv_self));
      SvRV_set (sv_self, &PL_sv_undef);
      sv_self_cache = sv_self;
    }

  if (expect_false (SvREFCNT (sv_events) != 1 || sv_events_cache))
    SvREFCNT_dec (sv_events);
  else
    sv_events_cache = sv_events;

  if (expect_false (SvTRUE (ERRSV)))
    {
      SPAGAIN;
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
      SPAGAIN;
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

#define CHECK_REPEAT(repeat) if (repeat < 0.) \
  croak (# repeat " value must be >= 0");

#define CHECK_FD(fh,fd) if ((fd) < 0) \
  croak ("illegal file descriptor or filehandle (either no attached file descriptor or illegal value): %s", SvPV_nolen (fh));

#define CHECK_SIG(sv,num) if ((num) < 0) \
  croak ("illegal signal number or name: %s", SvPV_nolen (sv));

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
    const_iv (EV, FLAG_FORKCHECK)
  };

  for (civ = const_iv + sizeof (const_iv) / sizeof (const_iv [0]); civ-- > const_iv; )
    newCONSTSUB (stash, (char *)civ->name, newSViv (civ->iv));

  stash_loop     = gv_stashpv ("EV::Loop"    , 1);
  stash_watcher  = gv_stashpv ("EV::Watcher" , 1);
  stash_io       = gv_stashpv ("EV::IO"      , 1);
  stash_timer    = gv_stashpv ("EV::Timer"   , 1);
  stash_periodic = gv_stashpv ("EV::Periodic", 1);
  stash_signal   = gv_stashpv ("EV::Signal"  , 1);
  stash_idle     = gv_stashpv ("EV::Idle"    , 1);
  stash_prepare  = gv_stashpv ("EV::Prepare" , 1);
  stash_check    = gv_stashpv ("EV::Check"   , 1);
  stash_child    = gv_stashpv ("EV::Child"   , 1);
  stash_embed    = gv_stashpv ("EV::Embed"   , 1);
  stash_stat     = gv_stashpv ("EV::Stat"    , 1);
  stash_fork     = gv_stashpv ("EV::Fork"    , 1);
  stash_async    = gv_stashpv ("EV::Async"   , 1);

  {
    SV *sv = perl_get_sv ("EV::API", TRUE);
             perl_get_sv ("EV::API", TRUE); /* silence 5.10 warning */

    /* the poor man's shared library emulator */
    evapi.ver                  = EV_API_VERSION;
    evapi.rev                  = EV_API_REVISION;
    evapi.sv_fileno            = sv_fileno;
    evapi.sv_signum            = sv_signum;
    evapi.supported_backends   = ev_supported_backends ();
    evapi.recommended_backends = ev_recommended_backends ();
    evapi.embeddable_backends  = ev_embeddable_backends ();
    evapi.time_                = ev_time;
    evapi.sleep_               = ev_sleep;
    evapi.loop_new             = ev_loop_new;
    evapi.loop_destroy         = ev_loop_destroy;
    evapi.loop_fork            = ev_loop_fork;
    evapi.loop_count           = ev_loop_count;
    evapi.now                  = ev_now;
    evapi.now_update           = ev_now_update;
    evapi.backend              = ev_backend;
    evapi.unloop               = ev_unloop;
    evapi.ref                  = ev_ref;
    evapi.unref                = ev_unref;
    evapi.loop                 = ev_loop;
    evapi.once                 = ev_once;
    evapi.io_start             = ev_io_start;
    evapi.io_stop              = ev_io_stop;
    evapi.timer_start          = ev_timer_start;
    evapi.timer_stop           = ev_timer_stop;
    evapi.timer_again          = ev_timer_again;
    evapi.periodic_start       = ev_periodic_start;
    evapi.periodic_stop        = ev_periodic_stop;
    evapi.signal_start         = ev_signal_start;
    evapi.signal_stop          = ev_signal_stop;
    evapi.idle_start           = ev_idle_start;
    evapi.idle_stop            = ev_idle_stop;
    evapi.prepare_start        = ev_prepare_start;
    evapi.prepare_stop         = ev_prepare_stop;
    evapi.check_start          = ev_check_start;
    evapi.check_stop           = ev_check_stop;
    evapi.child_start          = ev_child_start;
    evapi.child_stop           = ev_child_stop;
    evapi.stat_start           = ev_stat_start;
    evapi.stat_stop            = ev_stat_stop;
    evapi.stat_stat            = ev_stat_stat;
    evapi.embed_start          = ev_embed_start;
    evapi.embed_stop           = ev_embed_stop;
    evapi.embed_sweep          = ev_embed_sweep;
    evapi.fork_start           = ev_fork_start;
    evapi.fork_stop            = ev_fork_stop;
    evapi.async_start          = ev_async_start;
    evapi.async_stop           = ev_async_stop;
    evapi.async_send           = ev_async_send;
    evapi.clear_pending        = ev_clear_pending;
    evapi.invoke               = ev_invoke;

    sv_setiv (sv, (IV)&evapi);
    SvREADONLY_on (sv);
  }
#ifndef _WIN32
  pthread_atfork (0, 0, ev_default_fork);
#endif
}

SV *ev_default_loop (unsigned int flags = 0)
	CODE:
{
	if (!default_loop_sv)
          {
            evapi.default_loop = ev_default_loop (flags);

            if (!evapi.default_loop)
              XSRETURN_UNDEF;

            default_loop_sv = sv_bless (newRV_noinc (newSViv (PTR2IV (evapi.default_loop))), stash_loop);
          }

        RETVAL = newSVsv (default_loop_sv);
}
	OUTPUT:
        RETVAL

void ev_default_destroy ()
	CODE:
        ev_default_destroy ();
        SvREFCNT_dec (default_loop_sv);
        default_loop_sv = 0;

unsigned int ev_supported_backends ()

unsigned int ev_recommended_backends ()

unsigned int ev_embeddable_backends ()

void ev_sleep (NV interval)

NV ev_time ()

NV ev_now ()
	C_ARGS: evapi.default_loop

void ev_now_update ()
	C_ARGS: evapi.default_loop

unsigned int ev_backend ()
	C_ARGS: evapi.default_loop

unsigned int ev_loop_count ()
	C_ARGS: evapi.default_loop

void ev_set_io_collect_interval (NV interval)
	C_ARGS: evapi.default_loop, interval

void ev_set_timeout_collect_interval (NV interval)
	C_ARGS: evapi.default_loop, interval

void ev_loop (int flags = 0)
	C_ARGS: evapi.default_loop, flags

void ev_unloop (int how = EVUNLOOP_ONE)
	C_ARGS: evapi.default_loop, how

void ev_feed_fd_event (int fd, int revents = EV_NONE)
	C_ARGS: evapi.default_loop, fd, revents

void ev_feed_signal_event (SV *signal)
	CODE:
{
  	Signal signum = sv_signum (signal);
        CHECK_SIG (signal, signum);

        ev_feed_signal_event (evapi.default_loop, signum);
}

ev_io *io (SV *fh, int events, SV *cb)
	ALIAS:
        io_ns = 1
	CODE:
{
	int fd = sv_fileno (fh);
        CHECK_FD (fh, fd);

        RETVAL = e_new (sizeof (ev_io), cb, default_loop_sv);
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
        RETVAL = e_new (sizeof (ev_timer), cb, default_loop_sv);
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
        w = e_new (sizeof (ev_periodic), cb, default_loop_sv);
        w->fh = SvTRUE (reschedule_cb) ? newSVsv (reschedule_cb) : 0;
        ev_periodic_set (w, at, interval, w->fh ? e_periodic_cb : 0);
        RETVAL = e_bless ((ev_watcher *)w, stash_periodic);
        if (!ix) START (periodic, w);
}
	OUTPUT:
        RETVAL

ev_signal *signal (SV *signal, SV *cb)
	ALIAS:
        signal_ns = 1
	CODE:
{
  	Signal signum = sv_signum (signal);
        CHECK_SIG (signal, signum);

        RETVAL = e_new (sizeof (ev_signal), cb, default_loop_sv);
        ev_signal_set (RETVAL, signum);
        if (!ix) START (signal, RETVAL);
}
	OUTPUT:
        RETVAL

ev_idle *idle (SV *cb)
	ALIAS:
        idle_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_idle), cb, default_loop_sv);
        ev_idle_set (RETVAL);
        if (!ix) START (idle, RETVAL);
	OUTPUT:
        RETVAL

ev_prepare *prepare (SV *cb)
	ALIAS:
        prepare_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_prepare), cb, default_loop_sv);
        ev_prepare_set (RETVAL);
        if (!ix) START (prepare, RETVAL);
	OUTPUT:
        RETVAL

ev_check *check (SV *cb)
	ALIAS:
        check_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_check), cb, default_loop_sv);
        ev_check_set (RETVAL);
        if (!ix) START (check, RETVAL);
	OUTPUT:
        RETVAL

ev_fork *fork (SV *cb)
	ALIAS:
        fork_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_fork), cb, default_loop_sv);
        ev_fork_set (RETVAL);
        if (!ix) START (fork, RETVAL);
	OUTPUT:
        RETVAL

ev_child *child (int pid, int trace, SV *cb)
	ALIAS:
        child_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_child), cb, default_loop_sv);
        ev_child_set (RETVAL, pid, trace);
        if (!ix) START (child, RETVAL);
	OUTPUT:
        RETVAL

ev_stat *stat (SV *path, NV interval, SV *cb)
	ALIAS:
        stat_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_stat), cb, default_loop_sv);
        RETVAL->fh = newSVsv (path);
        ev_stat_set (RETVAL, SvPVbyte_nolen (RETVAL->fh), interval);
        if (!ix) START (stat, RETVAL);
	OUTPUT:
        RETVAL

ev_embed *embed (struct ev_loop *loop, SV *cb = 0)
	ALIAS:
        embed_ns = 1
	CODE:
{
        if (!(ev_backend (loop) & ev_embeddable_backends ()))
          croak ("passed loop is not embeddable via EV::embed,");

        RETVAL = e_new (sizeof (ev_embed), cb, default_loop_sv);
        RETVAL->fh = newSVsv (ST (0));
        ev_embed_set (RETVAL, loop);
        if (!ix) START (embed, RETVAL);
}
	OUTPUT:
        RETVAL

ev_async *async (SV *cb)
	ALIAS:
        async_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_async), cb, default_loop_sv);
        ev_async_set (RETVAL);
        if (!ix) START (async, RETVAL);
	OUTPUT:
        RETVAL

void once (SV *fh, int events, SV *timeout, SV *cb)
	CODE:
        ev_once (
           evapi.default_loop,
           sv_fileno (fh), events,
           SvOK (timeout) ? SvNV (timeout) : -1.,
           e_once_cb,
           newSVsv (cb)
        );

PROTOTYPES: DISABLE

MODULE = EV		PACKAGE = EV::Watcher	PREFIX = ev_

int ev_is_active (ev_watcher *w)

int ev_is_pending (ev_watcher *w)

void ev_invoke (ev_watcher *w, int revents = EV_NONE)
	C_ARGS: e_loop (w), w, revents

int ev_clear_pending (ev_watcher *w)
	C_ARGS: e_loop (w), w

void ev_feed_event (ev_watcher *w, int revents = EV_NONE)
	C_ARGS: e_loop (w), w, revents

int keepalive (ev_watcher *w, int new_value = 0)
	CODE:
{
        RETVAL = w->e_flags & WFLAG_KEEPALIVE;
        new_value = new_value ? WFLAG_KEEPALIVE : 0;

        if (items > 1 && ((new_value ^ w->e_flags) & WFLAG_KEEPALIVE))
          {
            REF (w);
            w->e_flags = (w->e_flags & ~WFLAG_KEEPALIVE) | new_value;
            UNREF (w);
          }
}
	OUTPUT:
        RETVAL

SV *cb (ev_watcher *w, SV *new_cb = 0)
	CODE:
{
        if (items > 1)
          {
            new_cb = e_get_cv (new_cb);
            RETVAL = newRV_noinc (w->cb_sv);
            w->cb_sv = SvREFCNT_inc (new_cb);
          }
        else
          RETVAL = newRV_inc (w->cb_sv);
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

SV *loop (ev_watcher *w)
	CODE:
	RETVAL = newRV_inc (w->loop);
	OUTPUT:
        RETVAL

int priority (ev_watcher *w, int new_priority = 0)
	CODE:
{
        RETVAL = w->priority;

        if (items > 1)
          {
            int active = ev_is_active (w);

            if (active)
              {
                /* grrr. */
                PUSHMARK (SP);
                XPUSHs (ST (0));
                PUTBACK;
                call_method ("stop", G_DISCARD | G_VOID);
              }

            ev_set_priority (w, new_priority);

            if (active)
              {
                PUSHMARK (SP);
                XPUSHs (ST (0));
                PUTBACK;
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
	int fd = sv_fileno (fh);
        CHECK_FD (fh, fd);

        sv_setsv (w->fh, fh);
        RESET (io, w, (w, fd, events));
}

SV *fh (ev_io *w, SV *new_fh = 0)
	CODE:
{
        if (items > 1)
          {
            int fd = sv_fileno (new_fh);
            CHECK_FD (new_fh, fd);

            RETVAL = w->fh;
            w->fh = newSVsv (new_fh);

            RESET (io, w, (w, fd, w->events));
          }
        else
          RETVAL = newSVsv (w->fh);
}
	OUTPUT:
        RETVAL

int events (ev_io *w, int new_events = EV_UNDEF)
	CODE:
{
        RETVAL = w->events;

        if (items > 1)
          RESET (io, w, (w, w->fd, new_events));
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
	Signal signum = sv_signum (signal);
        CHECK_SIG (signal, signum);

        RESET (signal, w, (w, signum));
}

int signal (ev_signal *w, SV *new_signal = 0)
	CODE:
{
        RETVAL = w->signum;

        if (items > 1)
          {
            Signal signum = sv_signum (new_signal);
            CHECK_SIG (new_signal, signum);

            RESET (signal, w, (w, signum));
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
        ev_timer_again (e_loop (w), w);
        UNREF (w);

void DESTROY (ev_timer *w)
	CODE:
        STOP (timer, w);
        e_destroy (w);

void set (ev_timer *w, NV after, NV repeat = 0.)
        INIT:
        CHECK_REPEAT (repeat);
	CODE:
        RESET (timer, w, (w, after, repeat));

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
        ev_periodic_again (e_loop (w), w);
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
        SvREFCNT_dec (w->fh);
        w->fh = SvTRUE (reschedule_cb) ? newSVsv (reschedule_cb) : 0;

        RESET (periodic, w, (w, at, interval, w->fh ? e_periodic_cb : 0));
}

NV at (ev_periodic *w)
	CODE:
        RETVAL = ev_periodic_at (w);
	OUTPUT:
        RETVAL

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

MODULE = EV		PACKAGE = EV::Prepare	PREFIX = ev_prepare_

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

MODULE = EV		PACKAGE = EV::Fork	PREFIX = ev_fork_

void ev_fork_start (ev_fork *w)
	CODE:
        START (fork, w);

void ev_fork_stop (ev_fork *w)
	CODE:
        STOP (fork, w);

void DESTROY (ev_fork *w)
	CODE:
        STOP (fork, w);
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

void set (ev_child *w, int pid, int trace)
	CODE:
        RESET (child, w, (w, pid, trace));

int pid (ev_child *w)
	ALIAS:
        rpid    = 1
        rstatus = 2
	CODE:
        RETVAL = ix == 0 ? w->pid
               : ix == 1 ? w->rpid
               :           w->rstatus;
	OUTPUT:
        RETVAL

MODULE = EV		PACKAGE = EV::Stat	PREFIX = ev_stat_

void ev_stat_start (ev_stat *w)
	CODE:
        START (stat, w);

void ev_stat_stop (ev_stat *w)
	CODE:
        STOP (stat, w);

void DESTROY (ev_stat *w)
	CODE:
        STOP (stat, w);
        e_destroy (w);

void set (ev_stat *w, SV *path, NV interval)
	CODE:
{
        sv_setsv (w->fh, path);
	RESET (stat, w, (w, SvPVbyte_nolen (w->fh), interval));
}

SV *path (ev_stat *w, SV *new_path = 0)
	CODE:
{
        RETVAL = SvREFCNT_inc (w->fh);

        if (items > 1)
          {
            SvREFCNT_dec (w->fh);
            w->fh = newSVsv (new_path);
            RESET (stat, w, (w, SvPVbyte_nolen (w->fh), w->interval));
          }
}
	OUTPUT:
        RETVAL

NV interval (ev_stat *w, NV new_interval = 0.)
	CODE:
{
        RETVAL = w->interval;

        if (items > 1)
          RESET (stat, w, (w, SvPVbyte_nolen (w->fh), new_interval));
}
	OUTPUT:
        RETVAL

void prev (ev_stat *w)
	ALIAS:
        stat = 1
        attr = 2
	PPCODE:
{
	ev_statdata *s = ix ? &w->attr : &w->prev;

        if (ix == 1)
          ev_stat_stat (e_loop (w), w);
        else if (!s->st_nlink)
          errno = ENOENT;

        PL_statcache.st_dev   = s->st_nlink;
        PL_statcache.st_ino   = s->st_ino;
        PL_statcache.st_mode  = s->st_mode;
        PL_statcache.st_nlink = s->st_nlink;
        PL_statcache.st_uid   = s->st_uid;
        PL_statcache.st_gid   = s->st_gid;
        PL_statcache.st_rdev  = s->st_rdev;
        PL_statcache.st_size  = s->st_size;
        PL_statcache.st_atime = s->st_atime;
        PL_statcache.st_mtime = s->st_mtime;
        PL_statcache.st_ctime = s->st_ctime;

        if (GIMME_V == G_SCALAR)
          XPUSHs (boolSV (s->st_nlink));
        else if (GIMME_V == G_ARRAY && s->st_nlink)
          {
            EXTEND (SP, 13);
            PUSHs (sv_2mortal (newSViv (s->st_dev)));
            PUSHs (sv_2mortal (newSViv (s->st_ino)));
            PUSHs (sv_2mortal (newSVuv (s->st_mode)));
            PUSHs (sv_2mortal (newSVuv (s->st_nlink)));
            PUSHs (sv_2mortal (newSViv (s->st_uid)));
            PUSHs (sv_2mortal (newSViv (s->st_gid)));
            PUSHs (sv_2mortal (newSViv (s->st_rdev)));
            PUSHs (sv_2mortal (newSVnv ((NV)s->st_size)));
            PUSHs (sv_2mortal (newSVnv (s->st_atime)));
            PUSHs (sv_2mortal (newSVnv (s->st_mtime)));
            PUSHs (sv_2mortal (newSVnv (s->st_ctime)));
            PUSHs (sv_2mortal (newSVuv (4096)));
            PUSHs (sv_2mortal (newSVnv ((NV)((s->st_size + 4095) / 4096))));
          }
}

MODULE = EV		PACKAGE = EV::Embed	PREFIX = ev_embed_

void ev_embed_start (ev_embed *w)
	CODE:
        START (embed, w);

void ev_embed_stop (ev_embed *w)
	CODE:
        STOP (embed, w);

void DESTROY (ev_embed *w)
	CODE:
        STOP (embed, w);
        e_destroy (w);

void set (ev_embed *w, struct ev_loop *loop)
	CODE:
{
        sv_setsv (w->fh, ST (1));
	RESET (embed, w, (w, loop));
}

SV *other (ev_embed *w)
	CODE:
        RETVAL = newSVsv (w->fh);
	OUTPUT:
        RETVAL

void ev_embed_sweep (ev_embed *w)
	C_ARGS: e_loop (w), w

MODULE = EV		PACKAGE = EV::Async	PREFIX = ev_async_

void ev_async_start (ev_async *w)
	CODE:
        START (async, w);

void ev_async_stop (ev_async *w)
	CODE:
        STOP (async, w);

void DESTROY (ev_async *w)
	CODE:
        STOP (async, w);
        e_destroy (w);

void ev_async_send (ev_async *w)
	C_ARGS: e_loop (w), w

SV *ev_async_async_pending (ev_async *w)
        CODE:
        RETVAL = boolSV (ev_async_pending (w));
	OUTPUT:
        RETVAL

MODULE = EV		PACKAGE = EV::Loop	PREFIX = ev_

SV *new (SV *klass, unsigned int flags = 0)
	CODE:
{
	struct ev_loop *loop = ev_loop_new (flags);

        if (!loop)
          XSRETURN_UNDEF;

        RETVAL = sv_bless (newRV_noinc (newSViv (PTR2IV (loop))), stash_loop);
}
	OUTPUT:
        RETVAL

void DESTROY (struct ev_loop *loop)
	CODE:
        if (loop != evapi.default_loop) /* global destruction sucks */
          ev_loop_destroy (loop);

void ev_loop_fork (struct ev_loop *loop)

void ev_loop_verify (struct ev_loop *loop)

NV ev_now (struct ev_loop *loop)

void ev_now_update (struct ev_loop *loop)

void ev_set_io_collect_interval (struct ev_loop *loop, NV interval)

void ev_set_timeout_collect_interval (struct ev_loop *loop, NV interval)

unsigned int ev_backend (struct ev_loop *loop)

unsigned int ev_loop_count (struct ev_loop *loop)

void ev_loop (struct ev_loop *loop, int flags = 0)

void ev_unloop (struct ev_loop *loop, int how = 1)

void ev_feed_fd_event (struct ev_loop *loop, int fd, int revents = EV_NONE)

#if 0

void ev_feed_signal_event (struct ev_loop *loop, SV *signal)
	CODE:
{
  	Signal signum = sv_signum (signal);
        CHECK_SIG (signal, signum);

        ev_feed_signal_event (loop, signum);
}

#endif

ev_io *io (struct ev_loop *loop, SV *fh, int events, SV *cb)
	ALIAS:
        io_ns = 1
	CODE:
{
	int fd = sv_fileno (fh);
        CHECK_FD (fh, fd);

        RETVAL = e_new (sizeof (ev_io), cb, ST (0));
        RETVAL->fh = newSVsv (fh);
        ev_io_set (RETVAL, fd, events);
        if (!ix) START (io, RETVAL);
}
	OUTPUT:
        RETVAL

ev_timer *timer (struct ev_loop *loop, NV after, NV repeat, SV *cb)
	ALIAS:
        timer_ns = 1
        INIT:
        CHECK_REPEAT (repeat);
	CODE:
        RETVAL = e_new (sizeof (ev_timer), cb, ST (0));
        ev_timer_set (RETVAL, after, repeat);
        if (!ix) START (timer, RETVAL);
	OUTPUT:
        RETVAL

SV *periodic (struct ev_loop *loop, NV at, NV interval, SV *reschedule_cb, SV *cb)
	ALIAS:
        periodic_ns = 1
        INIT:
        CHECK_REPEAT (interval);
	CODE:
{
  	ev_periodic *w;
        w = e_new (sizeof (ev_periodic), cb, ST (0));
        w->fh = SvTRUE (reschedule_cb) ? newSVsv (reschedule_cb) : 0;
        ev_periodic_set (w, at, interval, w->fh ? e_periodic_cb : 0);
        RETVAL = e_bless ((ev_watcher *)w, stash_periodic);
        if (!ix) START (periodic, w);
}
	OUTPUT:
        RETVAL

#if 0

ev_signal *signal (struct ev_loop *loop, SV *signal, SV *cb)
	ALIAS:
        signal_ns = 1
	CODE:
{
  	Signal signum = sv_signum (signal);
        CHECK_SIG (signal, signum);

        RETVAL = e_new (sizeof (ev_signal), cb, ST (0));
        ev_signal_set (RETVAL, signum);
        if (!ix) START (signal, RETVAL);
}
	OUTPUT:
        RETVAL

#endif

ev_idle *idle (struct ev_loop *loop, SV *cb)
	ALIAS:
        idle_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_idle), cb, ST (0));
        ev_idle_set (RETVAL);
        if (!ix) START (idle, RETVAL);
	OUTPUT:
        RETVAL

ev_prepare *prepare (struct ev_loop *loop, SV *cb)
	ALIAS:
        prepare_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_prepare), cb, ST (0));
        ev_prepare_set (RETVAL);
        if (!ix) START (prepare, RETVAL);
	OUTPUT:
        RETVAL

ev_check *check (struct ev_loop *loop, SV *cb)
	ALIAS:
        check_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_check), cb, ST (0));
        ev_check_set (RETVAL);
        if (!ix) START (check, RETVAL);
	OUTPUT:
        RETVAL

ev_fork *fork (struct ev_loop *loop, SV *cb)
	ALIAS:
        fork_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_fork), cb, ST (0));
        ev_fork_set (RETVAL);
        if (!ix) START (fork, RETVAL);
	OUTPUT:
        RETVAL

ev_child *child (struct ev_loop *loop, int pid, int trace, SV *cb)
	ALIAS:
        child_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_child), cb, ST (0));
        ev_child_set (RETVAL, pid, trace);
        if (!ix) START (child, RETVAL);
	OUTPUT:
        RETVAL

ev_stat *stat (struct ev_loop *loop, SV *path, NV interval, SV *cb)
	ALIAS:
        stat_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_stat), cb, ST (0));
        RETVAL->fh = newSVsv (path);
        ev_stat_set (RETVAL, SvPVbyte_nolen (RETVAL->fh), interval);
        if (!ix) START (stat, RETVAL);
	OUTPUT:
        RETVAL

ev_embed *embed (struct ev_loop *loop, struct ev_loop *other, SV *cb = 0)
	ALIAS:
        embed_ns = 1
	CODE:
{
        if (!(ev_backend (other) & ev_embeddable_backends ()))
          croak ("passed loop is not embeddable via EV::embed,");

        RETVAL = e_new (sizeof (ev_embed), cb, ST (0));
        RETVAL->fh = newSVsv (ST (1));
        ev_embed_set (RETVAL, other);
        if (!ix) START (embed, RETVAL);
}
	OUTPUT:
        RETVAL

ev_async *async (struct ev_loop *loop, SV *cb)
	ALIAS:
        async_ns = 1
	CODE:
        RETVAL = e_new (sizeof (ev_async), cb, ST (0));
        ev_async_set (RETVAL);
        if (!ix) START (async, RETVAL);
	OUTPUT:
        RETVAL

void once (struct ev_loop *loop, SV *fh, int events, SV *timeout, SV *cb)
	CODE:
        ev_once (
           loop,
           sv_fileno (fh), events,
           SvOK (timeout) ? SvNV (timeout) : -1.,
           e_once_cb,
           newSVsv (cb)
        );

