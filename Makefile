NIM ?= nim
NIMC ?= $(NIM) c
OBJDIR ?= .obj
OUTDIR ?= target
# These paths are quoted in recipes.
PREFIX ?= /usr/local
MANPREFIX ?= $(PREFIX)/share/man
MANPREFIX1 ?= $(MANPREFIX)/man1
MANPREFIX5 ?= $(MANPREFIX)/man5
TARGET ?= release
# This must be single-quoted, because it is not a real shell substitution.
# The default setting is at {the binary's path}/../libexec/chawan.
# You may override it with any path if your system does not have a libexec
# directory, but make sure to surround it with quotes if it contains spaces.
# (This way, the cha binary can be directly executed without installation.)
LIBEXECDIR ?= '$$CHA_BIN_DIR/../libexec/chawan'
# If overridden, take libexecdir that was specified.
# Otherwise, just install to libexec/chawan.
ifeq ($(LIBEXECDIR),'$$CHA_BIN_DIR/../libexec/chawan')
LIBEXECDIR_CHAWAN = "$(DESTDIR)$(PREFIX)/libexec/chawan"
else
LIBEXECDIR_CHAWAN = $(LIBEXECDIR)
endif

# These paths are quoted in recipes.
OUTDIR_TARGET = $(OUTDIR)/$(TARGET)
OUTDIR_BIN = $(OUTDIR_TARGET)/bin
OUTDIR_LIBEXEC = $(OUTDIR_TARGET)/libexec/chawan
OUTDIR_CGI_BIN = $(OUTDIR_LIBEXEC)/cgi-bin
OUTDIR_MAN = $(OUTDIR_TARGET)/share/man

# I won't take this from the environment for obvious reasons. Please override it
# in the make command if you must, or (preferably) fix your environment so it's
# not needed.
DANGER_DISABLE_SANDBOX = 0

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

ifneq ($(CFLAGS),)
FLAGS += $(foreach flag,$(CFLAGS),--passc:$(flag))
endif
ifneq ($(LDFLAGS),)
FLAGS += $(foreach flag,$(LDFLAGS),--passl:$(flag))
endif

.PHONY: all
all: $(OUTDIR_BIN)/cha $(OUTDIR_BIN)/mancha $(OUTDIR_CGI_BIN)/http \
	$(OUTDIR_CGI_BIN)/gemini $(OUTDIR_LIBEXEC)/gmi2html \
	$(OUTDIR_CGI_BIN)/gopher $(OUTDIR_LIBEXEC)/gopher2html \
	$(OUTDIR_CGI_BIN)/finger $(OUTDIR_CGI_BIN)/about \
	$(OUTDIR_CGI_BIN)/file $(OUTDIR_CGI_BIN)/ftp $(OUTDIR_CGI_BIN)/sftp \
	$(OUTDIR_LIBEXEC)/dirlist2html $(OUTDIR_LIBEXEC)/uri2html \
	$(OUTDIR_CGI_BIN)/man $(OUTDIR_CGI_BIN)/spartan \
	$(OUTDIR_CGI_BIN)/stbi $(OUTDIR_CGI_BIN)/jebp $(OUTDIR_CGI_BIN)/canvas \
	$(OUTDIR_CGI_BIN)/nanosvg $(OUTDIR_CGI_BIN)/sixel $(OUTDIR_CGI_BIN)/resize \
	$(OUTDIR_CGI_BIN)/chabookmark \
	$(OUTDIR_LIBEXEC)/urldec $(OUTDIR_LIBEXEC)/urlenc $(OUTDIR_LIBEXEC)/nc \
	$(OUTDIR_LIBEXEC)/md2html $(OUTDIR_LIBEXEC)/ansi2html
	ln -sf "$(OUTDIR)/$(TARGET)/bin/cha" cha

ifeq ($(shell uname), Linux)
chaseccomp = lib/chaseccomp/chaseccomp.o

lib/chaseccomp/chaseccomp.o: .FORCE
	(cd lib/chaseccomp && $(MAKE))
.FORCE:
endif

$(OUTDIR_BIN)/cha: src/*.nim src/**/*.nim src/**/*.c res/* res/**/* \
		$(chaseccomp) res/map/idna_gen.nim nim.cfg
	@mkdir -p "$(OUTDIR_BIN)"
	$(NIMC) --nimcache:"$(OBJDIR)/$(TARGET)/cha" -d:libexecPath=$(LIBEXECDIR) \
                -d:disableSandbox=$(DANGER_DISABLE_SANDBOX) $(FLAGS) \
		-o:"$(OUTDIR_BIN)/cha" src/main.nim

