# Public variables.
NIM ?= nim
NIMC ?= $(NIM) c
OBJDIR ?= .obj
OUTDIR ?= target
# These paths are quoted in recipes.
PREFIX ?= /usr/local
MANPREFIX ?= $(PREFIX)/share/man
MANPREFIX1 ?= $(MANPREFIX)/man1
MANPREFIX5 ?= $(MANPREFIX)/man5
MANPREFIX7 ?= $(MANPREFIX)/man7
TARGET ?= release
PANDOC ?= pandoc
PKG_CONFIG ?= pkg-config

# Note: this is not a real shell substitution.
# The default setting is at {the binary's path}/../libexec/chawan.
# You may override it with any path if your system does not have a libexec
# directory.
# (This way, `cha' can be directly executed without installation.)
LIBEXECDIR ?= \$$CHA_BIN_DIR/../libexec/chawan

# I won't take this from the environment for obvious reasons. Please override it
# in the make command if you must, or (preferably) fix your environment so it's
# not needed.
DANGER_DISABLE_SANDBOX = 0

# Private variables.
# If overridden, take libexecdir that was specified.
# Otherwise, just install to libexec/chawan.
ifeq ($(LIBEXECDIR),\$$CHA_BIN_DIR/../libexec/chawan)
LIBEXECDIR_CHAWAN = "$(DESTDIR)$(PREFIX)/libexec/chawan"
else
LIBEXECDIR_CHAWAN = $(LIBEXECDIR)
endif

# Static linking.
STATIC_LINK ?= 0

# These paths are quoted in recipes.
OUTDIR_TARGET = $(OUTDIR)/$(TARGET)
OUTDIR_BIN = $(OUTDIR_TARGET)/bin
OUTDIR_LIBEXEC = $(OUTDIR_TARGET)/libexec/chawan
OUTDIR_CGI_BIN = $(OUTDIR_LIBEXEC)/cgi-bin
OUTDIR_MAN = $(OUTDIR_TARGET)/share/man

# Force a poll implementation.  0 - do not force, 1 - poll, 2 - select.
# This is an intentionally undocumented debugging flag; open a ticket if
# you need it on a certain system, because it has subtle issues without
# platform-specific adjustments.
FORCE_POLL_MODE ?= 0

# Nim compiler flags
ifeq ($(TARGET),debug)
FLAGS += -d:debug --debugger:native
else ifeq ($(TARGET),release)
FLAGS += -d:release -d:strip -d:lto
else ifeq ($(TARGET),release0)
FLAGS += -d:release --stacktrace:on
else ifeq ($(TARGET),release1)
FLAGS += -d:release --debugger:native
endif

ssl_link = http gemini sftp
tohtml_link = gopher2html md2html ansi2html gmi2html dirlist2html img2html

protocols_bin = file ftp gopher finger man spartan chabookmark stbi jebp sixel \
	canvas resize nanosvg ssl
converters_bin = uri2html tohtml
tools_bin = urlenc nc
protocols = $(protocols_bin) $(ssl_link)
converters = $(converters_bin) $(tohtml_link)
tools = $(tools_bin) urldec

ifeq ($(STATIC_LINK),1)
LDFLAGS += -static
endif

ifeq ($(FORCE_POLL_MODE),2)
# for seccomp
CFLAGS += -DCHA_FORCE_SELECT
endif

FLAGS += $(foreach flag,$(CFLAGS),-t:$(flag))
FLAGS += $(foreach flag,$(LDFLAGS),-l:$(flag))

FLAGS += -d:disableSandbox=$(DANGER_DISABLE_SANDBOX)
FLAGS += -d:forcePollMode=$(FORCE_POLL_MODE)

ssl_libs = libssl libcrypto libbrotlidec libbrotlicommon libssh2
ssl_flags = $(FLAGS)
ssl_cflags := $(shell $(PKG_CONFIG) --cflags $(ssl_libs) || echo _cha_error)
ifeq ($(ssl_cflags),_cha_error)
$(error failed to find some dependencies)
endif
ssl_ldflags := $(shell $(PKG_CONFIG) --libs $(ssl_libs) || echo _cha_error)
ifeq ($(ssl_ldflags),_cha_error)
$(error failed to find some dependencies)
endif
ssl_flags += $(foreach flag,$(ssl_cflags),-t:$(flag))
ssl_flags += $(foreach flag,$(ssl_ldflags),-l:$(flag))

