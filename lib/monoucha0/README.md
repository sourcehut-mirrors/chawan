# Monoucha: seamless Nim-QuickJS integration

Monoucha is a wrapper library to simplify the process of embedding the
[QuickJS](https://bellard.org/quickjs/) JavaScript engine into Nim programs.

## Quick start

Include Monoucha in your project using either Nimble or as a git submodule.

```
requires "monoucha"
```

Then,

* There is a [manual](doc/manual.md). Please read the manual.
* [Examples](test/manual.nim) from the manual, organized as unit tests.

## Warning

Monoucha works with ORC, but it also depends on `=destroy` hooks with ref
objects, which [may leak](https://github.com/nim-lang/Nim/issues/24161)
memory in ORC (the interaction between the two features is "undefined".)

Therefore, for best results you should put the following in your nim.cfg:

```
--mm:refc
```

## Dependencies

Monoucha has no hard dependencies other than QuickJS and the standard
library (in particular, the `tables` module.)  QuickJS in turn has no
dependencies other than libc.

There is an optional `jserror` module which enables error handling that is
generic to Nim and QuickJS using the
[nim-results](https://github.com/arnetheduck/nim-results) library.

QuickJS is already included in this repository; you do not have to install
it separately.

## Q&A

* Cool, so how do I use this thing?

There is a [manual](doc/manual.md). Please read the manual.

* I'm getting memory leaks?

See the [Warning](#warning) section.

(If you are also experiencing issues with refc, please open a ticket
[here](https://todo.sr.ht/~bptato/chawan/) and I'll look into it.)

* I already have QuickJS, why are you not linking to my system library?

Monoucha does not actually use stock QuickJS, but a fork that tracks
upstream.

This fork includes some GC modifications necessary for the synchronization
of the Nim and QuickJS runtimes.

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

QuickJS was written by Fabrice Bellard and Charlie Gordon.  Some patches
from QuickJS-NG (maintained by Ben Noordhuis and Saúl Ibarra Corretgé)
are also included.

QuickJS is distributed in this repository under the terms of the MIT
license.  See the [monoucha/qjs/LICENSE](monoucha/qjs/LICENSE) file for
details.

Monoucha is released into the public domain.  See the [UNLICENSE](UNLICENSE)
file for details.
