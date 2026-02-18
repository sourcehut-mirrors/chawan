# poll wrapper for sane systems.
# std only merged working bindings recently, so for now we have to bind
# it on our own.

from std/posix import TPollfd, POLLNVAL

# NB: nfds_t on SVR4 was unsigned long, but BSDs use unsigned int.
# Linux and Haiku emulate the former, BSDs inherit the latter.
# ...except bionic copy-pasted from BSD headers, so it uses the latter
# too.
# Since there are less SVR4 imitators than BSD descendants, I'll use
# the latter as the fallback.
when defined(linux) and not defined(android) or defined(haiku):
  type nfds_t {.importc, header: "<poll.h>".} = culong
else:
  type nfds_t {.importc, header: "<poll.h>".} = cuint

const sizeofNfdsT = sizeof(nfds_t)
{.emit: """
NIM_STATIC_ASSERT(`sizeofNfdsT` == sizeof(nfds_t),
  "nfds_t size mismatch; please report at https://todo.sr.ht/~bptato/chawan");
""".}

proc poll(fds: ptr TPollfd; nfds: nfds_t; timeout: cint): cint
  {.cdecl, importc, header: "<poll.h>".}

type PollData* = object
  fds: seq[TPollfd]

iterator events*(ctx: var PollData): tuple[fd: cint; revents: cshort] =
  let L = ctx.fds.len
  for i in 0 ..< L:
    let event = ctx.fds[i]
    if event.fd == -1 or ctx.fds[i].revents == 0:
      continue
    assert (event.revents and POLLNVAL) == 0
    yield (event.fd, event.revents)

proc register*(ctx: var PollData; fd: int; events: cshort) =
  if fd >= ctx.fds.len:
    let olen = ctx.fds.len
    ctx.fds.setLen(fd + 1)
    for i in olen ..< fd:
      ctx.fds[i].fd = -1
  ctx.fds[fd].fd = cint(fd)
  ctx.fds[fd].events = events

proc register*(ctx: var PollData; fd: cint; events: cshort) =
  ctx.register(int(fd), events)

proc unregister*(ctx: var PollData; fd: int) =
  ctx.fds[fd].fd = -1

proc trim(ctx: var PollData) =
  var i = ctx.fds.high
  while i >= 0:
    if ctx.fds[i].fd != -1:
      break
    dec i
  ctx.fds.setLen(i + 1)

proc clear*(ctx: var PollData) =
  # Do *not* set fds' len to 0, because this is called from inside the
  # `events' iterator.
  for it in ctx.fds.mitems:
    it.fd = -1
    it.revents = 0

proc poll*(ctx: var PollData; timeout: cint) =
  ctx.trim()
  let fds = if ctx.fds.len > 0: addr ctx.fds[0] else: nil
  let res = poll(fds, nfds_t(ctx.fds.len), timeout)
  if res < 0: # error
    for event in ctx.fds.mitems:
      event.revents = 0
