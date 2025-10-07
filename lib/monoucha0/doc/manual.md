# Monoucha manual

**IMPORTANT**: currently, Monoucha only works correctly with refc, ergo you
*must* to put `--mm:refc` in your `nim.cfg`. ORC cannot deal with Monoucha's
GC-related hacks, and if you use ORC, you will run into memory errors on larger
projects.

I hope to fix this in the future. For now, please use refc.

## Table of Contents

* [Introduction](#introduction)
	- [Hello, world](#hello-world)
        - [Error handling](#error-handling)
* [Registering objects](#registering-objects)
	- [registerType: registering type interfaces](#registertype-registering-type-interfaces)
		* [Global objects](#global-objects)
		* [Inheritance](#inheritance)
		* [Misc registerType parameters](#misc-registertype-parameters)
	- [jsget, jsset: basic property reflectors](#jsget-jsset-basic-property-reflection)
* [Function pragmas](#function-pragmas)
	- [jsfunc: regular functions](#jsfunc-regular-functions)
	- [jsctor: constructors](#jsctor-constructors)
	- [jsfget, jsfset: custom property reflectors](#jsfget-jsfset-custom-property-reflectors)
	- [jsstfunc: static functions](#jsstfunc-static-functions)
	- [jsuffunc, jsufget, jsuffget: the LegacyUnforgeable property](#jsuffunc-jsufget-jsuffget-the-legacyunforgeable-property)
	- [jsgetownprop, jsgetprop, jssetprop, jsdelprop, jshasprop, jspropnames: magic functions](#jsgetownprop-jsgetprop-jssetprop-jsdelprop-jshasprop-jspropnames-magic-functions)
	- [jsfin: object finalizers](#jsfin-object-finalizers)
* [toJS, fromJS](#tojs-fromjs)
	- [Using raw JSValues](#using-raw-jsvalues)
	- [Using toJS](#using-tojs)
	- [Using fromJS](#using-fromjs)
	- [Custom type converters](#custom-type-converters)

## Introduction

Monoucha is a high-level wrapper to QuickJS, created for the
[Chawan](https://sr.ht/~bptato/chawan) browser with the primary aim of
automatically generating bindings to JS APIs.

While Monoucha *is* high-level, it does not try to completely abstract away
the low-level details.  You will in many cases have to use QuickJS APIs
directly to achieve something; Monoucha only provides abstractions to APIs
where doing something manually would be tedious and/or error-prone.

Also note that Monoucha is *not* complete, and neither is QuickJS-NG.
Documented interfaces may break at any new release.  Please pin a specific
version if you need a stable API.

### Hello, world

A simple example:

```nim
import monoucha/fromjs
import monoucha/javascript

let rt = newJSRuntime()
let ctx = rt.newJSContext()
const code = "'Hello from JS!'"
let val = ctx.eval(code)
var res: string
assert ctx.fromJS(val, res).isOk # no error
echo res # Hello from JS!
JS_FreeValue(ctx, val)
ctx.free()
rt.free()
```

eval() takes two parameters, one for code and one for the file name (used
for exception formatting).  Note that you have to free the context and
runtime handles manually.

The `res` variable then holds a QuickJS JSValue.  In this case, we convert
it to a string before freeing it.  You can skip conversion if you don't care
about the script's return value, but you *must* free the value.

### Error handling

Following code produces a ReferenceError:

```nim
const code = "abcd"
let val = ctx.eval(code)
```

If you try to convert this into a string, you will get an err() result.
This means you should print the exception message *somewhere*, but neither
QJS nor Monoucha really cares *where* you print it, or if you print it
at all.

A simple error handling code may look like:

```nim
if JS_IsException(res):
  stderr.writeLine(ctx.getExceptionMsg())
```

Usually you'll want to wrap `eval` in a function that deals with exceptions
in a way appropriate for your application.

## Registering objects

In JavaScript, all objects are passed *by reference*.  Monoucha allows you
to transparently use Nim object references in JS, provided you register
their type interface first.

### registerType: registering type interfaces

To register object types as a JavaScript interface, you must call the
`registerType` macro on the JS context with a type of your choice.

```nim
macro registerType*(ctx: JSContext; t: typed; parent: JSClassID = 0;
    asglobal: static bool = false; nointerface = false;
    name: static string = ""; hasExtraGetSet: static bool = false;
    extraGetSet: static openArray[TabGetSet] = []; namespace = JS_NULL;
    errid = opt(JSErrorEnum)): JSClassID
```

Typically, you would do this using Nim reference types.  Non-reference types
work too, but have some restrictions covered later.

Following code registers a JS interface for the Nim ref object `Moon`:

```nim
type Moon = ref object

jsDestructor(Moon)

# [...]
ctx.registerType(Moon)
const code = "Moon"
let val = ctx.eval(code)
var res: string
assert ctx.fromJS(val, res).isOk # no error
echo res # function Moon() [...]
JS_FreeValue(ctx, val)
```

i.e. just call `registerType`.

Pay attention to the jsDestructor template: you must call jsDestructor
immediately after your type declaration *before* any other functions.  (This
is necessary so that we can generate a `=destroy` hook for the object.)

#### Global objects

`registerType` also allows you to change the global object's type.  This
is quite important, as it is the only way to create global functions
(discounting object constructors).

To register a global type, set `asglobal = true` in `registerType`:

```nim
type Earth = ref object

# [...]
let earth = Earth()
ctx.registerType(Earth, asglobal = true)
ctx.setGlobal(earth)
const code = "assert(globalThis instanceof Earth)"
let val = ctx.eval(code)
assert not JS_IsException(val)
JS_FreeValue(ctx, val)
```

Notes:

* We call `setGlobal` with an instance of Earth.  This is needed to register
  some object as the backing Nim object; this same instance of Earth will be
  passed to bound functions.
* This time, we do not call jsDestructor, because the global object is
  special-cased; its reference is kept until the JS context gets freed.
  Therefore it does not need a `=destroy` hook.

#### Inheritance

`registerType` also allows you to specify inheritance chains by setting
the `parent` parameter:

```nim
type
  Planet = ref object of RootObj
  Earth = ref object of Planet
  Moon = ref object of Planet

# [...]
let planetCID = ctx.registerType(Planet)
ctx.registerType(Earth, parent = planetCID, asglobal = true)
ctx.registerType(Moon, parent = planetCID)
ctx.setGlobal(Earth()) # make sure to set a global so global functions work
const code = "assert(globalThis instanceof Planet)"
let val = ctx.eval(code)
assert not JS_IsException(val)
JS_FreeValue(ctx, val)
```

In this model, the inheritance tree looks like:

* Planet
	- Earth
	- Moon

There is no strict requirement to actually model the Nim inheritance chain.
e.g. if we set "Rock" as the parent of Planet, then we could use Rock as the
direct ancestor of Earth without even registering Planet at all.

However, this is a two-edged blade, as it also allows specifying invalid
models which result in undefined behavior.  For example, setting Earth as
the `parent` of Moon compiles, but is invalid, and will result in "Moon"
Nim objects being cast to Earth references.

#### Misc registerType parameters

Following parameters also exist:

* `nointerface`: suppress constructor creation
* `name`: set a different JS name than the Nim name
* `hasExtraGetSet`, `extraGetSet`: an array of magic getters/setters.
  `hasExtraGetSet` must be set to true in case you pass anything in
  `extraGetSet` because of a compiler bug.
* `namespace`: instead of defining the constructor on the global object,
  define it on the passed JS object. You must use QuickJS APIs to create
  this object. `namespace` is not consumed (i.e. you must free it
  yourself).

### jsget, jsset: basic property reflectors

The `jsget` and `jsset` pragmas can be set on fields of registered
object types to directly expose them to JS:

```nim
type
  Moon = ref object

  Earth = ref object
    moon {.jsget.}: Moon
    name {.jsgetset.}: string
    population {.jsset.}: int64

jsDestructor(Moon)

# [...]
let earth = Earth(moon: Moon(), population: 1, name: "Earth")
ctx.registerType(Earth, asglobal = true)
ctx.registerType(Moon)
ctx.setGlobal(earth)
const code = """
globalThis.population = 8e9;
"name: " + globalThis.name + ", moon: " + globalThis.moon;
"""
let val = ctx.eval(code)
var res: string
assert ctx.fromJS(val, res).isOk # no error
echo res # name: Earth, moon: [object Moon]
echo earth.population # 8e9
JS_FreeValue(ctx, val)
```

In the above example, we expose an Earth instance as the global object,
and modify/inspect it.  By default, object fields are not exposed to
JS; `{.jsget.}` gives JS read-only access, `{.jsset.}` write-only, and
`jsgetset` expands to `{.jsget, jsset.}` (both read and write).

## Function pragmas

The main feature of Monoucha is that it can automatically wrap functions
and expose them to JavaScript by associating them with types exposed
through [registerType](#registertype-registering-type-interfaces).
All you have to do is to stick pragmas to function definitions.

Here we enumerate over all currently available pragmas.

### jsfunc: regular functions

The simplest pragma is `.jsfunc`.  This marks the function as a member
of the JS interface associated with the first parameter's type.

Example:

```nim
type
  Window = ref object
    console {.jsget.}: Console

  Console = ref object

jsDestructor(Console)

proc log(console: Console; s: string) {.jsfunc.} =
  echo s

# [...]
let window = Window(console: Console())
ctx.registerType(Window, asglobal = true)
ctx.registerType(Console)
ctx.setGlobal(window)
const code = "console.log('Hello, world!')"
JS_FreeValue(ctx, ctx.eval(code))
```

As you can see, `log` has been exposed as a member of the JS interface
`Console`.

It is possible to use a different name for the JS function than for the
Nim procedure. e.g. the following will also expose a `log` function:

```nim
proc jsLog(console: Console; s: string) {.jsfunc: "log".} = # [...]
```

In general, you can use any combination of parameters in `.jsfunc` procs.
These are converted on a best-effort basis: e.g. in the above example,
`console.log(1)` would pass the string "1", not an exception.  Monoucha
tries to adhere to the WebIDL standard in this regard - the main exception
is that `float64` is mapped to `unrestricted double`, not just `double`.

The first parameter must be a reference type that has been registered using
`registerType`.

```nim
type Console2 = object # not ref!

proc log(console: var Console2; s: string) {.jsfunc.} = # [...]
```

It is also possible to insert a "zeroeth" parameter to get a reference to
the current JS context.  This is useful if you want to access state global
to the JS context without storing a backreference to the global object:

```nim
proc log(ctx: JSContext; console: Console; s: string) {.jsfunc.} =
  # This assumes you have already setGlobal a Window instance.
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  assert ctx.fromJS(global, window).isOk # no error
  JS_FreeValue(ctx, global)
  # Now you can do something with the window, e.g.
  window.outFile.writeLine(s)
```

It is also possible to use `varargs` in `.jsfunc` functions:

```nim
proc log(ctx: JSContext; console: Console; ss: varargs[JSValueConst])
    {.jsfunc.} =
  discard # can be called like `console.log("a", "b", "c", "d")`
```

Only `JSValueConst` varargs are supported.

For further information about individual type conversions, see the
[toJS, fromJS](#tojs-fromjs) section.

### jsctor: constructors

The `.jsctor` pragma is used to define a constructor for a specific
type:

```nim
type JSFile = ref object
  path {.jsget.}: string

jsDestructor(JSFile)

proc newJSFile(path: string): JSFile {.jsctor.} =
  return JSFile(path: path)

# [...]
# Use different name in JS through `name': File in JS is mapped to JSFile
# in Nim.
ctx.registerType(JSFile, name = "File")
const code = "console.log(new File('/path/to/file'))"
JS_FreeValue(ctx, ctx.eval(code)) # [object File]
```

`.jsctor`, like other pragmas, supports the same "zeroeth" JSContext
parameter as [jsfunc](#jsfunc-regular-functions), which is useful when the
global object is needed for resource allocation.

### jsfget, jsfset: custom property reflectors

The `.jsfget` and `.jsfset` pragmas can be used to define custom
getter/setter functions.

Like `.jsget` and `.jsset`, they appear as regular getters and setters
in JS.  However, instead of automatically reflecting a property, `.jsfget`
and `.jsfset` allows you to write custom code to handle property accesses.

Example:

```nim
# [...] (see above for constructor)

func name(file: JSFile): string {.jsfget.} =
  return file.path.substr(file.path.rfind('/') + 1)

proc setName(file: JSFile; s: string) {.jsfset: "name".} =
  let i = file.path.rfind('/')
  file.path = file.path.substr(0, i) & s

# [...]
const code = """
const file = new JSFile("/path/to/file");
console.log(file.path); /* /path/to/file */
console.log(file.name); /* file */
file.name = "new-name";
console.log(file.path); /* /path/to/new-name */
"""
JS_FreeValue(ctx, ctx.eval(code))
```

### jsstfunc: static functions

`.jsstfunc` defines a static function on a given interface.  Unlike with
`.jsfunc`, you must provide at least a single parameter for these functions,
with the syntax `Interface.functionName`.

Note that `Interface` must be an interface registered through
`registerType`.  If the interface was renamed, the Nim name (*not* the JS
name) must be used.

Example:

```nim
# [...] (see above for constructor)

proc jsExists(path: string): bool {.jsstfunc: "JSFile.exists".} =
  return fileExists(path)

# [...]
const code = """
console.log(File.exists("doc/manual.md")); /* true */
"""
JS_FreeValue(ctx, ctx.eval(code))
```

### jsuffunc, jsufget, jsuffget: the LegacyUnforgeable property

The pragmas `.jsuffunc`, `.jsufget` and `.jsuffget` correspond to the WebIDL
[`[LegacyUnforgeable]`](https://webidl.spec.whatwg.org/#LegacyUnforgeable)
property.

Concretely, this means that the function (or getter) is defined on
instances of the interface, not on the interface (i.e. object prototype)
as a non-configurable property.  Even more concretely, this means that the
function (or getter) cannot be changed by JavaScript code.

```nim
# this will always return the result of the fstat call.
proc owner(file: JSFile): int {.jsuffget.} =
  let fd = open(cstring(file.path), O_RDONLY, 0)
  if fd == -1: return -1
  var stats = Stat.default
  if fstat(fd, stats) == -1:
    discard close(fd)
    return -1
  return int(stats.st_uid)

proc getOwner(file: JSFile): int {.jsuffget.} =
  return file.owner

# [...]

const code = """
const file = new File("doc/manual.md");
const oldGetOwner = file.getOwner;
file.getOwner = () => -2; /* doesn't work */
assert(oldGetOwner == file.getOwner);
Object.defineProperty(file, "owner", { value: -2 }); /* throws */
"""
JS_FreeValue(ctx, ctx.eval(code))
```

### jsgetownprop, jsgetprop, jssetprop, jsdelprop, jshasprop, jspropnames: magic functions

`.jsgetownprop`, `.jsgetprop`, `.jssetprop`, `.jsdelprop`, `.jshasprop` and
`.jspropnames` generate bindings for magic functions.  These are mainly
useful for collections, where you want to provide custom behavior for
property accesses.

(TODO elaborate...)

### jsfin: object finalizers

The `.jsfin` pragma can be used to clean up resources used by objects at
the end of their lifetime.

In principle, this is just like the Nim `=destroy` property, except
it also tracks the lifetime of possible JS objects which the Nim object
may back.  (In other words, it's a cross-GC finalizer.)

The first parameter must be a reference to the object in question.
Only one `.jsfin` procedure per reference type is allowed, but parent
`.jsfin` finalizers are inherited.  (This used to work differently in
previous versions.)

`.jsfin` also supports a "zeroeth" parameter, but here it must be a
`JSRuntime`, *not* `JSContext`.  WARNING: this parameter is nil when an
object that was not bound to a JS value is finalized.  (An object is bound
to a JS value if toJS is called on it; this happens whenever you return a
Nim object from a function bound to JS.)

WARNING 2: like Nim `=destroy`, this pragma is very easy to misuse.
In particular, make sure to **NEVER ALLOCATE** in a `.jsfin` finalizer,
because this [breaks](https://github.com/nim-lang/Nim/issues/4851) Nim refc.
(I don't know if this problem is still present in ORC, but at the moment
Monoucha does not work with ORC anyway.)

Example:

```nim
type JSFile = ref object
  path: string
  buffer: pointer # some internal buffer handled as managed memory
jsDestructor(JSFile)

proc newJSFile(path: string): JSFile {.jsctor.} =
  return JSFile(
    path: path,
    buffer: alloc(4096)
  )

var unrefd {.global.} = 0
proc finalize(file: JSFile) {.jsfin.} =
  if file.buffer != nil:
    dealloc(file.buffer)
    # Note: it is not necessary to nil out the pointer; it's just me being
    # paranoid :P
    file.buffer = nil
    inc unrefd

# [...]

const code = """
{
	/* following call is in a separate code, so QJS can unref it
	 * immediately. */
	const file = new File("doc/manual.md");
}
/* in contrast, following file will not be deallocated until the runtime is
 * gone. */
const file = new File("doc/manual.md");
"""
JS_FreeValue(ctx, ctx.eval(code))
GC_fullCollect() # ensure refc runs
assert unrefd == 1 # first file is already deallocated
ctx.free()
GC_fullCollect() # ensure refc runs
assert unrefd == 1 # the second file is still available
rt.free()
assert unrefd == 2 # runtime is freed, so the second file gets deallocated too
```

## toJS, fromJS

This section covers the handling and conversion of JSValue types.  While in
many cases it is possible to avoid using JSValues, Monoucha does not go out
of its way to completely eliminate them.

In particular, handling JSValues is unavoidable when:

* You want to do something with `eval()`'s result.
* You need to call a QuickJS API not wrapped by Monoucha. (e.g. JS
  function calls)
* You want a dynamically typed variable, e.g. for "union" types.

### Option vs Opt

In converters, the conventional way to represent null values is to use
`Option[T]`.  This applies to e.g. strings (which are not nilable in Nim),
but also to refs in fromJS so that a registered ref object parameter of a
`.jsfunc` is not nullable unless you wrap it in an `Option`.

`Opt[T]` in contrast is used for representing errors.  Typically, it is
returned from fromJS as `Opt[void]`; you can use the nim-results functions
to handle these.  It is also possible to return a `Result[T, JSError]` from
a bound procedure, making it easy to return error conditions from procs used
both in Nim and JS.  (Notably however, returning a JSValue is still a more
effective alternative.)

Monoucha does not use Nim exceptions.

### Using raw JSValues

When passing around raw JSValues, it is important to make sure you
reference/unreference appropriately. For this, use the `JS_DupValue` and
`JS_FreeValue` functions from QuickJS. (When you only have access to a
`JSRuntime`, use the `JS_FreeValueRT` and `JS_DupValueRT` variants
instead.)

Note the presence of JSValueConst; this is a distinct subtype of JSValue
that indicates that the value is borrowed. It is analogous to the `lent`
keyword in Nim (which is implicit in procedure parameters).

In contrast, procedures that take a non-const JSValue are expected to
take ownership of said JSValue and eventually free it. This behavior is
anologous to the `sink` keyword in Nim.

To get raw JSValues in `.jsfunc` (or similar) bound functions, you can
simply set the desired parameter's type to `JSValueConst`. This way, you
get a "borrowed" JSValue; to keep a reference to these after the function
exits, reference them with `JS_DupValue` first. (Analogously, you do not
have to free such JSValues as long as you don't call `JS_DupValue` on
them, either.)

Since JSValues need a JSContext to do anything useful, you may want to
set the first parameter of such functions to a `JSContext` type; this
passes the current JSContext on to the bound function. (For details, see
[above](#jsfunc-regular-functions).)

### Using toJS

```nim
proc toJS[T](ctx: JSContext; val: T): JSValue
```

Monoucha internally uses the overloaded `toJS` function to convert bound
function return values to JS values. This is available to user code too;
simply import the `monoucha/tojs` module.

Naturally, `JSValue`s you get from toJS are owned by you, so you should
call `JS_FreeValue` on these when you no longer need them.

The `tojs` module also includes some other convenience functions:

* `defineProperty`, `definePropertyC`, `definePropertyE`,
  `definePropertyCW`, `definePropertyCWE`: simple wrappers around
  `JS_DefineProperty*` functions from the QuickJS API. Unlike the
  QuickJS versions, they panic on errors, so only use these if you are
  100% sure that they always succeed.<br>
  The `C`, `E`, `CW`, `CWE` represent the "configurable", "enumerable",
  and "writable" flags of the property.<br>
  Warning: like in QuickJS, these functions *consume* a JSValue; that
  is, if you pass a JSValue, then the function will call `JS_FreeValue`
  on it.
* `newFunction`: creates a new JavaScript function. `args` is a list of
  parameter names, `body` is the JavaScript function body.

### Using fromJS

```nim
proc fromJS[T](ctx: JSContext; val: JSValueConst; res: var T): Err[void]
```

`fromJS` converts QJS `JSValue`s into Nim values.  To use it, import
`monoucha/fromjs`.

On success, `fromJS` fills `res` and returns `Opt[void].some()`.

On failure, `res` is set to an unspecified value, a QuickJS exception is
thrown (using `JS_Throw()`), and `Opt[void].none()` is returned.

**Warning**: JSDict in general is somewhat finnicky: you must make
sure that their destructors run before deinitializing the runtime.
In practice, this means a) you must not use JSDict in the same procedure
where you free the JSRuntime, b) you must call GC_fullCollect before
freeing the runtime if you use JSDict.  (TODO: this all seems very
broken.  Why isn't JSDict itself just a ref object?)

Passing `JS_EXCEPTION` to `fromJS` is valid, and results in no new exception
being thrown.

### Custom type converters

In Monoucha, object reference types are automatically converted to JS
reference types.  However, value types are different: trying to pass any
other type to/from JS errors out at compilation time.

To work around this limitation, you can override `toJS` and `fromJS` for
such types.  In both cases, it is enough to add an overload for the
respective function and expose it to the module where the converter is
needed (i.e. where you call `registerType`).

### Implementation details

As mentioned before, ref types registered with the registerType macro can
be freely passed to JS, and the function-defining macros set functions on
their JS prototypes.  When a ref type is passed to JS, a shim JS object is
associated with the Nim object, and will remain in memory until neither Nim
nor JS has references to it.

There is a complication in this system: QuickJS has a reference-counting GC,
and so does Nim.  Associating two objects managed by two separate GCs is
problematic: even if you can freely manage the references on both objects,
you now have a cycle that only a cycle collector can break up.  A cross-GC
cycle collector is out of question; then it would be easier to just replace
the entire GC in one of the runtimes.  (That is probably how a future
ARC-based version will work.)

So instead, we patch a hook into the QuickJS cycle collector.  Every time
a JS companion object of a Nim object would be freed, we first check if the
Nim object still has references from Nim, and if yes, prevent the JS object
from being freed by "moving" a reference to the JS object (i.e. unref Nim,
ref JS).

Then, if we want to pass the object to JS again, we add no references to the
JS object, only to the Nim object.  By this, we "moved" the reference back
to JS.

This way, the Nim cycle collector can destroy the object without problems
if no more references to it exist.  Once you set some properties on the JS
companion object, it will remain even if no more references exist to it in
JS for some time, only in Nim.  So this works:

```js
document.querySelector("html").canary = "chirp";
console.log(document.querySelector("html").canary); /* chirp */
```