export CC CFLAGS LDFLAGS PANDOC

binaries = $(OUTDIR_BIN)/cha $(OUTDIR_BIN)/mancha
binaries += $(foreach bin,$(protocols),$(OUTDIR_CGI_BIN)/$(bin))
binaries += $(foreach bin,$(converters),$(OUTDIR_LIBEXEC)/$(bin))
binaries += $(foreach bin,$(tools),$(OUTDIR_LIBEXEC)/$(bin))

.PHONY: all
all: $(binaries)
	ln -sf "$(OUTDIR)/$(TARGET)/bin/cha" cha

ifeq ($(shell uname), Linux)
chaseccomp = lib/chaseccomp/chaseccomp.o

lib/chaseccomp/chaseccomp.o: .FORCE
	(cd lib/chaseccomp && $(MAKE))
.FORCE:
endif

twtstr = src/utils/twtstr.nim src/types/opt.nim
dynstream = src/io/dynstream.nim
chafile = src/io/chafile.nim $(dynstream)
myposix = src/utils/myposix.nim
connectionerror = src/server/connectionerror.nim
lcgi = $(myposix) $(chafile) $(twtstr) $(sandbox) $(connectionerror) \
	adapter/protocol/lcgi.nim
lcgi_ssl = $(lcgi) adapter/protocol/lcgi_ssl.nim
sandbox = src/utils/sandbox.nim $(chaseccomp)
tinfl = adapter/protocol/tinfl.h

