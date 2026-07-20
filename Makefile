# aholyc - another Holy-C compiler. Zero external dependencies: only cc + make.
CC ?= cc
AR ?= ar
CFLAGS ?= -Os -Wall -Wextra -std=gnu99
LDFLAGS ?=
PREFIX ?= /usr/local
DESTDIR ?=
CWD=$(shell pwd)

LIBSRC = src/main.c src/getopt.c src/lex.c src/parse.c src/util.c src/sb.c src/exe.c src/fmt.c \
      src/back_c.c src/back_ll.c src/back_js.c
LIBOBJ = $(LIBSRC:.c=.o) src/embed.o
OBJ = src/cli.o $(LIBOBJ)

all: aholyc

aholyc: src/cli.o libaholyc.a
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ src/cli.o libaholyc.a -ldl

libaholyc.a: $(LIBOBJ)
	$(AR) rcs $@ $(LIBOBJ)

$(OBJ): src/aholyc.h
src/main.o src/getopt.o: src/getopt.h

# embedded runtime + prelude sources
src/embed.c: tools/file2c runtime/rt.c runtime/rt.js runtime/prelude.hc runtime/exe.hc
	./tools/file2c aholyc_i_rt_c_src runtime/rt.c > $@
	./tools/file2c aholyc_i_rt_js_src runtime/rt.js >> $@
	./tools/file2c aholyc_i_prelude_hc runtime/prelude.hc >> $@
	./tools/file2c aholyc_i_exe_hc runtime/exe.hc >> $@

tools/file2c: tools/file2c.c
	$(CC) -O2 -o $@ tools/file2c.c

tests/lib_instances: tests/lib_instances.c libaholyc.a include/aholyc.h
	$(CC) $(CFLAGS) -Iinclude -o $@ tests/lib_instances.c libaholyc.a -ldl -pthread

test: aholyc tests/lib_instances
	sh tests/run.sh
	./tests/lib_instances

# normalize all HolyC sources in the repo (doc/format.md)
fmt: aholyc
	./aholyc fmt -w examples/*.HC tests/*.HC runtime/*.hc

clean:
	rm -f aholyc libaholyc.a tests/lib_instances $(OBJ) src/embed.c tools/file2c
	rm -rf tests/out

install: aholyc libaholyc.a
	mkdir -p $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/include $(DESTDIR)$(PREFIX)/lib
	cp aholyc $(DESTDIR)$(PREFIX)/bin/aholyc
	cp include/aholyc.h $(DESTDIR)$(PREFIX)/include/aholyc.h
	cp libaholyc.a $(DESTDIR)$(PREFIX)/lib/libaholyc.a

symstall: aholyc
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	rm -f $(DESTDIR)$(PREFIX)/bin/aholyc
	ln -fs $(CWD)/aholyc $(DESTDIR)$(PREFIX)/bin/aholyc

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/aholyc $(DESTDIR)$(PREFIX)/include/aholyc.h \
		$(DESTDIR)$(PREFIX)/lib/libaholyc.a

.PHONY: all test clean install uninstall
