# macOS has no functional poll (it chokes on /dev/tty), so we instead
# emulate it with select.

{.passc: "-D_DARWIN_UNLIMITED_SELECT".}

import std/posix

type PollData* = object
  currentFd: cint
  nfds: cint
  fds: seq[cshort]
  readPool: seq[uint8]
  writePool: seq[uint8]
  errorPool: seq[uint8]

template read(ctx: PollData): ptr TFdSet =
  cast[ptr TFdSet](unsafeAddr ctx.readPool[0])

template write(ctx: PollData): ptr TFdSet =
  cast[ptr TFdSet](unsafeAddr ctx.writePool[0])

template error(ctx: PollData): ptr TFdSet =
  cast[ptr TFdSet](unsafeAddr ctx.errorPool[0])

proc setFd(ctx: PollData; fd: cint) =
  let events = ctx.fds[int(fd)]
  if (events and POLLIN) != 0:
    FD_SET(fd, ctx.read[])
  else:
    FD_CLR(fd, ctx.read[])
  if (events and POLLOUT) != 0:
    FD_SET(fd, ctx.write[])
  else:
    FD_CLR(fd, ctx.write[])
  if (events and POLLERR) != 0:
    FD_SET(fd, ctx.error[])
  else:
    FD_CLR(fd, ctx.error[])

iterator events*(ctx: var PollData): tuple[fd: cint; revents: cshort] =
  # Note that unlike in standard poll, ctx.nfds may change during the
  # iteration, and this is not a bug.  In this case we just set up the
  # event post-addition.
  ctx.currentFd = 0
  while ctx.currentFd < ctx.nfds:
    let fd = ctx.currentFd
    var revents = cshort(0)
    if FD_ISSET(fd, ctx.read[]) != 0:
      revents = revents or POLLIN
    if FD_ISSET(fd, ctx.write[]) != 0:
      revents = revents or POLLOUT
    if FD_ISSET(fd, ctx.error[]) != 0:
      revents = revents or POLLERR
    if revents != 0:
      yield (fd, revents)
    ctx.setFd(fd)
    inc ctx.currentFd

proc register*(ctx: var PollData; fd: cint; events: cshort) =
  if fd >= ctx.nfds:
    let onfds = ctx.nfds
    ctx.nfds = fd + 1
    if ctx.currentFd == onfds: # not in events iterator
      ctx.currentFd = ctx.nfds
  let infds = int(ctx.nfds)
  if infds > ctx.fds.len:
    if ctx.fds.len == 0:
      ctx.fds.setLen(64)
    else:
      ctx.fds.setLen(max(ctx.fds.len * 2, ((infds + 7) div 8) * 8))
    assert ctx.fds.len mod 8 == 0
    let sz = ctx.fds.len div 8
    ctx.readPool.setLen(sz)
    ctx.writePool.setLen(sz)
    ctx.errorPool.setLen(sz)
  ctx.fds[int(fd)] = events or POLLERR
  # currentFd is always the next fd to be set.
  # if it points to us or a previous fd, then we must not set the event,
  # or else we'll get bogus events
  if fd < ctx.currentFd:
    ctx.setFd(fd)

proc register*(ctx: var PollData; fd: int; events: cshort) =
  ctx.register(cint(fd), events)

proc unregister*(ctx: var PollData; fd: int) =
  ctx.fds[fd] = cshort(0)
  # Mimic behavior of poll_standard: if unregister is called on an event
  # that has not been read yet, destroy said event.
  ctx.setFd(cint(fd))

proc clear*(ctx: var PollData) =
  # Do *not* set nfds to 0, because this is called from inside the
  # `events' iterator.
  for fd, it in ctx.fds.mpairs:
    it = 0
    ctx.setFd(cint(fd))

proc trim(ctx: var PollData) =
  var i = ctx.nfds - 1
  while i >= 0:
    if ctx.fds[int(i)] != 0:
      break
    dec i
  ctx.nfds = i + 1

proc poll*(ctx: var PollData; timeout: cint) =
  ctx.trim()
  var tv = Timeval(
    tv_sec: Time(max(timeout div 1000, 0)),
    tv_usec: Suseconds(max((timeout mod 1000) * 1000, 0))
  )
  let ptv = if timeout != -1: addr tv else: nil
  if ctx.nfds == 0:
    discard select(ctx.nfds, nil, nil, nil, ptv)
  else:
    let res = select(ctx.nfds, ctx.read, ctx.write, ctx.error, ptv)
    if res < 0: # error
      for fd in cint(0) ..< ctx.nfds:
        FD_CLR(fd, ctx.read[])
        FD_CLR(fd, ctx.write[])
        FD_CLR(fd, ctx.error[])
