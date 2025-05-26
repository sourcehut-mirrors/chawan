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
	- [Non-reference objects](#non-reference-objects)
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

Monoucha is a high-level wrapper to QuickJS. It was created for the
[Chawan](https://sr.ht/~bptato/chawan) browser to avoid manually writing
bindings to JS APIs.

While Monoucha *is* high-level, it does not try to completely abstract
away the low-level details. You will in many cases have to use QuickJS
APIs directly to achieve something; Monoucha only provides abstractions
to APIs where doing something manually would be tedious and/or
error-prone.

Also note that Monoucha is *not* complete, and neither is QuickJS-NG.
While a major API break for documented interfaces is unlikely, it may
happen at any time in the future.  Please pin a specific version if you
need a stable API.

### Hello, world

Let's start with a simplified version of the example from the README:

```nim
import monoucha/fromjs
import monoucha/javascript

let rt = newJSRuntime()
let ctx = rt.newJSContext()
const code = "'Hello from JS!'"
let val = ctx.eval(code)
var res: string
assert ctx.fromJS(val, res).isSome # no error
echo res # Hello from JS!
JS_FreeValue(ctx, val)
ctx.free()
rt.free()
```

This is the minimal required code to run a script.  You may notice a few
things:

* eval() takes two parameters, one for code and one for the file name.
  The file name will be used for exception formatting.
* You have to free the context and runtime handles manually.  This is
  unfortunately unavoidable; the good news is that you won't have to do
  much manual memory management after this.

The `res` variable then holds a QuickJS JSValue. In this case, we
convert it to a string before freeing it. You can skip conversion if you
don't care about the script's return value, but you must *always* free
it.

You may be thinking to yourself, "why is there no convenience wrapper
around this?"  The reason is illustrated in the next section.

### Error handling

Let's get ourselves a ReferenceError:

```nim
const code = "abcd"
let val = ctx.eval(code)
```

If you try to convert this into a string, you will get an err() result.
Obviously, you want to print your errors *somewhere*, but Monoucha does
not care how and where you log error messages, and leaves this task to
the user.

However, there is an easy way to retrieve the current error message:

```nim
if JS_IsException(res):
  stderr.writeLine(ctx.getExceptionMsg())
```

In most cases, you should wrap `eval` in a function that deals with
exceptions in the most appropriate way for your application.

Alternatively, a self-contained evalConvert can be written as follows:

```nim
import results
import monoucha/tojs

proc evalConvert[T](ctx: JSContext; code: string;
    file = "<input>"): Result[T, string] =
  let val = ctx.eval(code, file, flags)
  var res: T
  if ctx.fromJS(val, res).isNone:
    # Exception when converting the value.
    JS_FreeValue(ctx, val)
    return err(ctx.getExceptionMsg())
  JS_FreeValue(ctx, val)
  # All ok! Return the converted object.
  return ok(res)
```

This is less efficient than immediately logging the exception message.

## Registering objects

So far we have talked about running JS code and getting its result,
which is not enough for most use cases. If you are embedding QuickJS,
you probably want some sort of interoperability between JS and Nim code.

In JavaScript, all objects are passed *by reference*. Monoucha allows
you to transparently use Nim object references in JS, provided you
register their type interface first.

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

Typically, you would do this using Nim reference types. Non-reference
types work too, but have some restrictions which will be covered.

Now for the first example. Following code registers a JS interface for
the Nim ref object `Moon`:

```nim
type Moon = ref object

jsDestructor(Moon)

# [...]
ctx.registerType(Moon)
const code = "Moon"
let val = ctx.eval(code)
var res: string
assert ctx.fromJS(val, res).isSome # no error
echo res # function Moon() [...]
JS_FreeValue(ctx, val)
```

Quite straightforward: just call `registerType`.

Pay attention to the jsDestructor template: you call jsDestructor
immediately after your type declaration *before* any other functions, or
Monoucha will complain.  (This is necessary so that we can generate a
`=destroy` hook for the object.)

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

You may notice two things:

* We call `setGlobal` with an instance of Earth.  This is needed to
  register some object as the backing Nim object; this same instance of
  Earth will be passed to bound functions.
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

There is no strict requirement to actually model the Nim inheritance
chain.  e.g. if we set "Rock" as the parent of Planet, then we could use
Rock as the direct ancestor of Earth without even registering Planet at
all.

However, this is a two-edged blade, as it also allows specifying invalid
models which may result in undefined behavior. For example, setting
Earth as the `parent` of Moon compiles, but is invalid, as it will
result in "Moon" Nim objects being casted to Earth references.

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

Time to actually expose some Nim values to JS.

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
assert ctx.fromJS(val, res).isSome # no error
echo res # name: Earth, moon: [object Moon]
echo earth.population # 8e9
JS_FreeValue(ctx, val)
```

In the above example, we expose an Earth instance as the global object,
and modify/inspect it.  By default, object fields are not exposed to JS;
`{.jsget.}` gives JS read-only access, `{.jsset.}` write-only, and
`jsgetset` expands to `{.jsget, jsset.}` (both read and write).

### Non-reference objects

JavaScript objects have reference semantics, so this does not make much
sense at first glance.  However, children of heap-allocated objects do
in fact have a permanent address, which we can convert to JS so long as
we hold a reference to their parent.

e.g. this works:

```nim
type
  Moon = object

  Earth = ref object
    moon {.jsget.}: Moon

jsDestructor(Moon)

# [...]
let earth = Earth(moon: Moon())
ctx.registerType(Earth, asglobal = true)
ctx.registerType(Moon)
ctx.setGlobal(earth)
const code = "globalThis.moon"
let val = ctx.eval(code)
var res: string
assert ctx.fromJS(val, res).isSome # no error
echo res # [object Moon]
JS_FreeValue(ctx, val)
```

This still has some restrictions: for example, you cannot return a
non-reference object from a [wrapped](#function-pragmas) function.

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

In general, you can use any combination of parameters in `.jsfunc`
procs.  These are converted on a best-effort basis: e.g. in the above
example, `console.log(1)` would pass the string "1", not an exception.
Monoucha tries to adhere to the WebIDL standard in this regard. (TODO:
find & document places where this is not true yet.)

The first parameter *must* be a reference type that has been registered
using `registerType`. Alternatively, you can also use a registered
non-reference object type, but in this case, you *must* annotate it with
`var`:

```nim
type Console2 = object # not ref!

proc log(console: var Console2; s: string) {.jsfunc.} = # [...]
```

It is also possible to insert a "zeroeth" parameter to get a reference
to the current JS context. This is useful if you want to access state
global to the JS context without storing a backreference to the global
object:

```nim
proc log(ctx: JSContext; console: Console; s: string) {.jsfunc.} =
  # This assumes you have already setGlobal a Window instance.
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  assert ctx.fromJS(global, window).isSome # no error
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

For efficiency reasons, only `JSValueConst` varargs are supported.

(In the past, union types and non-JSValueConst varargs also worked. This
feature was dropped because it generated inefficient and bloated code;
`fromJS` with `JSValueConst` parameters can be used to the same effect.)

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
parameter trick as [jsfunc](#jsfunc-regular-functions), which is useful
when the global object is needed for resource allocation.

### jsfget, jsfset: custom property reflectors

The `.jsfget` and `.jsfset` pragmas can be used to define custom
getter/setter functions.

Like `.jsget` and `.jsset`, they appear as regular getters and setters
in JS. However, instead of automatically reflecting a property,
`.jsfget` and `.jsfset` allows you to write custom code to handle
property accesses.

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

`.jsstfunc` defines a static function on a given interface. Unlike with
`.jsfunc`, you must provide at least a single parameter for these
functions, with the syntax `Interface.functionName`.

Note that `Interface` must be an interface registered through
`registerType`. If the interface was renamed, the Nim name (*not* the
JS name) must be used.

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

The pragmas `.jsuffunc`, `.jsufget` and `.jsuffget` correspond to the
WebIDL
[`[LegacyUnforgeable]`](https://webidl.spec.whatwg.org/#LegacyUnforgeable)
property.

Concretely, this means that the function (or getter) is defined on
*instances* of the interface, not on the interface (i.e. object
prototype) as a non-configurable property.  Even more concretely, this
means that the function (or getter) cannot be changed by JavaScript
code.

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

`.jsgetownprop`, `.jsgetprop`, `.jssetprop`, `.jsdelprop`, `.jshasprop`
and `.jspropnames` generate bindings for magic functions. These are
mainly useful for collections, where you want to provide custom behavior
for property accesses.

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
`JSRuntime`, *not* `JSContext`.  WARNING: this parameter is nil when
-an object that was not bound to a JS value is finalized.  (e.g.
calling toJS on the object, or returning the object from a `.jsfunc`
converts it to a JSValue too.)

WARNING 2: like Nim `=destroy`, this pragma is very easy to misuse.  In
particular, make sure to **NEVER ALLOCATE** in a `.jsfin` finalizer,
because this [breaks](https://github.com/nim-lang/Nim/issues/4851) Nim
refc.  (I don't know if this problem is still present in ORC, but at the
moment Monoucha does not work with ORC anyway.)

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

This section covers the handling and conversion of JSValue types.

While in most cases it is possible to avoid using JSValues, Monoucha
does not go out of its way to completely eliminate them.

In particular, handling JSValues is unavoidable when:

* You want to do something with `eval()`'s result.
* You need to call a QuickJS API not wrapped by Monoucha. (e.g. JS
  function calls)
* You want a dynamically typed variable, e.g. for "union" types.

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

`fromJS` is the opposite of `toJS`: it converts `JSValue`s into Nim
values. Import the `monoucha/fromjs` module to use it.

On success, `fromJS` fills `res` and returns `Opt[void].some()`.

On failure, `res` is set to an unspecified value, a QuickJS exception is
thrown (using `JS_Throw()`), and `Opt[void].none()` is returned.

**Warning**: JSDict in general is somewhat finnicky: you must make
sure that their destructors run before deinitializing the runtime.
In practice, this means a) you must not use JSDict in the same procedure
where you free the JSRuntime, b) you must call GC_fullCollect before
freeing the runtime if you use JSDict.  (TODO: this all seems very
broken.  Why isn't JSDict itself just a ref object?)

Passing `JS_EXCEPTION` to `fromJS` is valid, and results in no new
exception being thrown.

### Custom type converters

In Monoucha, object reference types are automatically converted to JS
reference types. However, value types are different:

* A non-reference `object` is converted to a JS reference by implicitly
  turning it into `ptr object`, as noted [above](#non-reference-objects).
* Trying to pass any other type to/from JS errors out at compilation.

To work around this limitation, you can override `toJS` and `fromJS` for
specific types. In both cases, it is enough to add an overload for the
respective function and expose it to the module where the converter is
needed (i.e. where you call `registerType`).
