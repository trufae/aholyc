# aholyc - another Holy-C compiler. Zero external dependencies: only cc + make.
CC ?= cc
CFLAGS ?= -Os -Wall -Wextra -std=gnu99
LDFLAGS ?=
PREFIX ?= /usr/local
DESTDIR ?=
CWD=$(shell pwd)

SRC = src/main.c src/lex.c src/parse.c src/util.c src/exe.c src/fmt.c \
      src/back_c.c src/back_ll.c src/back_js.c
OBJ = $(SRC:.c=.o)

all: ahc

# -rdynamic: #exe blocks are dlopened libraries that resolve their
# compiler-API symbols (src/exe.c) against the ahc binary itself.
ahc: $(OBJ) src/embed.o
	$(CC) $(CFLAGS) $(LDFLAGS) -rdynamic -o $@ $(OBJ) src/embed.o -ldl

$(OBJ): src/ahc.h

# embedded runtime + prelude sources
src/embed.c: tools/file2c runtime/rt.c runtime/rt.js runtime/prelude.hc runtime/exe.hc
	./tools/file2c rt_c_src runtime/rt.c > $@
	./tools/file2c rt_js_src runtime/rt.js >> $@
	./tools/file2c prelude_hc runtime/prelude.hc >> $@
	./tools/file2c exe_hc runtime/exe.hc >> $@

tools/file2c: tools/file2c.c
	$(CC) -O2 -o $@ tools/file2c.c

test: ahc
	sh tests/run.sh

# normalize all HolyC sources in the repo (doc/format.md)
fmt: ahc
	./ahc fmt -w examples/*.HC tests/*.HC runtime/*.hc

clean:
	rm -f ahc $(OBJ) src/embed.o src/embed.c tools/file2c
	rm -rf tests/out

install: ahc
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp ahc $(DESTDIR)$(PREFIX)/bin/ahc

symstall: ahc
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	rm -f $(DESTDIR)$(PREFIX)/bin/ahc
	ln -fs $(CWD)/ahc $(DESTDIR)$(PREFIX)/bin/ahc

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/ahc

.PHONY: all test clean install uninstall
