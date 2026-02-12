{.push raises: [].}

import std/posix

import local/select
import monoucha/fromjs
import monoucha/jsbind
import monoucha/quickjs
import monoucha/tojs
import server/bufferiface
import server/loaderiface
import types/jsopt
import types/opt
import types/url

type
  #TODO this belongs in JS
  Tab* = ref object
    head* {.jsget.}: Container
    current* {.jsget.}: Container
    prev* {.jsget.}: Tab
    next* {.jsget.}: Tab

  Container* = ref object
    prev* {.jsget.}: Container # public
    next* {.jsget.}: Container # public
    iface* {.jsget.}: BufferInterface # private
    init* {.jsget.}: BufferInit # private
    replace*: Container
    # if we are referenced by another container, replaceRef is set so that we
    # can clear ourselves on discard
    replaceRef*: Container
    sourcepair*: Container # pointer to buffer with a source view (may be nil)
    select* {.jsgetset.}: Select # public (get)
    currentSelection* {.jsget.}: Highlight # public
    tab*: Tab

  NavDirection* = enum
    ndPrev = "prev"
    ndNext = "next"
    ndAny = "any"

jsDestructor(Container)
jsDestructor(Tab)

proc newContainer*(init: BufferInit; tab: Tab): Container =
  return Container(init: init, tab: tab)

# shallow clone of buffer
proc clone*(container: Container; newurl: URL; loader: FileLoader):
    tuple[fd: cint, c: Container] =
  if container.iface == nil:
    return (-1, nil)
  var sv {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    return (-1, nil)
  let url = if newurl != nil:
    newurl
  else:
    container.init.url
  let res = container.iface.clone(url, sv[1])
  discard close(sv[1])
  if res.isErr:
    return (-1, nil)
  let nc = Container(
    tab: container.tab,
    currentSelection: container.currentSelection,
    init: newBufferInit(url, container.init)
  )
  (sv[0], nc)

proc append*(this, other: Container) =
  if other.prev != nil:
    other.prev.next = other.next
  if other.next != nil:
    other.next.prev = other.prev
  other.next = this.next
  if this.next != nil:
    this.next.prev = other
  other.prev = this
  this.next = other

proc remove*(this: Container) =
  if this.prev != nil:
    this.prev.next = this.next
  if this.next != nil:
    this.next.prev = this.prev
  if this.tab.current == this:
    this.tab.current = if this.prev != nil: this.prev else: this.next
  if this.tab.head == this:
    this.tab.head = this.next
  this.tab = nil
  this.next = nil
  this.prev = nil

# tab may be nil.
# Returns the old tab if it has become empty.
proc setTab*(container: Container; tab: Tab): Tab =
  let oldTab = container.tab
  if oldTab != nil:
    container.remove()
  container.tab = tab
  if tab != nil:
    if tab.current == nil:
      tab.current = container
      tab.head = container
    else:
      tab.current.append(container)
  if oldTab != nil and oldTab.current == nil:
    return oldTab
  nil

# private
proc unsetReplace(container: Container): Container {.jsfunc.} =
  let replace = container.replace
  if replace != nil:
    replace.replaceRef = nil
    container.replace = nil
  return replace

# private
proc setReplace(container, replace: Container) {.jsfunc.} =
  container.replace = replace
  replace.replaceRef = container

# private
proc setCurrentSelection(ctx: JSContext; container: Container;
    val: JSValueConst): Opt[void] {.jsfset: "currentSelection".} =
  if JS_IsNull(val):
    container.currentSelection = nil
  else:
    ?ctx.fromJS(val, container.currentSelection)
  ok()

# private
proc closeSelect(container: Container) {.jsfunc.} =
  container.select = nil

# public
proc find*(container: Container; dir: NavDirection): Container {.jsfunc.} =
  return case dir
  of ndPrev: container.prev
  of ndNext: container.next
  of ndAny:
    if container.prev != nil: container.prev else: container.next

proc addContainerModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(Container, name = "Buffer")
  ?ctx.registerType(Tab)
  ok()

{.pop.} # raises: []
