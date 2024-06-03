# Monoucha manual

**IMPORTANT**: currently, Monoucha only works correctly with refc, ergo you
*must* to put `--mm:refc` in your `nim.cfg`. ORC cannot deal with Monoucha's
GC-related hacks, and if you use ORC, you will run into memory errors on larger
projects.

I hope to fix this in the future. For now, please use refc.

**UNDER CONSTRUCTION**: this document is an incomplete draft. Partially untested
code and possible inaccuracies ahead.

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
	- [jsgetprop, jssetprop, jsdelprop, jshasprop, jspropnames: magic functions](#jsgetprop-jssetprop-jsdelprop-jshasprop-jspropnames-magic-functions)
        - [jsfin: object finalizers](#jsfin-object-finalizers)
* [toJS, fromJS](#tojs-fromjs)
	- [Using raw JSValues](#using-raw-jsvalues)
	- [Using toJS](#using-tojs)
	- [Using fromJS](#using-fromjs)
	- [Custom type converters](#custom-type-converters)

## Introduction

Monoucha is a high-level wrapper to QuickJS. It was created for the
[Chawan](https://sr.ht/~bptato/chawan) browser to avoid having to manually write
bindings to JS APIs.

First, a disclaimer: while Monoucha *is* high-level, it does not try to
completely abstract away the low-level details. You will in many cases have to
use QuickJS APIs directly to achieve something; Monoucha only provides
abstractions to APIs where doing something manually would be tedious and/or
error-prone.

Also note that Monoucha is *not* complete. APIs may change, disappear, or appear
at any time in the future. Please pin a specific version if you need a stable
API.

### Hello, world

Let's start with a simplified version of the example from the README:

```nim
import monoucha/fromjs
import monoucha/javascript

let rt = newJSRuntime()
let ctx = rt.newJSContext()
const code = "'Hello from JS!'"
let res = ctx.eval(code, "<test>")
echo fromJS[string](ctx, res).get # Hello from JS!
JS_FreeValue(ctx, res)
ctx.free()
rt.free()
```

This is the minimal required code to run a script. You may notice a few things:

* eval() takes two parameters, one for code and one for the file name. The file
  name will be used for exception handling.
* You have to free the context and runtime handles manually. This is
  unfortunately unavoidable; the good news is that you won't have to do much
  manual memory management after this.

The `res` variable then holds a QuickJS JSValue. In this case, we convert it
to a string before freeing it; you can skip conversion if you don't care about
the script's return value, but you must *always* free it.

You may be thinking to yourself, "come on, why is there no convenience wrapper
around this?" Well, it is because one thing we haven't talked about yet:

### Error handling

Let's get ourselves a ReferenceError:

```nim
const code = "abcd"
let res = ctx.eval(code, "<test>")
```

If you try to convert this into a string, you will get an err(nil) result.
Obviously you want to print your errors *somewhere*, but since Monoucha does not
know (or care) where you log error messages, it leaves this task to you.

What we *do* provide is an easy way to retrieve the current error message:

```nim
if JS_IsException(res):
  stderr.writeLine(ctx.getExceptionMsg())
```

In most cases, you should wrap `eval` in a function that deals with exceptions
in the appropriate way for your application.

Alternatively, a self-contained evalConvert can be written as follows:

```nim
import monoucha/tojs

proc evalConvert[T](ctx: JSContext; code, file: string): Result[T, string] =
  let res = ctx.eval(code, file, flags)
  if JS_IsException(res):
    # Exception in eval; return the message.
    return err(ctx.getExceptionMsg())
  let val = fromJS[T]ctx, (res)
  JS_FreeValue(ctx, res)
  if val.isNone:
    # Conversion failed; convert the error value into an exception and then
    # return its message.
    #
    # Important: toJS here does not only convert the error (a JSError object),
    # but also *throws it*
    JS_FreeValue(ctx, toJS(ctx, val.error))
    return err(ctx.getExceptionMsg())
  # All ok! Return the converted object.
  return ok(val.get)
```

However, it is usually more efficient (and simpler) to immediately log
exceptions than to pass them around as a Result.

## Registering objects

So far we have talked about running JS code and getting its result, which is
nice, but not enough for most use cases. If you are embedding QuickJS, you
probably want some sort of interoperability between JS and Nim code.

JS is an object-oriented language, where objects are passed *by reference*.
Monoucha allows you to transparently use Nim object references in JS, provided
you register their interface first.

### registerType: registering type interfaces

To register object types as a JavaScript interface, you must call the
`registerType` macro on the JS context with a type of your choice.

```nim
macro registerType*(ctx: JSContext; t: typed; parent: JSClassID = 0;
    asglobal: static bool = false; nointerface = false;
    name: static string = ""; has_extra_getset: static bool = false;
    extra_getset: static openArray[TabGetSet] = []; namespace = JS_NULL;
    errid = opt(JSErrorEnum); ishtmldda = false): JSClassID
```

Typically, you would do this using Nim reference types; non-reference types have
some restrictions, which we will cover later.

Now for the first example. Following code registers a JS interface for the Nim
object `Moon`:

```nim
type Moon = ref object

jsDestructor(Moon)

# [...]
ctx.registerType(Moon)
const code = "Moon"
let res = ctx.eval(code, "<test>")
echo fromJS[string](ctx, res).get # function Moon() [...]
JS_FreeValue(ctx, res)
```

Quite straightforward; just call `registerType`.

One thing to pay attention to is the jsDestructor template: you must place a
jsDestructor call directly after your type declaration *before* any other
functions, or Monoucha will complain. (This is necessary so that we can generate
a `=destroy` hook for the object.)

#### Global objects

`registerType` also allows you to change the global object's type; this is quite
important, as it is the only way to create global functions (discounting the
constructors of object interfaces).

To register a global type, you must set `asglobal = true` in `registerType`:

```nim
type Earth = ref object

# [...]
let earth = Earth()
ctx.registerType(Earth, asglobal = true)
ctx.setGlobal(earth)
const code = "globalThis instanceof Earth"
let res = ctx.eval(code, "<test>")
echo fromJS[bool](ctx, res).get # true
JS_FreeValue(ctx, res)
```

You may notice two things:

* We call `setGlobal` with an instance of Earth. This is needed to register some
  object as the backing Nim object; this same instance of Earth will be passed
  to bound functions.
* This time, we do not call jsDestructor. This is because the global object is
  special-cased; its reference is kept until the JS context gets
  freed. Therefore it does not need a `=destroy` hook.

#### Inheritance

`registerType` also allows you to specify inheritance chains by setting the
`parent` parameter:

```nim
type
  Planet = ref object of RootObj
  Earth = ref object of Planet
  Moon = ref object of Planet

# [...]
let planetCID = ctx.registerType(Planet)
ctx.registerType(Earth, parent = planetCID, asglobal = true)
ctx.registerType(Moon, parent = planetCID)
const code = "globalThis instanceof Planet"
let res = ctx.eval(code, "<test>")
echo fromJS[bool](ctx, res).get # true
JS_FreeValue(ctx, res)
```

In this model, the inheritance tree looks like:

* Planet
	- Earth
	- Moon

Note that there is no strict requirement to actually model the Nim inheritance
chain; e.g. if we set "Rock" as the parent of Planet, then we could use Rock as
the direct ancestor of Earth without even registering Planet at all.

However, this is a two-edged blade, as it also allows specifying invalid models
which may result in undefined behavior. For example, setting Earth as the parent
of Moon is invalid, as it will result in "Moon" Nim objects being casted to
Earth references.

#### Misc registerType parameters

Following parameters also exist:

* `nointerface`: suppress constructor creation
* `name`: set a different JS name than the Nim name
* `has_extra_getset`, `extra_getset`: add an array of magic getters/setters.
  Note that `has_extra_getset` must be set to true in case you pass anything in
  `extra_getset` because of a compiler bug. (TODO elaborate here)
* `namespace`: instead of defining the constructor on the global object, define
  it on the passed JS object. Note that you must use QuickJS APIs to create
  this object, and that the object is not consumed (i.e. is not freed).
* `errid`: set the error ID. TODO this is currently pretty useless as a public
  API because JSErrorEnum is not extendable
* `ishtmldda`: creates a "falsy" object, like document.all. Note that currently
  only one of these is allowed per context.


### jsget, jsset: basic property reflectors

Time to actually expose some Nim values to JS.

The `jsget` and `jsset` pragmas can be set on fields of registered object
types to directly expose them to JS:

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
let res = ctx.eval(code, "<test>")
echo fromJS[string](ctx, res).get # name: Earth, moon: [object Moon]
echo earth.population # 8e9
JS_FreeValue(ctx, res)
```

In the above example, we expose an Earth instance as the global object, and
modify/inspect it. By default, object fields are not exposed to JS; `{.jsget.}`
gives JS read-only access, `{.jsset.}` write-only, and `jsgetset` expands to
`{.jsget, jsset.}`.

### Non-reference objects

JavaScript only has reference semantics for objects, so this does not make
much sense at first sight. However, children of heap-allocated objects do in
fact have a permanent address, which we can convert to JS so long as we hold a
reference to their parent.

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
let res = ctx.eval(code, "<test>")
echo fromJS[string](ctx, res).get # [object Moon]
JS_FreeValue(ctx, res)
```

Do note that this has some restrictions: for example, you cannot return a
non-reference object from a [wrapped](#function-pragmas) function.

## Function pragmas

Arguably the most important feature of Monoucha is that it lets you
automatically wrap functions and expose them to JavaScript by associating them
with types exposed through [registerType](#registerType-registering-type-interfaces).

This is done by sticking pragmas to function definitions; here we enumerate over
all currently available pragmas.

### jsfunc: regular functions

The simplest pragma is `.jsfunc`: this marks the function as a member of the
JS interface associated with the first parameter's type.

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
JS_FreeValue(ctx, ctx.eval(code, "<test>"))
```

As you can see, `log` has been exposed as a member of the JS interface
`Console`.

It is possible to use a different name for the JS function than for the Nim
procedure. e.g. the following will also expose a `log` function:

```nim
proc jsLog(console: Console; s: string) {.jsfunc: "log".} = # [...]
```

In general, you can use any combination of parameters in `.jsfunc` procs.
These are converted on a best-effort basis: e.g. in the above example,
`console.log(1)` would pass the string "1", not an exception. Monoucha tries to
adhere to the WebIDL standard in this regard. (TODO: find & document places
where this is not true yet.)

The first parameter *must* be a reference type that has been registered using
`registerType`. Alternatively, you can also use a registered non-reference
object type, but in this case, you *must* annotate it with `var`:

```nim
type Console2 = object # not ref!

proc log(console: var Console2; s: string) {.jsfunc.} = # [...]
```

However, it is possible to insert a "zeroeth" parameter to get a reference to
the current JS context. This is useful if you want to access state global to the
JS context without storing a backreference to the global object:

```nim
proc log(ctx: JSContext; console: Console; s: string) {.jsfunc.} =
  # This assumes you have already setGlobal a Window instance.
  let global = JS_GetGlobalObject(ctx)
  let window = fromJS[Window](ctx, global).get
  JS_FreeValue(ctx, global)
  # Now you can do something with the window, e.g.
  window.outFile.writeLine(s)
```

It is also possible to use `varargs` and union types in `.jsfunc` functions:

```nim
proc log(console: Console; ss: varargs[string]) {.jsfunc.} =
  discard # can be called like `console.log("a", "b", "c", "d")`

proc log2[T: int|string](console: Console; x: T) {.jsfunc.} =
  discard # if JS passes a number, typeof(x) will be `int`.
```

Note that union types have some limitations: currently, only the following types
are accepted: `Table`, `seq`, `string`, `JSValue`, `bool`, `int`, `uint32`
`ref object`. If you need more granular type checking, you are advised to take a
`JSValue`.

For further information about individual type conversions, see the
[toJS, fromJS](#tojs-fromjs) section.

### jsctor: constructors

The `.jsctor` pragma is used to define a constructor for a specific type:

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
JS_FreeValue(ctx, ctx.eval(code, "<test>")) # [object File]
```

Note that `.jsctor`, like other pragmas, supports the same "zeroeth" JSContext
parameter trick as [jsfunc](#jsfunc-regular-functions), which is useful when
the global object is needed for resource allocation.

### jsfget, jsfset: custom property reflectors

The `.jsfget` and `.jsfset` pragmas can be used to define custom getter/setter
functions.

Like `.jsget` and `.jsset`, they appear as regular getters and setters in
JS. However, instead of automatically reflecting a property, `.jsfget` and
`.jsfset` allows you to write custom code to handle property accesses.

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
JS_FreeValue(ctx, ctx.eval(code, "<test>"))
```

### jsstfunc: static functions

`.jsstfunc` defines a static function on a given interface. Unlike with
`.jsfunc`, you must provide at least a single parameter for these functions,
with the syntax `Interface.functionName`.

Note that `Interface` must be an interface registered through `registerType`.
If the interface was renamed, the Nim name (*not* the JS name) must be used.

Example:

```nim
# [...] (see above for constructor)

proc jsExists(path: string): bool {.jsstfunc: "JSFile.exists".} =
  return fileExists(path)

# [...]
const code = """
console.log(File.exists("doc/manual.md")); /* true */
"""
JS_FreeValue(ctx, ctx.eval(code, "<test>"))
```
