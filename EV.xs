#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <math.h>
#include <netinet/in.h>

#include <sys/time.h>
#include <time.h>
#include <event.h>
#include <evdns.h>

/* workaround for evhttp.h requiring obscure bsd headers */
#ifndef TAILQ_ENTRY
#define TAILQ_ENTRY(type)                                               \
struct {                                                                \
        struct type *tqe_next;  /* next element */                      \
        struct type **tqe_prev; /* address of previous next element */  \
}
#endif /* !TAILQ_ENTRY */
#include <evhttp.h>

#define EV_NONE 0
#define EV_UNDEF -1

#define TIMEOUT_NONE HUGE_VAL

typedef struct event_base *Base;

static HV *stash_base, *stash_event;

static double tv_get (struct timeval *tv)
{
  return tv->tv_sec + tv->tv_usec * 1e-6;
}

static void tv_set (struct timeval *tv, double val)
{
  tv->tv_sec  = (long)val;
  tv->tv_usec = (long)((val - (double)tv->tv_sec) * 1e6);

}

/////////////////////////////////////////////////////////////////////////////
// Event

typedef struct ev {
  struct event ev;
  SV *cb, *fh;
  SV *self; /* contains this struct */
  double timeout;
  double interval;
  unsigned char active;
  unsigned char abstime;
} *Event;

static double
e_now ()
{
  struct timeval tv;
  gettimeofday (&tv, 0);

  return tv_get (&tv);
}

static void e_cb (int fd, short events, void *arg);

static int sv_fileno (SV *fh)
{
  SvGETMAGIC (fh);

  if (SvROK (fh))
    fh = SvRV (fh);

  if (SvTYPE (fh) == SVt_PVGV)
    return PerlIO_fileno (IoIFP (sv_2io (fh)));

  if (SvIOK (fh))
    return SvIV (fh);

  return -1;
}

static Event
e_new (SV *fh, short events, SV *cb)
{
  int fd = sv_fileno (fh);
  Event ev;
  SV *self = NEWSV (0, sizeof (struct ev));
  SvPOK_only (self);
  SvCUR_set (self, sizeof (struct ev));

  ev = (Event)SvPVX (self);

  ev->fh       = newSVsv (fh);
  ev->cb       = newSVsv (cb);
  ev->self     = self;
  ev->timeout  = TIMEOUT_NONE;
  ev->interval = 0.;
  ev->abstime  = 0;
  ev->active   = 0;

  event_set (&ev->ev, fd, events, e_cb, (void *)ev);

  return ev;
}

static struct timeval *
e_tv (Event ev)
{
  static struct timeval tv;
  double to = ev->timeout;

  if (to == TIMEOUT_NONE)
    return 0;

  if (ev->abstime)
    {
      double now = e_now ();

      if (ev->interval)
        ev->timeout = (to += ceil ((now - to) / ev->interval) * ev->interval);

      to -= now;
    }
  else if (to < 0.)
    to = 0.;

  tv_set (&tv, to);

  return &tv;
}

static SV *e_self (Event ev)
{
  SV *rv;

  if (SvOBJECT (ev->self))
    rv = newRV_inc (ev->self);
  else
    {
      rv = newRV_noinc (ev->self);
      sv_bless (rv, stash_event);
      SvREADONLY_on (ev->self);
    }

  return rv;
}

static int
e_start (Event ev)
{
  if (ev->active) event_del (&ev->ev);
  ev->active = 1;
  return event_add (&ev->ev, e_tv (ev));
}

static int e_stop (Event ev)
{
  return ev->active
    ? (ev->active = 0), event_del (&ev->ev)
    : 0;
}

