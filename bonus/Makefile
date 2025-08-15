CHA_CGI_DIR ?= "$$(cha -r 'pager.externInto("cat", getenv("CHA_DIR")+"/cgi-bin")')"

prefix = /usr/local

bindir = $(DESTDIR)$(prefix)/bin

.PHONY: none
none:
	@echo "Run make install-{file} to install a script."

.PHONY: install-git.cgi
install-git.cgi: git.cgi
	mkdir -p $(CHA_CGI_DIR)
	cp git.cgi $(CHA_CGI_DIR)
	./addurimethod git git.cgi
#TODO this will almost never work unless the user is root...
	ln -s $(CHA_CGI_DIR)/git.cgi $(bindir)/gitcha

.PHONY: install-filei.cgi
install-filei.cgi: filei.cgi
	mkdir -p $(CHA_CGI_DIR)
	cp filei.cgi $(CHA_CGI_DIR)

stbir2_url=https://raw.githubusercontent.com/nothings/stb/master/stb_image_resize2.h

stbir2/stb_image_resize2.h:
	@printf 'stb_image_resize2.h not found.\n'
	@printf 'Should I download it from $(stbir2_url)? (y/n) '
	@read -r res; if test "$$res" = "y"; then \
	cd stbir2; cha -d "$(stbir2_url)" >stb_image_resize2.h; \
	else exit 1; \
	fi

.PHONY: install-stbir2
install-stbir2: stbir2/stbir2.nim stbir2/stb_image_resize2.h stbir2/stb_image_resize2.c
	mkdir -p $(CHA_CGI_DIR)
	nim c -d:release -d:lto -o:$(CHA_CGI_DIR)/resize stbir2/stbir2.nim

.PHONY: install-libfetch.c
install-libfetch-http.c: $(CHA_CGI_DIR)/libfetch-http
	$(CC) -Wall -O2 -g -std=c89 $< -lfetch -o $@
	./addurimethod http libfetch-http
	./addurimethod https libfetch-http

.PHONY: install-magnet.cgi
install-magnet.cgi: magnet.cgi
	mkdir -p $(CHA_CGI_DIR)
	cp magnet.cgi $(CHA_CGI_DIR)
	./addurimethod magnet magnet.cgi

.PHONY: install-curlhttp
install-curlhttp:
	mkdir -p $(CHA_CGI_DIR)
	nim c -f -d:release -d:lto -d:curlLibName=$(CURLLIBNAME) \
		-o:$(CHA_CGI_DIR)/curlhttp curlhttp.nim
	./addurimethod http curlhttp
	./addurimethod https curlhttp

.PHONY: install-trans.cgi
install-trans.cgi: trans.cgi
	mkdir -p $(CHA_CGI_DIR)
	cp trans.cgi $(CHA_CGI_DIR)
	@echo
	@echo 'Add this to your config.toml:'
	@echo
	@echo '[page]'
	@echo "gT = '''"
	@echo 'async () => {'
	@echo '  if (!pager.currentSelection) {'
	@echo '    pager.alert("No selection to translate.");'
	@echo '    return;'
	@echo '  }'
	@echo '  const text = await pager.getSelectionText(pager.currentSelection);'
	@echo '  pager.cursorToggleSelection();'
	@echo '  pager.loadSubmit(`cgi-bin:trans.cgi?${encodeURIComponent(text)}`);'
	@echo '}'
	@echo "'''"