$(OUTDIR_BIN)/mancha: adapter/tools/mancha.nim
	@mkdir -p "$(OUTDIR_BIN)"
	$(NIMC) --nimcache:"$(OBJDIR)/$(TARGET)/mancha" $(FLAGS) \
		-o:"$(OUTDIR_BIN)/mancha" $(FLAGS) adapter/tools/mancha.nim

unicode_version = 16.0.0

.PHONY: unicode_gen
unicode_gen: $(OBJDIR)/genidna $(OBJDIR)/gencharwidth
	@printf 'Download EastAsianWidth.txt and IdnaMappingTable.txt from www.unicode.org? (y/n) '
	@read res; if test "$$res" = "y"; then \
	cha -d 'https://www.unicode.org/Public/idna/$(unicode_version)/IdnaMappingTable.txt' >res/map/IdnaMappingTable.txt; \
	cha -d 'https://www.unicode.org/Public/$(unicode_version)/ucd/EastAsianWidth.txt' >res/map/EastAsianWidth.txt; \
	fi
	$(NIMC) --nimcache:"$(OBJDIR)/idna_gen_cache" -d:danger -o:"$(OBJDIR)/genidna" res/genidna.nim
	$(NIMC) --nimcache:"$(OBJDIR)/charwidth_gen_cache" -d:danger -o:"$(OBJDIR)/gencharwidth" res/gencharwidth.nim
	$(OBJDIR)/genidna > res/map/idna_gen.nim
	$(OBJDIR)/gencharwidth > res/map/charwidth_gen.nim

twtstr = src/utils/twtstr.nim src/utils/map.nim src/types/opt.nim
dynstream = src/io/dynstream.nim src/io/dynstream_aux.c
lcgi = $(dynstream) $(twtstr) $(sandbox) adapter/protocol/lcgi.nim
lcgi_ssl = $(lcgi) adapter/protocol/lcgi_ssl.nim
sandbox = src/utils/sandbox.nim $(chaseccomp)

$(OUTDIR_CGI_BIN)/man: $(twtstr)
$(OUTDIR_CGI_BIN)/http: adapter/protocol/curl.nim $(sandbox)
$(OUTDIR_CGI_BIN)/about: res/chawan.html res/license.md
$(OUTDIR_CGI_BIN)/file: $(twtstr)
$(OUTDIR_CGI_BIN)/ftp: $(lcgi)
$(OUTDIR_CGI_BIN)/sftp: $(lcgi) $(twtstr)
$(OUTDIR_CGI_BIN)/gemini: $(lcgi_ssl)
$(OUTDIR_CGI_BIN)/stbi: adapter/img/stbi.nim adapter/img/stb_image.c \
		adapter/img/stb_image.h $(sandbox) $(dynstream)
$(OUTDIR_CGI_BIN)/jebp: adapter/img/jebp.c adapter/img/jebp.h $(sandbox)
$(OUTDIR_CGI_BIN)/sixel: src/types/color.nim $(sandbox) $(twtstr) $(dynstream)
$(OUTDIR_CGI_BIN)/canvas: src/types/canvastypes.nim src/types/path.nim \
	src/io/bufreader.nim src/types/color.nim $(sandbox) $(dynstream) $(twtstr)
$(OUTDIR_CGI_BIN)/resize: adapter/img/stb_image_resize.h adapter/img/stb_image_resize.c \
	$(sandbox) $(dynstream) $(twtstr)
$(OUTDIR_CGI_BIN)/nanosvg: adapter/img/nanosvg.nim adapter/img/nanosvg.c adapter/img/nanosvg.h
$(OUTDIR_LIBEXEC)/urlenc: $(twtstr)
$(OUTDIR_LIBEXEC)/nc: $(lcgi)
$(OUTDIR_LIBEXEC)/gopher2html: $(twtstr)
$(OUTDIR_LIBEXEC)/ansi2html: src/types/color.nim src/io/poll.nim $(twtstr) $(dynstream)
$(OUTDIR_LIBEXEC)/md2html: $(twtstr)
$(OUTDIR_LIBEXEC)/dirlist2html: $(twtstr)

$(OUTDIR_CGI_BIN)/%: adapter/protocol/%.nim
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(subst $(OUTDIR_CGI_BIN)/,,$@)" \
		-d:disableSandbox=$(DANGER_DISABLE_SANDBOX) -d:curlLibName=$(CURLLIBNAME) \
		-o:"$@" $<

$(OUTDIR_CGI_BIN)/%: adapter/protocol/%
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	install -m755 $< "$(OUTDIR_CGI_BIN)"

$(OUTDIR_LIBEXEC)/%: adapter/format/%
	@mkdir -p "$(OUTDIR_LIBEXEC)"
	install -m755 $< "$(OUTDIR_LIBEXEC)"

$(OUTDIR_CGI_BIN)/%: adapter/img/%.nim
	@mkdir -p "$(OUTDIR_CGI_BIN)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(subst $(OUTDIR_CGI_BIN)/,,$@)" \
                -d:disableSandbox=$(DANGER_DISABLE_SANDBOX) -o:"$@" $<

