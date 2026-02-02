import types/url

when defined(freebsd):
  proc c_setproctitle(fmt: cstring) {.header: "<unistd.h>", importc:
    "setproctitle", varargs.}
elif defined(netbsd) or defined(openbsd):
  proc c_setproctitle(fmt: cstring) {.header: "<stdlib.h>", importc:
    "setproctitle", varargs.}
elif defined(linux):
  let PR_SET_NAME {.importc, header: "<sys/prctl.h>", nodecl.}: cint
  proc prctl(option: cint; arg2, arg3, arg4, arg5: culong): cint {.importc,
    header: "<sys/prctl.h>".}

proc setProcessTitle*(s: string) =
  when defined(freebsd) or defined(netbsd) or defined(openbsd):
    c_setproctitle("%s", cstring(s))
  elif defined(linux):
    discard prctl(PR_SET_NAME, cast[culong](cstring(s)), 0, 0, 0)

when defined(linux):
  import utils/twtstr

proc setBufferProcessTitle*(url: URL) =
  when defined(linux):
    # linux truncates to 15 chars; try to preserve important info
    const initTitle = "cha buf "
    var title = initTitle
    var hostname = url.hostname
    if hostname.startsWith("www."):
      hostname.delete(0.."www.".high)
    title &= hostname
    if title.len > initTitle.len:
      title &= ' '
    title &= url.pathname.afterLast('/')
    setProcessTitle(title)
  else:
    setProcessTitle("cha buffer " & $url)
