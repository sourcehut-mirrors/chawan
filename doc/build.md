# Building Chawan

Chawan uses GNU make for builds.

## Variables

Following is a list of variables which may be safely overridden. You can
also override them by setting an environment variable with the same name.

* `TARGET`: the build target.
	- `debug`: Generate a debug build, with stack traces and
	  debugging symbols enabled. Useful for debugging, but generates
	  huge and slow executables.
	- `release`: The default target. Uses LTO and strips the final
	  binaries.
	- `release0`: A release build with stack traces enabled. Useful
	  when you need to debug a crash that needs a lot of processing
	  to manifest. Note: this does not enable line traces.
	- `release1`: A release build with debugging symbols enabled.
	  Useful for profiling with cachegrind, or debugging a release
	  build with gdb.
* `OUTDIR`: where to output the files.
* `NIM`: path to the Nim compiler.
* `CFLAGS`, `LDFLAGS`: flags to pass to the C compiler at compile or
  link time.
* `OBJDIR`: directory to output compilation artifacts. By default, it is
  `.obj`.
* `PREFIX`: installation prefix, by default it is `/usr/local`.
* `DESTDIR`: directory prepended to `$(PREFIX)`. e.g. you can set it to
  `/tmp`, so that `make install` installs the binary to the path
  `/tmp/usr/local/bin/cha`.
* `MANPREFIX`, `MANPREFIX1`, `MANPREFIX5`: prefixes for the installation
  of man pages. The default setting expands to
  `/usr/local/share/man/man1`, etc.  (Normally you shouldn't have to
  set `MANPREFIX1` or `MANPREFIX5` at all, as these are derived from
  `MANPREFIX`.)
* `LIBEXECDIR`: Path to your libexec directory; by default, it is
  relative to wherever the binary is placed when it is executed. (i.e.
  after installation it would resolve to `/usr/local/libexec`.)
* `STATIC_LINK`: Set it to 1 for static linking.
* `DANGER_DISABLE_SANDBOX`: Set it to 1 to forcibly disable syscall
  filtering. Note that this is *not* taken from the environment
  variables, and you must use it like `make DANGER_DISABLE_SANDBOX=1`.  
  **Warning**: as the name suggests, this is rarely an optimal solution
  to whatever problem you are facing.

This list does not include the `CC` variable, because Nim only supports
a limited set of C compilers. If you want to override the C compiler:

1. Set `CC` to the respective compiler anyways, because it is used by
   chaseccomp.
2. If your compiler is supported by Nim, then set e.g. `FLAGS=--cc:clang`.
   Check the list of supported compilers with `nim --cc:help`.
3. If your compiler is not supported by Nim, but emulates another
   compiler driver, then add e.g.
   `FLAGS=--gcc.path=/usr/local/musl/bin --gcc.exe=musl-gcc --gcc.linkerexe=musl-gcc`

## Phony targets

* `all`: build all required executables
* `clean`: remove OBJDIR (i.e. object files, but not the built executables)
* `distclean`: remove OBJDIR and OUTDIR (i.e. both object files and executables)
* `manpage`: rebuild man pages; note that this is not part of `all`.
  Manual pages are included in the repository, so this only needs to be called
  when you modify the documentation.
* `install`: install the `cha` binary, and if man pages were generated,
  those as well
* `uninstall`: remove the `cha` binary and Chawan man pages

## Cross-compiling

[Apparently](https://todo.sr.ht/~bptato/chawan/37) it's possible.
From user cutenice (with dependencies updated):

> With the latest changes, I could simply run
> `CFLAGS=-m32 LDFLAGS=-m32 FLAGS=--cpu:i386 make` to cross-compile!
>
> I don't know if I have any additional insight from today's
> exploration.. On Arch I needed these things:
>
> - `nim-git` from the AUR
>   - the version available in the repos isn't quite new enough it
>     seems. I think it's related to #12 (at least i got similar looking
>     errors)
> - enable the multilib repository in `/etc/pacman.conf`
> - `pacman -S lib32-openssl lib32-libxcrypt lib32-libssh2`
>   - most of these packages pull packages like `lib32-gcc-libs` and
>     `lib32-glibc` which might be useful as well haha
> - the rest can be eluded from the PKGBUILD in the
>   [AUR](https://aur.archlinux.org/packages/chawan-git)

## Static linking

Tested with musl as follows:

* Install musl to the default path (`/usr/local/musl`)
* Add the following to `$HOME/nim.cfg`:

```
cc:gcc
gcc.path = "/usr/local/musl/bin"
gcc.exe = "musl-gcc"
gcc.linkerexe = "musl-gcc"
```

* Compile and install OpenSSL, libssh2, libbrotlicommon and libbrotlidec
  to `/usr/local/musl`.
* Compile Chawan:

```sh
$ export PKG_CONFIG_PATH=/usr/local/musl/lib/pkgconfig:/usr/local/musl/lib64/pkgconfig
$ export CC=musl-gcc STATIC_LINK=1
$ make distclean
$ make
```