$(OUTDIR_LIBEXEC)/%: adapter/format/%.nim
	@mkdir -p "$(OUTDIR_LIBEXEC)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(subst $(OUTDIR_LIBEXEC)/,,$@)" \
		-o:"$@" $<

$(OUTDIR_LIBEXEC)/%: adapter/tools/%.nim
	@mkdir -p "$(OUTDIR_LIBEXEC)"
	$(NIMC) $(FLAGS) --nimcache:"$(OBJDIR)/$(TARGET)/$(subst $(OUTDIR_LIBEXEC)/,,$@)" \
		-o:"$@" $<

$(OUTDIR_LIBEXEC)/urldec: $(OUTDIR_LIBEXEC)/urlenc
	(cd "$(OUTDIR_LIBEXEC)" && ln -sf urlenc urldec)

$(OBJDIR)/man/cha-%.md: doc/%.md md2manpreproc
	@mkdir -p "$(OBJDIR)/man"
	./md2manpreproc $< > $@

doc/cha-%.5: $(OBJDIR)/man/cha-%.md
	pandoc --standalone --to man $< -o $@

.PHONY: clean
clean:
	rm -rf "$(OBJDIR)/$(TARGET)"
	(cd lib/chaseccomp && $(MAKE) clean)

.PHONY: distclean
distclean: clean
	rm -rf "$(OUTDIR)"

manpages1 = cha.1 mancha.1
manpages5 = cha-config.5 cha-mailcap.5 cha-mime.types.5 cha-localcgi.5 \
	cha-urimethodmap.5 cha-protocols.5 cha-api.5 cha-troubleshooting.5 \
	cha-image.5

manpages = $(manpages1) $(manpages5)

.PHONY: manpage
manpage: $(manpages:%=doc/%)

protocols = http about file ftp sftp gopher gemini finger man spartan stbi \
	jebp sixel canvas resize chabookmark nanosvg
converters = gopher2html md2html ansi2html gmi2html dirlist2html uri2html
tools = urlenc nc

.PHONY: install
install:
	mkdir -p "$(DESTDIR)$(PREFIX)/bin"
	install -m755 "$(OUTDIR_BIN)/cha" "$(DESTDIR)$(PREFIX)/bin"
	install -m755 "$(OUTDIR_BIN)/mancha" "$(DESTDIR)$(PREFIX)/bin"
# intentionally not quoted
	mkdir -p $(LIBEXECDIR_CHAWAN)/cgi-bin
	for f in $(protocols); do \
	install -m755 "$(OUTDIR_CGI_BIN)/$$f" $(LIBEXECDIR_CHAWAN)/cgi-bin; \
	done
	for f in $(converters) $(tools); \
	do install -m755 "$(OUTDIR_LIBEXEC)/$$f" $(LIBEXECDIR_CHAWAN); \
	done
# urldec is just a symlink to urlenc
	(cd $(LIBEXECDIR_CHAWAN) && ln -sf urlenc urldec)
	mkdir -p "$(DESTDIR)$(MANPREFIX1)"
	for f in $(manpages1); do install -m644 "doc/$$f" "$(DESTDIR)$(MANPREFIX1)"; done
	mkdir -p "$(DESTDIR)$(MANPREFIX5)"
	for f in $(manpages5); do install -m644 "doc/$$f" "$(DESTDIR)$(MANPREFIX5)"; done

.PHONY: uninstall
uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/cha"
	rm -f "$(DESTDIR)$(PREFIX)/bin/mancha"
# intentionally not quoted
	for f in $(protocols); do rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/$$f; done
# notes:
# * png has been removed in favor of stbi
# * data has been moved back into the main binary
# * gmifetch has been replaced by gemini
# * cha-finger has been renamed to finger
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/png
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/data
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/gmifetch
	rm -f $(LIBEXECDIR_CHAWAN)/cgi-bin/cha-finger
	rmdir $(LIBEXECDIR_CHAWAN)/cgi-bin || true
	for f in $(converters) $(tools); do rm -f $(LIBEXECDIR_CHAWAN)/$$f; done
# urldec is just a symlink to urlenc
	rm -f $(LIBEXECDIR_CHAWAN)/urldec
	rmdir $(LIBEXECDIR_CHAWAN) || true
	for f in $(manpages5); do rm -f "$(DESTDIR)$(MANPREFIX5)/$$f"; done
	for f in $(manpages1); do rm -f "$(DESTDIR)$(MANPREFIX1)/$$f"; done

.PHONY: submodule
submodule:
	git submodule update --init

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
	(cd test/net && ./run)

.PHONY: test
test: test_js test_layout test_net test_md
