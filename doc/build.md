# Building Chawan

Chawan uses GNU make for builds.

## Variables

Following is a list of variables which may be safely overridden. You can
also override them by setting an environment variable with the same name.

* `TARGET`: the build target. By default, this is `release`; for development,
  `debug` is recommended.<br>
  This variable changes flags passed to the Nim compiler as follows:
	- `debug`: Generate a debug build, with --debugger:native (embedded
	  debugging symbols) enabled. This is useful for debugging, but
	  generates huge and slow executables.
	- `release`: This is the default target. We use LTO and strip the
	  final binary.
	- `release0`: A release build with stack traces enabled. Useful when
	  you need to debug a crash that needs a lot of processing to manifest.
	  Note: this does not enable line traces, so you only get the function
	  name in stack traces.
	- `release1`: A release build with --debugger:native enabled. May
	  be useful for profiling with cachegrind, or debugging a release
	  build with with gdb.
* `OUTDIR`: where to output the files.
* `NIMC`: path to the Nim compiler. Note that you need to include the flag
  for compilation; by default it is set to `nim c`.
* `OBJDIR`: directory to output compilation artifacts. By default, it is
  set to `.obj`.<br>
  You may be able to speed up compilation somewhat by setting it to an
  in-memory file system.
* `PREFIX`: installation prefix, by default it is `/usr/local`.
* `DESTDIR`: directory prepended to `$(PREFIX)`. e.g. we can set it to
  `/tmp`, so that `make install` installs the binary to the path
  `/tmp/usr/local/bin/cha`.
* `MANPREFIX`, `MANPREFIX1`, `MANPREFIX5`: prefixes for the installation of
  man pages. The default setting expands to `/usr/local/share/man/man1`, etc.
  (Normally you shouldn't have to set `MANPREFIX1` or `MANPREFIX5` at all,
  as these are derived from `MANPREFIX`.)
* `CURLLIBNAME`: Change the name of the libcurl shared object file.
* `LIBEXECDIR`: Path to your libexec directory; by default, it is relative
  to wherever the binary is placed when it is executed. (i.e. after installation
  it would resolve to `/usr/local/libexec`.) <BR>
  WARNING: Unlike other path names, this must be quoted if your path contains
  spaces!
* `DANGER_DISABLE_SANDBOX`: Set it to 1 to disable syscall sandboxing even
  on systems where we have built-in sandboxing support. Note that this is
  *not* taken from the environment variables; you must use it like
  `make DANGER_DISABLE_SANDBOX=1`.<BR>
  WARNING: as the name suggests, this is rarely an optimal solution to whatever
  problem you are facing.

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
* `submodule`: download the submodules required for the browser to build
  (for those of us who keep forgetting the corresponding git command :)