static void
e_cb (int fd, short events, void *arg)
{
  struct ev *ev = (struct ev*)arg;
  dSP;

  ENTER;
  SAVETMPS;

  if (!(ev->ev.ev_events & EV_PERSIST) || (events & EV_TIMEOUT))
    ev->active = 0;

  PUSHMARK (SP);
  EXTEND (SP, 2);
  PUSHs (sv_2mortal (e_self (ev)));
  PUSHs (sv_2mortal (newSViv (events)));
  PUTBACK;
  call_sv (ev->cb, G_DISCARD | G_VOID | G_EVAL);

  if (ev->interval && !ev->active)
    e_start (ev);

  FREETMPS;

  if (SvTRUE (ERRSV))
    {
      PUSHMARK (SP);
      PUTBACK;
      call_sv (get_sv ("EV::DIED", 1), G_DISCARD | G_VOID | G_EVAL | G_KEEPERR);
    }

  LEAVE;
}

/////////////////////////////////////////////////////////////////////////////
// DNS

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

/////////////////////////////////////////////////////////////////////////////
// XS interface functions

MODULE = EV		PACKAGE = EV		PREFIX = event_

BOOT:
{
  HV *stash = gv_stashpv ("EV", 1);

  static const struct {
    const char *name;
    IV iv;
  } *civ, const_iv[] = {
#   define const_iv(pfx, name) { # name, (IV) pfx ## name },
    const_iv (EV_, NONE)
    const_iv (EV_, TIMEOUT)
    const_iv (EV_, READ)
    const_iv (EV_, WRITE)
    const_iv (EV_, SIGNAL)
    const_iv (EV_, PERSIST)
    const_iv (EV, LOOP_ONCE)
    const_iv (EV, LOOP_NONBLOCK)
    const_iv (EV, BUFFER_READ)
    const_iv (EV, BUFFER_WRITE)
    const_iv (EV, BUFFER_EOF)
    const_iv (EV, BUFFER_ERROR)
    const_iv (EV, BUFFER_TIMEOUT)
  };

  for (civ = const_iv + sizeof (const_iv) / sizeof (const_iv [0]); civ-- > const_iv; )
    newCONSTSUB (stash, (char *)civ->name, newSViv (civ->iv));

  stash_base  = gv_stashpv ("EV::Base" , 1);
  stash_event = gv_stashpv ("EV::Event", 1);
}

double now ()
	CODE:
        RETVAL = e_now ();
	OUTPUT:
        RETVAL

const char *version ()
	ALIAS:
        method = 1
	CODE:
        RETVAL = ix ? event_get_method () : event_get_version ();
	OUTPUT:
        RETVAL

Base event_init ()

int event_priority_init (int npri)

int event_dispatch ()

int event_loop (int flags = 0)

int event_loopexit (double after = 0)
	CODE:
{
        struct timeval tv;
        tv_set (&tv, after);
        event_loopexit (&tv);
}

Event event (SV *cb)
	CODE:
        RETVAL = e_new (NEWSV (0, 0), 0, cb);
	OUTPUT:
        RETVAL

Event io (SV *fh, short events, SV *cb)
	ALIAS:
        io_ns = 1
	CODE:
        RETVAL = e_new (fh, events, cb);
        if (!ix) e_start (RETVAL);
	OUTPUT:
        RETVAL

Event timer (double after, int repeat, SV *cb)
	ALIAS:
        timer_ns = 1
	CODE:
        RETVAL = e_new (NEWSV (0, 0), 0, cb);
        RETVAL->timeout  = after;
        RETVAL->interval = repeat;
        if (!ix) e_start (RETVAL);
	OUTPUT:
        RETVAL

Event timer_abs (double at, double interval, SV *cb)
	ALIAS:
        timer_abs_ns = 1
	CODE:
        RETVAL = e_new (NEWSV (0, 0), 0, cb);
        RETVAL->timeout  = at;
        RETVAL->interval = interval;
        RETVAL->abstime  = 1;
        if (!ix) e_start (RETVAL);
	OUTPUT:
        RETVAL

