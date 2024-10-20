from std/posix import TPollfd, POLLNVAL

# NB: nfds_t on SVR4 this was unsigned long, but BSDs use unsigned int.
# Linux and Haiku emulate the former, BSDs inherit the latter.
# Since there are less SVR4 imitators than BSD descendants, I'll just
# hardcode the former.
when defined(linux) or defined(haiku):
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

iterator events*(ctx: PollData): TPollfd =
  let L = ctx.fds.len
  for i in 0 ..< L:
    let event = ctx.fds[i]
    if event.fd == -1 or ctx.fds[i].revents == 0:
      continue
    assert (event.revents and POLLNVAL) == 0
    yield event

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
  ctx.fds.setLen(0)

proc poll*(ctx: var PollData; timeout: cint) =
  ctx.trim()
  let fds = addr ctx.fds[0]
  let res = poll(fds, nfds_t(ctx.fds.len), timeout)
  if res < 0: # error
    for event in ctx.fds.mitems:
      event.revents = 0
