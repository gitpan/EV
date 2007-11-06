#ifndef EV_API_H
#define EV_API_H

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef pTHX_
# define pTHX_
# define aTHX_
# define pTHX
# define aTHX
#endif

#define EV_COMMON			\
  SV *self; /* contains this struct */	\
  SV *cb_sv, *fh

#ifndef EV_PROTOTYPES
# define EV_PROTOTYPES 0
#endif

#define EV_STANDALONE   1
#define EV_MULTIPLICITY 0

#include <ev.h>

struct EVAPI {
  I32 ver;
  I32 rev;
#define EV_API_VERSION 1
#define EV_API_REVISION 0

  /* perl fh or fd int to fd */
  int (*sv_fileno) (SV *fh);
  /* signal number/name to signum */
  int (*sv_signum) (SV *fh);

  /* same as libev functions */
  ev_tstamp (*now)(void);
  ev_tstamp (*(time))(void);
  int (*method)(void);
  void (*loop)(int flags);
  void (*unloop)(int how);
  void (*once)(int fd, int events, ev_tstamp timeout, void (*cb)(int revents, void *arg), void *arg);
  void (*io_start)(struct ev_io *);
  void (*io_stop) (struct ev_io *);
  void (*timer_start)(struct ev_timer *);
  void (*timer_stop) (struct ev_timer *);
  void (*timer_again)(struct ev_timer *);
  void (*periodic_start)(struct ev_periodic *);
  void (*periodic_stop) (struct ev_periodic *);
  void (*signal_start)(struct ev_signal *);
  void (*signal_stop) (struct ev_signal *);
  void (*idle_start)(struct ev_idle *);
  void (*idle_stop) (struct ev_idle *);
  void (*prepare_start)(struct ev_prepare *);
  void (*prepare_stop) (struct ev_prepare *);
  void (*check_start)(struct ev_check *);
  void (*check_stop) (struct ev_check *);
  void (*child_start)(struct ev_child *);
  void (*child_stop) (struct ev_child *);
};

#if !EV_PROTOTYPES
# define sv_fileno(sv)         GEVAPI->sv_fileno (sv)
# define sv_signum(sv)         GEVAPI->sv_signum (sv)
# define ev_now()              GEVAPI->now ()
# define ev_time()             GEVAPI->(time) ()
# define ev_method()           GEVAPI->method ()
# define ev_loop(flags)        GEVAPI->loop (flags)
# define ev_unloop()           GEVAPI->unloop (int how)
# define ev_once(fd,events,timeout,cb,arg) GEVAPI->once ((fd), (events), (timeout), (cb), (arg))
# define ev_io_start(w)        GEVAPI->io_start (w)
# define ev_io_stop(w)         GEVAPI->io_stop  (w)
# define ev_timer_start(w)     GEVAPI->timer_start (w)
# define ev_timer_stop(w)      GEVAPI->timer_stop  (w)
# define ev_timer_again(w)     GEVAPI->timer_again (w)
# define ev_periodic_start(w)  GEVAPI->periodic_start (w)
# define ev_periodic_stop(w)   GEVAPI->periodic_stop  (w)
# define ev_signal_start(w)    GEVAPI->signal_start (w)
# define ev_signal_stop(w)     GEVAPI->signal_stop  (w)
# define ev_idle_start(w)      GEVAPI->idle_start (w)
# define ev_idle_stop(w)       GEVAPI->idle_stop  (w)
# define ev_prepare_start(w)   GEVAPI->prepare_start (w)
# define ev_prepare_stop(w)    GEVAPI->prepare_stop  (w)
# define ev_check_start(w)     GEVAPI->check_start (w)
# define ev_check_stop(w)      GEVAPI->check_stop  (w)
# define ev_child_start(w)     GEVAPI->child_start (w)
# define ev_child_stop(w)      GEVAPI->child_stop  (w)
#endif

static struct EVAPI *GEVAPI;

#define I_EV_API(YourName)                                                       \
STMT_START {                                                                     \
  SV *sv = perl_get_sv ("EV::API", 0);                                           \
  if (!sv) croak ("EV::API not found");                                          \
  GEVAPI = (struct EVAPI*) SvIV (sv);                                            \
  if (GEVAPI->ver != EV_API_VERSION                                              \
      || GEVAPI->rev < EV_API_REVISION)                                          \
    croak ("EV::API version mismatch (%d.%d vs. %d.%d) -- please recompile %s",  \
           GEVAPI->ver, GEVAPI->rev, EV_API_VERSION, EV_API_REVISION, YourName); \
} STMT_END

#endif

