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

#define EV_COMMON				\
  int flags; /* cheap on 64 bit systems */	\
  SV *self; /* contains this struct */		\
  SV *cb_sv, *fh, *data;

#ifndef EV_PROTOTYPES
# define EV_PROTOTYPES 0
#endif

#define EV_STANDALONE   1
#define EV_MULTIPLICITY 0

#include <ev.h>

struct EVAPI {
  I32 ver;
  I32 rev;
#define EV_API_VERSION 3
#define EV_API_REVISION 0

  /* perl fh or fd int to fd */
  int (*sv_fileno) (SV *fh);
  /* signal number/name to signum */
  int (*sv_signum) (SV *fh);

  /* same as libev functions */
  ev_tstamp (*now)(EV_P);
  ev_tstamp (*(time))(void);
  unsigned int (*backend)(EV_P);
  void (*loop)(EV_P_ int flags);
  void (*unloop)(EV_P_ int how);
  void (*ref)(EV_P);
  void (*unref)(EV_P);
  void (*once)(EV_P_ int fd, int events, ev_tstamp timeout, void (*cb)(int revents, void *arg), void *arg);
  int  (*clear_pending)(EV_P_ void *);
  void (*invoke)(EV_P_ void *, int);
  void (*io_start)(EV_P_ ev_io *);
  void (*io_stop) (EV_P_ ev_io *);
  void (*timer_start)(EV_P_ ev_timer *);
  void (*timer_stop) (EV_P_ ev_timer *);
  void (*timer_again)(EV_P_ ev_timer *);
  void (*periodic_start)(EV_P_ ev_periodic *);
  void (*periodic_stop) (EV_P_ ev_periodic *);
  void (*signal_start)(EV_P_ ev_signal *);
  void (*signal_stop) (EV_P_ ev_signal *);
  void (*child_start)(EV_P_ ev_child *);
  void (*child_stop) (EV_P_ ev_child *);
  void (*stat_start)(EV_P_ ev_stat *);
  void (*stat_stop) (EV_P_ ev_stat *);
  void (*stat_stat) (EV_P_ ev_stat *);
  void (*idle_start)(EV_P_ ev_idle *);
  void (*idle_stop) (EV_P_ ev_idle *);
  void (*prepare_start)(EV_P_ ev_prepare *);
  void (*prepare_stop) (EV_P_ ev_prepare *);
  void (*check_start)(EV_P_ ev_check *);
  void (*check_stop) (EV_P_ ev_check *);
};

#if !EV_PROTOTYPES
# define sv_fileno(sv)         GEVAPI->sv_fileno (sv)
# define sv_signum(sv)         GEVAPI->sv_signum (sv)
# define ev_now(loop)          GEVAPI->now (loop)
# define ev_time()             GEVAPI->(time) ()
# define ev_backend(loop)      GEVAPI->backend (loop)
# define ev_loop(flags)        GEVAPI->loop (flags)
# define ev_unloop(how)        GEVAPI->unloop (how)
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
# define ev_stat_start(w)      GEVAPI->stat_start (w)
# define ev_stat_stop(w)       GEVAPI->stat_stop  (w)
# define ev_stat_stat(w)       GEVAPI->stat_stat  (w)
# define ev_ref(loop)          GEVAPI->ref   (loop)
# define ev_unref(loop)        GEVAPI->unref (loop)
# define ev_clear_pending(w)   GEVAPI->clear_pending (w)
# define ev_invoke(w,rev)      GEVAPI->invoke (w, rev)
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