Event signal (SV *signal, SV *cb)
	ALIAS:
        signal_ns = 1
	CODE:
        RETVAL = e_new (signal, EV_SIGNAL | EV_PERSIST, cb);
        if (!ix) e_start (RETVAL);
	OUTPUT:
        RETVAL

PROTOTYPES: DISABLE


MODULE = EV		PACKAGE = EV::Base	PREFIX = event_base_

Base new ()
	CODE:
        RETVAL = event_init ();
	OUTPUT:
        RETVAL

int event_base_dispatch (Base base)

int event_base_loop (Base base, int flags = 0)

int event_base_loopexit (Base base, double after)
	CODE:
{
        struct timeval tv;
        tv.tv_sec  = (long)after;
        tv.tv_usec = (long)(after - tv.tv_sec) * 1e6;
        event_base_loopexit (base, &tv);
}

int event_base_priority_init (Base base, int npri)

void event_base_set (Base base, Event ev)
	C_ARGS: base, &ev->ev

void DESTROY (Base base)
	CODE:
        /*event_base_free (base);*/ /* causes too many problems */


MODULE = EV		PACKAGE = EV::Event	PREFIX = event_

int event_priority_set (Event ev, int pri)
	C_ARGS: &ev->ev, pri

int event_add (Event ev, double timeout = TIMEOUT_NONE)
	CODE:
        ev->timeout = timeout;
        ev->abstime = 0;
        RETVAL = e_start (ev);
	OUTPUT:
        RETVAL

int event_start (Event ev)
	CODE:
        RETVAL = e_start (ev);
	OUTPUT:
        RETVAL

int event_del (Event ev)
	ALIAS:
        stop = 0
	CODE:
        RETVAL = e_stop (ev);
	OUTPUT:
        RETVAL

void DESTROY (Event ev)
	CODE:
        e_stop (ev);
        SvREFCNT_dec (ev->cb);
        SvREFCNT_dec (ev->fh);

SV *cb (Event ev, SV *new_cb = 0)
	CODE:
        RETVAL = newSVsv (ev->cb);
        if (items > 1)
          sv_setsv (ev->cb, new_cb);
	OUTPUT:
        RETVAL

SV *fh (Event ev, SV *new_fh = 0)
	ALIAS:
        signal = 0
	CODE:
        RETVAL = newSVsv (ev->fh);
        if (items > 1)
          {
            if (ev->active) event_del (&ev->ev);
            sv_setsv (ev->fh, new_fh);
            ev->ev.ev_fd = sv_fileno (ev->fh);
            if (ev->active) event_add (&ev->ev, e_tv (ev));
          }
	OUTPUT:
        RETVAL

short events (Event ev, short new_events = EV_UNDEF)
	CODE:
        RETVAL = ev->ev.ev_events;
        if (items > 1)
          {
            if (ev->active) event_del (&ev->ev);
            ev->ev.ev_events = new_events;
            if (ev->active) event_add (&ev->ev, e_tv (ev));
          }
	OUTPUT:
        RETVAL

double timeout (Event ev, double new_timeout = 0., int repeat = 0)
	CODE:
        RETVAL = ev->timeout;
        if (items > 1)
          {
            if (ev->active) event_del (&ev->ev);
            ev->timeout  = new_timeout;
            ev->interval = repeat;
            ev->abstime  = 0;
            if (ev->active) event_add (&ev->ev, e_tv (ev));
          }
	OUTPUT:
        RETVAL

void timeout_abs (Event ev, double at, double interval = 0.)
	CODE:
        if (ev->active) event_del (&ev->ev);
        ev->timeout  = at;
        ev->interval = interval;
        ev->abstime  = 1;
        if (ev->active) event_add (&ev->ev, e_tv (ev));


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

#ifdef MS_WINDOWS

int evdns_config_windows_nameservers ()

#endif

void evdns_search_clear ()

void evdns_search_add (char *domain)

void evdns_search_ndots_set (int ndots)


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








