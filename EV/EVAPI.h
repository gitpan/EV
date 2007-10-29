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

#include <event.h>

struct EVAPI {
  I32 ver;
  I32 rev;
#define EV_API_VERSION 1
#define EV_API_REVISION 0

  /* return the current wallclock time */
  double (*now)(void);

  /* wait for a single event, without registering an event watcher */
  /* if timeout is < 0, do wait indefinitely */
  void (*once)(int fd, short events, double timeout, void (*cb)(int, short, void *), void *arg);

  /* same as event_loop */
  int (*loop)(int flags);
};

/*
 * usage examples:
 *
 * now = GEVAPI->now ();
 * GEVAPI->once (5, EV_READ, 60, my_cb, (void *)mysv);
 */

static struct EVAPI *GEVAPI;

#define I_EV_API(YourName)                                                       \
STMT_START {                                                                     \
  SV *sv = perl_get_sv ("EV::API", 0);                                           \
  if (!sv) croak ("EV::API not found");                                          \
  GEVAPI = (struct CoroAPI*) SvIV (sv);                                          \
  if (GEVAPI->ver != EV_API_VERSION                                              \
      || GEVAPI->rev < EV_API_REVISION)                                          \
    croak ("EV::API version mismatch (%d.%d vs. %d.%d) -- please recompile %s",  \
           GEVAPI->ver, GEVAPI->rev, EV_API_VERSION, EV_API_REVISION, YourName); \
} STMT_END

#endif

