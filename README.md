# Monoucha: seamless Nim-QuickJS integration

Monoucha is a wrapper library to simplify the process of embedding the QuickJS
JavaScript engine into Nim programs.

## Quick start

Include Monoucha in your project using either Nimble or as a git submodule.

```
requires "monoucha >= 0.2.1"
```

Then,

* There is a [manual](doc/manual.md). Please read the manual.
* [Examples](test/manual.nim) from the manual, organized as unit tests.

## Example

```nim
# Compile with nim c --mm:refc!
import monoucha/fromjs
import monoucha/javascript
import results

type
  MyGlobal = ref object
    console {.jsget.}: Console

  Console = ref object

jsDestructor(Console)

proc log(console: Console; s: string) {.jsfunc.} =
  echo s

proc main() =
  let global = MyGlobal(console: Console())
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(MyGlobal, asglobal = true)
  ctx.registerType(Console)
  ctx.setGlobal(global)
  const code = """
console.log("Hello from Nim!");
"Hello from JS!";
"""
  let res = ctx.eval(code, "<test>") # Hello from Nim!
  echo fromJS[string](ctx, res).get # Hello from JS!
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

main()
```

Above code does the following:

* Create a new QuickJS runtime & a QuickJS context in that runtime
* Register the MyGlobal and Console types, and generate bindings for the
  `console` property of MyGlobal and the `log` function of Console
* Evaluate JS code in this context
* Convert the result of the evaluated JS code to a Nim string, and print it
* Free the result, then free the context

## Warning

At the time of writing, Monoucha only works with refc. This means you have to
put the following in your nim.cfg:

```
--mm:refc
```

If you do not do this, you will be rewarded with strange crashes as your program
grows.

## Dependencies

monoucha depends on the [nim-results](https://github.com/arnetheduck/nim-results.git)
library.

QuickJS is already included in this repository; you do not need to install it
separately.

## Q&A

* Cool, so how do I use this thing?

I'm working on a [manual](doc/manual.md). Please read the manual.

* I'm getting weird memory errors?

You did not read the above instructions, you have to set --mm:refc.

Monoucha does not (and never did) work with ORC, or other memory managers for
that matter. You must use refc.

* I already have QuickJS, why are you not linking to my system library?

Monoucha does not actually use stock QuickJS, but a fork that tracks upstream.
This fork includes some GC hacks necessary for proper integration of the Nim and
QuickJS runtimes.

* Can I compile Nim to JS and execute Nim from Nim?

Possibilities are endless, but [this](https://peterme.net/using-nimscript-as-a-configuration-language-embedding-nimscript-pt-1.html)
looks like a better solution.

* Can I use Monoucha with `[insert JS engine]` instead of QuickJS?

No. Feel free to fork and adapt it to whatever engine you want, but here we only
support QuickJS.

* What *is* a monoucha?

A kind of tea, from the town once called Monou. You pronounce it as mo-no-u-cha.

Yes, it's a [pun](https://en.wikipedia.org/w/index.php?title=SpiderMonkey&oldid=1214134789#History).

## License

QuickJS was written by Fabrice Bellard and Charlie Gordon, and is distributed
in this repository under the terms of the MIT license. See the
[monoucha/qjs/LICENSE](monoucha/qjs/LICENSE) file for details.

Monoucha is released into the public domain. See the [UNLICENSE](UNLICENSE) file
for details.
