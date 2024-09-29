# Monoucha: seamless Nim-QuickJS integration

Monoucha is a wrapper library to simplify the process of embedding the
[QuickJS-NG](https://github.com/quickjs-ng/quickjs) JavaScript engine into Nim
programs.

## Quick start

Include Monoucha in your project using either Nimble or as a git submodule.

```
requires "monoucha"
```

Then,

* There is a [manual](doc/manual.md). Please read the manual.
* [Examples](test/manual.nim) from the manual, organized as unit tests.

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

QuickJS-NG is already included in this repository; you do not need to install it
separately.

## Q&A

* Cool, so how do I use this thing?

I'm working on a [manual](doc/manual.md). Please read the manual.

* I'm getting weird memory errors?

You did not read the above instructions, you have to set --mm:refc.

Monoucha does not (and never did) work with ORC, or other memory managers for
that matter. You must use refc.

(If you are still experiencing issues, please open a ticket
[here](https://todo.sr.ht/~bptato/chawan/) and I'll look into it.)

* I already have QuickJS-NG, why are you not linking to my system library?

Monoucha does not actually use stock QuickJS-NG, but a fork that tracks
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

QuickJS was written by Fabrice Bellard and Charlie Gordon, and is maintained as
QuickJS-NG by Ben Noordhuis and Saúl Ibarra Corretgé.

QuickJS-NG is distributed in this repository under the terms of the MIT
license. See the [monoucha/qjs/LICENSE](monoucha/qjs/LICENSE) file for details.

Monoucha is released into the public domain. See the [UNLICENSE](UNLICENSE) file
for details.
