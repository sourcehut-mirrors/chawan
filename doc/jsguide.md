# JavaScript guide

Chawan uses QuickJS for implementing JavaScript, related APIs, and parts of
the browser shell itself.  This document details how this works, as well as
what one should be careful about when working with related code.

Note: this is aimed at people interested in modifying Chawan's code.
If you are looking for the JS command API, check [**cha-api**](api.md)(7)
instead.

## WebIDL

Major browsers tend to use WebIDL for binding generation.  In Chawan
however, we use Nim macros as a more ergonomic and powerful alternative.
That being said, you should always consult the relevant
[standards](hacking.md#resources) when implementing interfaces.

The WebIDL *interface* concept is mostly identical to Chawan's *class*,
which in turn is built upon QuickJS's `JSClass` feature.  Usually, our
documentation uses *class* when talking about the implementation, and
*interface* when talking about the user-facing concept, but it's not 100%
consistent.

## JS types

A JS type must be defined as follows:

```nim
import monoucha/jsref

type
  MyClass = JSRef[MyClassObj]

  MyClassObj {.pure.} = object
    someField: int
```

Note the `.pure` field; this is necessary for Nim 1.6.14 to generate
correct code.

Constructing such an object is performed using the `jsNew` template:

```nim
jsClassDef(MyClass): # see below for jsClassDef
  proc newMyClass(): MyClass {.jsctor.} =
    let obj = jsNew MyClassObj(
      someField: 1234
    )
    if obj != nil: # obj may be nil
      obj.initialize()
    obj
```

Note that in theory, `jsNew` may return a `nil` pointer.  (In practice,
it currently never does, but I am considering a "memory limit" config
option which would make it possible.)  Accordingly, returning `nil` from a
constructor throws an OOM exception.

Also note that, due to an implementation detail, a `jsmark` hook (detailed
[below](#jsmark-mark-functions)) can run *before* the class object is
assigned to the pointer.  The practical consequence is that if your object
owns any `ref` fields with `JSValue`s to mark, `jsmark` *must* first check
if the `ref` is nil before marking any sub-fields.

## Implementing interfaces

WebIDL interfaces (also known as a "class") are implemented in Chawan using
the `jsClassDef` macro.  Example:

```nim
jsClassDef(Node):
  jsextends EventTargetDef

  proc firstChild(this: Node): Node {.jsfget.} =
    # ...

  proc lastChild(this: Node): Node {.jsfget.} =
    # ...

  proc cloneNode(ctx: JSContext; this: Node): Node {.jsfunc.} =
    # ...
```

The macro will produce a function wrapper for each pragma-annotated
function, and store the result in the `NodeDef` variable (i.e., the type
name and then `Def`).  Some variants are:

* `jsClassNameDef`: same as `jsClassDef`, but the JS interface's name will
  be a string you supply instead of the Nim type's name.  Useful if
  the interface's name would clash with another commonly used Nim type
  (e.g., `File`).

* `jsPublicClassDef`: same as `jsClassDef`, but the result is "public",
  i.e., you can use it from another module.

* `jsPublicClassNameDef`: combination of the above two.

* `jsNamespaceDef`: creates a WebIDL namespace.  This is just an object
  with a bunch of static functions (`.jsstfunc`).

* `jsClassRaw`: creates a "raw" class that isn't bound to a specific Nim
  type.  It can be used without setting an opaque Nim pointer at all, or by
  setting any other arbitrary pointer.

  Note that this is very hard to use correctly, because JavaScript can
  usually hold any type longer than its parent.  For example, if you're
  holding an unrelated `JSRef` in an instantiated class, you'll probably
  want to store the pointer from `JS_DupForeignObject`, and then
  `JS_FreeForeignObject` inside `.jsfin` (don't forget `.jsmark` either).

  Also note that a raw class derived from a non-raw class behaves like a
  non-raw class.  This behavior is subject to change.

After declaring such a class, you also have to register it.
This is typically done inside an `add[...]Module` procedure, such as:

```nim
proc registerEventModule(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(EventDef)
  ?ctx.registerClass(UIEventDef)
  # ...
  ok()
```

Always make sure that parent interfaces are registered before their
children; if you fail to do so, `registerClass` will assert.

For registering namespaces, use `registerNamespace`.

Sometimes, it is useful to derive two unrelated WebIDL interfaces from
the same parent Nim object.  For example, `HTMLCollection` and
`HTMLAllCollection` have similar behavior, and are therefore both derived
from `Collection`.  Still, this is just an implementation detail, and we
don't actually want to expose `Collection` to the web.

In such classes, use `registerFakeClass`; the runtime will treat this as
a class, but from the JS side, it will look as if the prototype were the
class's prototype.  Such classes must be treated as "abstract", i.e., you
shouldn't instantiate the class itself with `jsNew`, only derived classes.

### Commands & function pragmas

Inside a `jsClassDef` (etc.), it is possible to define getters, setters,
functions, etc. either by issuing a `js[...]` *command*, or by defining a
procedure with a `.js[...]` pragma attached (as seen above).

Commands look like this:

```nim
jsClassDef(TreeWalker):
  jsextends CollectionLikeDef

  jsget TreeWalker, root
  jsget TreeWalker, whatToShow
  jsget TreeWalker, filter
  jsgetset TreeWalker, currentNode
```

Currently implemented commands are:

* `jsextends` denotes the parent class's definition object.

* `jsget`, `jsset`, `jsgetset` generate a setter, getter, or both for
  an object field.  For now, both the type and the field must be declared.
  (TODO at the moment this is 100% redundant...)

  It is possible to expose a field under a different name by passing three
  or more string parameters, e.g.

  ```nim
  jsget MouseEvent clientX, "clientX", "x"
  ```

  In this case, the field `clientX` is made accessible through the getter
  `clientX` as well as `x`.

* Finally, `jsufget` declares a field with a
  [`LegacyUnforgeable`](#the-legacyunforgeable-property) name.

For implementing anything more complex, you'll have to use a procedure with
a pragma.

### jsfunc, jsstfunc: functions

The simplest pragma is `.jsfunc`.  This marks the procedure as a member
of the JS interface associated with the first parameter's type.

Example:

```nim
jsClassDef(TreeWalker):
  proc parentNode(this: TreeWalker): Opt[Node] {.jsfunc.} =
    var node = this.currentNode
    # ...
    ok(node)
```

This will result in a function `parentNode()` being defined on
`TreeWalker`.  Using a different name for the JS function than the Nim
procedure is also possible:

```nim
jsClassDef(TreeWalker):
  proc parentNodeImpl(this: TreeWalker): Opt[Node] {.jsfunc: "parentNode".} =
    var node = this.currentNode
    # ...
    ok(node)
```

The first parameter of a `jsfunc` must either be of the interface's type
itself, one of its parents, or JSValueConst.  Whatever this may be, the
object is nonetheless guaranteed to have a class id associated with the
interface defined.

Subsequent parameters may be of any type supported by `toJS`.  (If a type
isn't supported, you can implement a converter yourself.)

It is also possible to insert a "zeroeth" parameter to get a reference to
the current JS context.  This is useful if you want to access state global
to the JS context without storing a backreference to the global object:

```nim
jsClassDef(TreeWalker):
  proc parentNode(ctx: JSContext; this: TreeWalker): Opt[Node] {.jsfunc.} =
    var node = this.currentNode
    # do something with ctx...
    ok(node)
```

TODO: really the ctx should be the second parameter so it doesn't mess with
UFCS.

A variant of `jsfunc` is `jsstfunc`; this generates a static function for
which no `this` value is generated.

It is also possible to use `varargs` in `.jsfunc`s:

```nim
jsNamespaceDef(console):
  proc log(ctx: JSContext; ss: varargs[JSValueConst]) {.jsstfunc.} =
    discard # can be called like `console.log("a", "b", "c", "d")`
```

Only `JSValueConst` varargs are supported.

### jsctor: constructors

The `.jsctor` pragma is used to define a constructor for a specific
type:

```nim
jsClassDef(CustomElementRegistry):
  proc newCustomElementRegistry*(): CustomElementRegistry {.jsctor.} =
    jsNew CustomElementRegistryObj(scoped: true)
```

`.jsctor`, like other pragmas, supports the same "zeroeth" JSContext
parameter as [jsfunc](#jsfunc-jsstfunc-functions), which is useful when the
global object is needed for resource allocation.

### jsfget, jsfset: custom property reflectors

The `.jsfget` and `.jsfset` pragmas can be used to define custom
getter/setter functions.

Like `jsget` and `jsset` commands, they appear as regular getters and
setters in JS.  However, instead of automatically reflecting a property,
`.jsfget` and `.jsfset` allows you to write custom code to handle property
accesses.

Example:

```nim
jsClassDef(Attr):
  proc value(attr: Attr): string {.jsfget.} =
    return attr.data.value

  proc setValue(ctx: JSContext; attr: Attr; ds: DOMString) {.
      jsfset: "value".} =
    attr.ownerElement.setAttr(ctx, attr.data.name.view(), ds)
```

### Magic functions

`.jsmfget`, `.jsmfset` and `.jsmffunc` used to declare magic functions.
The idea is that for functions with different names that behave similarly,
we don't necessarily need yet another function declaration, instead we get
passed a 16-bit value used to discriminate between the functions.

The magic parameter always comes after the `this` parameter.  e.g.,

```nim
jsClassDef(HTMLTableElement):
  proc createTableChild(ctx: JSContext; this: HTMLTableElement;
      tagType: TagType): Element {.jsmfunc("createCaption", ttCaption),
      jsmfunc("createTHead", ttThead), jsmfunc("createTBody", ttTbody),
      jsmfunc("createTFoot", ttTfoot).} =
    # simplified for demonstration purposes
    var element = this.asParentNode.findFirstChildOf(tagType)
    if element == nil:
      element = this.asNode.document.newHTMLElement(tagType).asElement
      if element != nil:
        this.asParentNode.insert(element.asNode, nil, ctx)
    return element
```

### The LegacyUnforgeable property

The pragmas `.jsuffunc`, `.jsufget` and `.jsuffget` correspond to the WebIDL
[`[LegacyUnforgeable]`](https://webidl.spec.whatwg.org/#LegacyUnforgeable)
property.

Concretely, this means that the function (or getter) is defined on
instances of the interface, not on the interface (i.e. object prototype)
as a non-configurable property.  Even more concretely, this means that the
function (or getter) cannot be changed by JavaScript code.

### jsgetownprop, jsgetprop, jssetprop, jsdelprop, jshasprop, jspropnames: magic functions

`.jsgetownprop`, `.jsgetprop`, `.jssetprop`, `.jsdelprop`, `.jshasprop` and
`.jspropnames` generate bindings for magic functions.  These are mainly
useful for collections, where you want to provide custom behavior for
property accesses.

In general, you'll only need `.jsgetownprop` and `jspropnames`, all others
are optimizations.  Sometimes we use `.jssetprop` too but I'm not sure
if it's correct...

### jsfin: object finalizers

The `.jsfin` pragma can be used to clean up resources used by objects
at the end of their lifetime.  It is also useful for emulating "weak"
references.

The first parameter must be a JSRuntime, while the second parameter is a
reference to the object in question.  Only one `.jsfin` procedure per
reference type is allowed, but parent `.jsfin` finalizers are inherited.

Do note that `JSRef` and `JSValue` members are automatically collected,
and therefore do not need a `jsfin`.  The exception is `seq[JSValue]`
or more generally, `JSValue`s stored in any sub-object/sub-ref field.

Example:

```nim
jsClassDef(CollectionLike):
  proc finalize(rt: JSRuntime; collection: CollectionLike) {.jsfin.} =
    # remove live collections from the document
    if collection.document != nil:
      let collection = cast[ptr CollectionLikeObj](collection)
      if collection.prev != nil:
        collection.prev.next = collection.next
      else:
        collection.document.liveCollectionsHead = collection.next
      if collection.next != nil:
        collection.next.prev = collection.prev
```

### jsmark: mark functions

`jsmark` assists the QuickJS GC in breaking up cyclic references.  Usually,
`jsClassDef` will generate these automatically for you, except if your
object has a `seq` of `JSValue`s or `JSRef`s, or `JSValue`s/`JSRef`s in an
object field.

In such cases, you should define `jsmark` to prevent leaks:

```nim
jsClassDef(Collection):
  jsextends CollectionLikeDef

  proc mark(rt: JSRuntime; this: Collection; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for node in this.snapshot:
      rt.markObj(node, markFunc)
```

(Note that the fields `jsmark` automatically finds is a subset of what
`jsfin` automatically does.  The primary reason is that `jsfin` uses ARC's
`=destroy` generator facility, while `jsmark` relies on a macro.

While it would be possible to extend `jsmark` to support all cases, the
resulting compilation speed slowdown would be unacceptable.)

Inside `jsmark`, `JSRef` refcounting operations *must* be avoided.
This obviously means things like `let a = this.a` are forbidden; less
obviously, a lot of iterators copy:

* `std/table` - prefer `utils/tabutil` instead
* `array[n, JSRef[T]]` - iterate using `myitems` instead (note: this is not
  necessary with `seq`, only `array`)
* linked lists - these you'll have to cast to `ptr` I'm afraid

---

## toJS, fromJS

While in many cases it is possible to avoid using `JSValue`s, Chawan does
not go out of its way to completely eliminate them.

In particular, handling `JSValue`s is unavoidable when:

* You want to do something with `eval()`'s result.
* You want to call a callback.
* You want a dynamically typed variable, e.g. for "union" types.

### Option vs Opt

In converters, the conventional way to represent null values is to
`import std/options`, `import monoucha/jsnull`, and use `Option[T]`.

This applies to e.g. strings (which are not nilable in Nim), but also to
refs in fromJS so that a registered ref object parameter of a `.jsfunc` is
not nullable unless you wrap it in an `Option`.

`Opt[T]` in contrast is used for representing errors using Chawan's result
type defined in `types/opt`.

Typically, it is returned from fromJS as `Opt[void]`.  It is also possible
to return a `Opt[T]` from a bound procedure, making it easy to return error
conditions from procs used both in Nim and JS.  (However, returning a
JSValue is usually more efficient.)

### Using raw JSValues

When passing around raw JSValues, make sure you reference/unreference
appropriately using the `JS_DupValue` and `JS_FreeValue` functions from
QuickJS.  (When you only have access to a `JSRuntime`, use `JS_FreeValueRT`
and `JS_DupValueRT` instead.)

Note the presence of JSValueConst; this is a distinct subtype of JSValue
that indicates that the value will be free'd by the caller.

In contrast, procedures that take a non-const JSValue are expected to
take ownership of said JSValue and eventually free it.  This behavior is
similar to Nim's `sink` keyword.

To get raw JSValues in `.jsfunc` (or similar) bound functions, set the
desired parameter's type to `JSValueConst`.

Since JSValues need a JSContext to do anything useful, you'll want to set
the first parameter of such functions to a `JSContext` type; this passes
the current JSContext on to the bound function.  See
[above](#jsfunc-jsstfunc-functions) for details.

Warning: a footgun exists when calling `JSValue`s stored in an object.
E.g.,

```nim
type
  EventListener = ref object
    callback: JSValue

proc invoke(ctx: JSContext; listener: EventListener; event: Event): JSValue =
  # simplified for demonstration purposes
  let jsTarget = ctx.toJS(event.currentTarget)
  if JS_IsException(jsTarget):
    return jsTarget
  let jsEvent = ctx.toJS(event)
  if JS_IsException(jsEvent):
    JS_FreeValue(ctx, jsTarget)
    return jsEvent
  # horrible bug!
  let ret = ctx.call(listener.callback, jsTarget, jsEvent)
  JS_FreeValue(ctx, jsTarget)
  JS_FreeValue(ctx, jsEvent)
```

Here, the call is **incorrect**.  The reason is that QuickJS *borrows*
`listener.callback`, so if the callback removes `listener` (e.g., with
removeEventListener), then you're suddenly looking at memory corruption.

To avoid this, it is helpful to dup any owned function before calling it.
Correct example:

```nim
proc invoke(ctx: JSContext; listener: EventListener; event: Event): JSValue =
  # simplified for demonstration purposes
  let jsTarget = ctx.toJS(event.currentTarget)
  if JS_IsException(jsTarget):
    return jsTarget
  let jsEvent = ctx.toJS(event)
  if JS_IsException(jsEvent):
    JS_FreeValue(ctx, jsTarget)
    return jsEvent
  # correct variant
  let callback = JS_DupValue(ctx, listener)
  let ret = ctx.call(callback, jsTarget, jsEvent)
  JS_FreeValue(ctx, callback)
  JS_FreeValue(ctx, jsTarget)
  JS_FreeValue(ctx, jsEvent)
```

### Using toJS

```nim
proc toJS[T](ctx: JSContext; val: T): JSValue
```

The `jsClassDef` macro uses the overloaded `toJS` function to convert bound
function return values to JS values.  This can be called by user code too
by importing `monoucha/tojs`.

`JSValue`s you get from toJS are owned by you, so you should call
`JS_FreeValue` on these when you no longer need them.

The `tojs` module also includes some other convenience functions:

* `defineProperty`, `definePropertyC`, `definePropertyE`,
  `definePropertyCW`, `definePropertyCWE`: simple wrappers around
  `JS_DefineProperty*` functions from the QuickJS API.

  The `C`, `E`, `CW`, `CWE` represent the "configurable", "enumerable",
  and "writable" flags of the property.

  Warning: like in QuickJS, these functions *consume* a JSValue; that
  is, if you pass a JSValue, then the function will call `JS_FreeValue`
  on it.

* `newFunction`: creates a new JavaScript function.  `args` is a list of
  parameter names, `body` is the JavaScript function body.

### Using fromJS

```nim
proc fromJS[T](ctx: JSContext; val: JSValueConst; res: var T): FromJSResult
```

`fromJS` converts QJS `JSValue`s into Nim values.  The default converters
reside in `monoucha/fromjs`.

On success, `fromJS` fills `res` and returns `fjOk`.

On failure, `res` is set to an unspecified value, a QuickJS exception is
thrown (typically a `TypeError`), and `fjErr` is returned.

Passing `JS_EXCEPTION` to `fromJS` is invalid.

### Custom type converters

It is possible to add custom `fromJS` and `toJS` overloads for any type.

---

## Debugging

If you hope to figure out anything you'll want to use `make TARGET=debug`.
Besides showing a Nim stack trace, this will also dump leaked GC objects
when a buffer is closed or the browser ends.  (Note that buffer leak
information is swallowed if you simply press `q`.  Also, it doesn't work in
`make test`.  (TODO: it should.))

`make TARGET=asan` may help with memory errors too, although it is
significantly slower than `TARGET=debug`.

Some other useful flags are defined in QuickJS.  The simplest way to
enable these is to uncomment them in `lib/monoucha0/monoucha/qjs/quickjs.c`:

* FORCE_GC_AT_MALLOC: forces a GC before each JS object allocation.
  Useful to stress test init, but very slow.
* JS_MALLOC_LARGE_BLOCKS_ONLY: QuickJS has a custom malloc that is very
  fast, but also interacts poorly with valgrind and is generally more
  forgiving with UAFs.

---

## Implementation

The main difficulty here is creating a memory model that allows three types
of references: JS only, Nim only, and JS + Nim.

So the core idea we use is to have a single refcount in *all three cases*.
QuickJS and its cycle collector only sees a bound object as one object, so
no cycle collection must be done in the default case, and even with cycle
collection, pairing objects is trivial.

### ARC

Chawan uses the *ARC* Nim memory manager.  The ORC cycle collector is
not enabled, meaning `ref`s are reference counted, but cycles between
`ref`s have to be broken up manually.

For inherently cyclic graphs (pretty much every JS API), we instead
use the custom `JSRef` type.  This is implemented using Nim's [lifetime
hooks](https://nim-lang.org/docs/destructors.html), and a QuickJS patch to
support *foreign objects*.

### Foreign objects

A *foreign object* is a QuickJS GC object type.  Every Nim type exposed to JS
is allocated using the QuickJS GC, and wrapped in a `JSForeignObject`
header that includes

* The class id (`JSClassID`).
* A pointer to either the foreign object itself (a self-reference), or to a
  `JSObject`.

When converting the foreign object to a JSValue, it is checked if the
pointer is a `JSObject *`.  If yes, we simply dup and return that pointer.

Otherwise, we create a new `JSObject`, transfer the `JSForeignObject`'s
reference count to that, and finally remove the `JSForeignObject` from
the GC.

This means the opaque pointer always points to an active GC object whose
reference count represents the number of active JS *and* Nim references to
the object.  Once this reference count reaches zero, the class finalizer
is called using a `JSValue`:

* If there is a corresponding `JSObject` (i.e., the object was ever used
  in JS), the passed `JSValue` is of `JS_TAG_OBJECT`.  The foreign object
  is retrieved by calling `JS_GetOpaque`.
* Otherwise, the passed `JSValue` is of `JS_TAG_MODULE`.  The foreign
  object is the JSValue's pointer.  (Of course, this is a hack, but it
  keeps the QuickJS patch's diff down.)

The finalizer invokes a chain of functions which first run any operations
defined in `jsfin` and then call `=destroy` (or JS_FreeValueRT) on the
object's fields.  Note that if the `JSValue` is a `JS_TAG_OBJECT`, the
foreign object is no longer a GC object, and therefore the finalizer
wrapper disposes of it using `JS_FreeForeignObjectMemory`.

`gc_mark` works similarly, without the final disposal step.

### JSRef

As mentioned above, the `JSForeignObject`s are automatically refcounted in
Nim using `JSRef`.  While its use is mostly straightforward, there are some
caveats.

First, `JSRef` is implemented using `distinct`.  The benefit is that this
compiles to a C pointer, so the compiler gets as much type information as
it can, without having to generate a million structs for each and every
object.

The drawback is that `distinct` is a bit finnicky, here's how we work
around that...

#### Conversions

A generic `distinct` cannot borrow the `.` operator, so an alternative
solution is needed.  An easy way is to use the `experimental:dotOperators`
feature with the following template:

```nim
template `.`[T](r: JSRef[T]; field: untyped): untyped =
  convertToPtr(r).field
```

The problem here is `convertToPtr`.  There are two ways to convert a
variable `r` of `JSRef[T]` to `ptr T`.

1. `(ptr T)(r)`
2. `cast[ptr T](r)`

The catch is that both are glitched in their own exciting way.

First, when `(ptr T)(r)` *converts* the object to a `ptr T`, it also
removes any `=destroy` hooks to be called.  That doesn't sound so bad until
you consider:

```nim
proc firstChild(r: Node): Node =
  # simplified for demonstration purposes
  r.internalFirst

proc insert(a, b, c: Node) =
  # ...
  a.firstChild.parentNode = a
  # ...will be transformed into
  # (ptr T)(a.firstChild).parentNode = a
```

This is transformed into:

```nim
proc firstChild(r: Node): Node =
  cha_jsDup(r.internalFirst)

proc insert(a, b, c: Node)
  (ptr T)(a.firstChild).parentNode = a
```

i.e., firstChild is never unref'd, we get a leak.

`cast[ptr T](r)` behaves better, but it has the issue that Nim will not
consider it an access to `r` itself..  e.g.,

```nim
proc restart(builder: ChaDOMBuilder) =
  let document = newDocument(builder.document.url)
  let window = builder.document.window
  document.window = window
  window.document = document
  # ...
```

gets transformed into

```nim
proc restart(builder: ChaDOMBuilder) =
  let document = newDocument(cast[ptr DocumentObj](builder.document).url)
  var window = cha_jsDup(cast[ptr DocumentObj](builder.document).window)
  cast[ptr DocumentObj](document).window = move(window)
  cast[ptr DocumentObj](window).document = document
```

and since `window` got moved, the `document` assignment is now directed to
the zero page.  See [bug report](https://github.com/nim-lang/Nim/issues/26123).

Luckily, most of the damage can be backwards-compatibly undone by a macro:
if there was a call, the value could not have been derived from a local,
so cast.  For other expressions, we know that we aren't responsible for
decref, so convert.

This is, of course, a horrible hack, but as far as I can tell, it works
everywhere.

### Runtime initialization

The order required is:

1. Register the global object's class in the runtime.
2. Register the global object in the context.
3. Register everything else.

Since we treat QJS as a runtime, these steps must run even in buffers that
do not use JavaScript.  However, in those buffers the `JSContext` is set to
a dummy created with `JS_NewContextRaw`, which uses minimal resources.

#### The global object

...is a special case.  We aren't allowed to set the opaque for
`JS_GetGlobalValue(ctx)`, because QuickJS already uses it for storing
global variables.  So we do it in the following way:

* Allocate a new Window foreign object.
* Allocate a dummy `JSObject` with Window's class.  Set this as Window's
  foreign opaque and Window as the dummy object's opaque.
* Finally, define a property on the global object that holds the foreign
  object.  (The property name is a unique symbol, so this isn't accessible
  from JS.)
* When converting a `JSValue` to a `JSRef`, special case the global object:
  if the `JSValue` holds the global `JSObject`, then return `Window`
  (stored as `globalObj` in `JSContextOpaque`).
* When converting a `JSRef` to a `JSValue`, do the same, except now check
  for `globalObj` and return `JS_GetGlobalObject(ctx)`.

This will presumably work with frames too, once they are supported.