# lib/*0 has a 0 so that it doesn't conflict with the old submodules.
# git can't deal with this, it seems.
$(OUTDIR_BIN)/cha: src/*.nim src/*/*.nim src/*/*.c res/* lib/chame0/chame/* \
		lib/chagashi0/chagashi/* lib/monoucha0/monoucha/* \
		lib/monoucha0/monoucha/qjs/* $(chaseccomp) \
		res/charwidth_gen.nim nim.cfg
	@mkdir -p "$(OUTDIR_BIN)"
	$(NIMC) --nimcache:"$(OBJDIR)/$(TARGET)/cha" -d:libexecPath=$(LIBEXECDIR) \
                $(FLAGS) -o:"$(OUTDIR_BIN)/cha" src/main.nim

$(OUTDIR_BIN)/mancha: adapter/tools/mancha.nim $(twtstr) $(myposix) $(chafile)
	@mkdir -p "$(OUTDIR_BIN)"
	$(NIMC) --nimcache:"$(OBJDIR)/$(TARGET)/mancha" $(FLAGS) \
		-o:"$(OUTDIR_BIN)/mancha" adapter/tools/mancha.nim

unicode_version = 17.0.0

.PHONY: unicode_gen
unicode_gen:
	@printf 'Download EastAsianWidth.txt from www.unicode.org? (y/n) '
	@read res; if test "$$res" = "y"; then \
	cha -d 'https://www.unicode.org/Public/$(unicode_version)/ucd/EastAsianWidth.txt' >res/EastAsianWidth.txt; \
	fi
	$(NIMC) --nimcache:"$(OBJDIR)/charwidth_gen_cache" -d:danger -o:"$(OBJDIR)/gencharwidth" res/gencharwidth.nim
	$(OBJDIR)/gencharwidth > res/charwidth_gen.nim~
	mv res/charwidth_gen.nim~ res/charwidth_gen.nim

$(OUTDIR_CGI_BIN)/man: $(lcgi) src/utils/lrewrap.nim \
	lib/monoucha0/monoucha/libregexp.nim \
	lib/monoucha0/monoucha/qjs/libregexp.* \
	lib/monoucha0/monoucha/qjs/libunicode.* \
	lib/monoucha0/monoucha/qjs/cutils.*
$(OUTDIR_CGI_BIN)/file: $(lcgi)
$(OUTDIR_CGI_BIN)/ftp: $(lcgi)
$(OUTDIR_CGI_BIN)/ssl: adapter/protocol/http.nim adapter/protocol/gemini.nim \
	adapter/protocol/sftp.nim $(lcgi_ssl) $(sandbox) $(tinfl)
$(OUTDIR_CGI_BIN)/stbi: adapter/img/stbi.nim adapter/img/stb_image.h \
	adapter/img/stb_image_write.h $(lcgi)
$(OUTDIR_CGI_BIN)/jebp: adapter/img/jebp.h $(lcgi)
$(OUTDIR_CGI_BIN)/sixel: src/types/color.nim $(lcgi)
$(OUTDIR_CGI_BIN)/canvas: src/types/canvastypes.nim src/types/path.nim \
	src/io/packetreader.nim src/types/color.nim adapter/img/stb_image.h \
	$(lcgi)
$(OUTDIR_CGI_BIN)/resize: adapter/img/stb_image_resize.h $(lcgi)
$(OUTDIR_CGI_BIN)/nanosvg: adapter/img/nanosvg.nim adapter/img/nanosvg.h \
	adapter/img/nanosvgrast.h $(lcgi)
$(OUTDIR_LIBEXEC)/urlenc: $(twtstr) $(chafile)
$(OUTDIR_LIBEXEC)/nc: $(lcgi)
$(OUTDIR_LIBEXEC)/tohtml: adapter/format/ansi2html.nim adapter/format/dirlist2html.nim \
	adapter/format/gmi2html.nim adapter/format/gopher2html.nim \
	adapter/format/md2html.nim adapter/format/img2html.nim \
	$(twtstr) $(chafile) $(dynstream) src/types/color.nim

$(foreach it,$(ssl_link),$(OUTDIR_CGI_BIN)/$(it)): $(OUTDIR_CGI_BIN)/ssl
	(cd "$(OUTDIR_CGI_BIN)" && ln -sf ssl $(notdir $@))

$(foreach it,$(tohtml_link),$(OUTDIR_LIBEXEC)/$(it)): $(OUTDIR_LIBEXEC)/tohtml
	(cd "$(OUTDIR_LIBEXEC)" && ln -sf tohtml $(notdir $@))

$(OUTDIR_CGI_BIN)/%: adapter/protocol/%.nim adapter/nim.cfg
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(notdir $@)" -o:"$@" $<

$(OUTDIR_CGI_BIN)/ssl: adapter/protocol/ssl.nim adapter/nim.cfg
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	$(NIMC) $(ssl_flags) --nimcache:"$(OBJDIR)/$(TARGET)/$(notdir $@)" -o:"$@" $<

$(OUTDIR_CGI_BIN)/%: adapter/protocol/%
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	install -m755 $< "$(OUTDIR_CGI_BIN)"

$(OUTDIR_LIBEXEC)/%: adapter/format/%
	@mkdir -p "$(OUTDIR_LIBEXEC)"
	install -m755 $< "$(OUTDIR_LIBEXEC)"

$(OUTDIR_CGI_BIN)/%: adapter/img/%.nim adapter/nim.cfg
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	rm -rf "$(OBJDIR)/$(TARGET)/$(notdir $@)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(notdir $@)" -o:"$@" $<

$(OUTDIR_LIBEXEC)/%: adapter/format/%.nim adapter/nim.cfg
	@mkdir -p "$(OUTDIR_LIBEXEC)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(notdir $@)" -o:"$@" $<

$(OUTDIR_LIBEXEC)/%: adapter/tools/%.nim adapter/nim.cfg
	@mkdir -p "$(OUTDIR_LIBEXEC)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(notdir $@)" -o:"$@" $<

$(OUTDIR_LIBEXEC)/urldec: $(OUTDIR_LIBEXEC)/urlenc
	(cd "$(OUTDIR_LIBEXEC)" && ln -sf urlenc urldec)

doc/%.1: doc/%.md md2man
	./md2man $< > $@~
	mv $@~ $@

doc/cha-%.5: doc/%.md md2man
	./md2man $< > $@~
	mv $@~ $@

doc/cha-%.7: doc/%.md md2man
	./md2man $< > $@~
	mv $@~ $@

.PHONY: clean
clean:
	rm -rf "$(OBJDIR)/$(TARGET)"
	(cd lib/chaseccomp && $(MAKE) clean)

.PHONY: distclean
distclean: clean
	rm -rf "$(OUTDIR)"

manpages1 = cha.1 mancha.1
manpages5 = cha-config.5 cha-mailcap.5 cha-mime.types.5 cha-localcgi.5 \
	cha-urimethodmap.5
manpages7 = cha-protocols.7 cha-api.7 cha-troubleshooting.7 cha-image.7 cha-css.7 cha-terminal.7

manpages = $(manpages1) $(manpages5) $(manpages7)

.PHONY: manpage
manpage: $(manpages:%=doc/%)

.PHONY: install
install:
	mkdir -p "$(DESTDIR)$(PREFIX)/bin"
	install -m755 "$(OUTDIR_BIN)/cha" "$(DESTDIR)$(PREFIX)/bin"
	install -m755 "$(OUTDIR_BIN)/mancha" "$(DESTDIR)$(PREFIX)/bin"
# intentionally not quoted
	mkdir -p $(LIBEXECDIR_CHAWAN)/cgi-bin
	for f in $(protocols_bin); do \
	install -m755 "$(OUTDIR_CGI_BIN)/$$f" $(LIBEXECDIR_CHAWAN)/cgi-bin; \
	done
	for f in $(converters_bin) $(tools_bin); \
	do install -m755 "$(OUTDIR_LIBEXEC)/$$f" $(LIBEXECDIR_CHAWAN); \
	done
	(cd $(LIBEXECDIR_CHAWAN) && ln -sf urlenc urldec)
	for f in $(ssl_link); do (cd $(LIBEXECDIR_CHAWAN)/cgi-bin && ln -sf ssl "$$f"); done
	for f in $(tohtml_link); do (cd $(LIBEXECDIR_CHAWAN) && ln -sf tohtml "$$f"); done
	mkdir -p "$(DESTDIR)$(MANPREFIX1)"
	for f in $(manpages1); do install -m644 "doc/$$f" "$(DESTDIR)$(MANPREFIX1)"; done
	mkdir -p "$(DESTDIR)$(MANPREFIX5)"
	for f in $(manpages5); do install -m644 "doc/$$f" "$(DESTDIR)$(MANPREFIX5)"; done
	mkdir -p "$(DESTDIR)$(MANPREFIX7)"
	for f in $(manpages7); do install -m644 "doc/$$f" "$(DESTDIR)$(MANPREFIX7)"; done

.PHONY: uninstall
uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/cha"
	rm -f "$(DESTDIR)$(PREFIX)/bin/mancha"
# intentionally not quoted
	for f in $(protocols); do rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/$$f; done
	for f in $(converters) $(tools); do rm -f $(LIBEXECDIR_CHAWAN)/$$f; done
# We only want to uninstall binaries that the main distribution
# includes or has ever included, but not those that the user might have
# added.  Some of these cannot be directly derived from our variables:
# * png has been removed in favor of stbi
# * data, about have been moved back into the main binary
# * gmifetch has been replaced by gemini
# * cha-finger has been renamed to finger
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/about
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/cha-finger
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/data
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/gmifetch
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/png
	rmdir $(LIBEXECDIR_CHAWAN)/cgi-bin || true
	rmdir $(LIBEXECDIR_CHAWAN) || true
	for f in $(manpages7); do rm -f "$(DESTDIR)$(MANPREFIX7)/$$f"; done
	for f in $(manpages5); do rm -f "$(DESTDIR)$(MANPREFIX5)/$$f"; done
# moved to section 7
	for f in cha-protocols.5 cha-api.5 cha-troubleshooting.5 cha-image.5; do rm -f "$(DESTDIR)$(MANPREFIX5)/$$f"; done
	for f in $(manpages1); do rm -f "$(DESTDIR)$(MANPREFIX1)/$$f"; done

test/net/run: test/net/run.nim
	$(NIMC) test/net/run.nim

.PHONY: test_js
test_js:
	(cd test/js && ./run.sh)

.PHONY: test_layout
test_layout:
	(cd test/layout && ./run.sh)

.PHONY: test_md
test_md:
	(cd test/md && ./run.sh)

.PHONY: test_net
test_net: test/net/run
	(cd test/net && ./run.sh)

.PHONY: test
test: test_js test_layout test_net test_md
