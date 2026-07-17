#!/bin/sh
# mhc test harness: build + run every example on every available backend
# and compare against tests/expected/*.out
cd "$(dirname "$0")/.." || exit 1
mkdir -p tests/out
fail=0
backends="c"
command -v clang >/dev/null 2>&1 && backends="$backends llvm"
command -v node >/dev/null 2>&1 && backends="$backends js"
echo "testing backends: $backends"
for b in $backends; do
	for f in examples/*.HC; do
		n=$(basename "$f" .HC)
		exp="tests/expected/$n.out"
		[ -f "$exp" ] || continue
		if ! ./mhc -b "$b" -o "tests/out/$n-$b" "$f" 2>"tests/out/$n-$b.err"; then
			echo "FAIL build $b/$n"
			head -5 "tests/out/$n-$b.err"
			fail=1
			continue
		fi
		"./tests/out/$n-$b" >"tests/out/$n-$b.txt" 2>&1
		if cmp -s "$exp" "tests/out/$n-$b.txt"; then
			echo "ok   $b/$n"
		else
			echo "FAIL $b/$n"
			diff "$exp" "tests/out/$n-$b.txt" | head -10
			fail=1
		fi
	done
done
# separate compilation: -c objects + link, with public/extern symbols
for b in $backends; do
	[ "$b" = js ] && continue
	if ./mhc -c -b "$b" tests/mod_a.HC -o "tests/out/mod_a-$b.o" 2>"tests/out/mod-$b.err" &&
	   ./mhc -c -b "$b" tests/mod_b.HC -o "tests/out/mod_b-$b.o" 2>>"tests/out/mod-$b.err" &&
	   ./mhc -b "$b" "tests/out/mod_a-$b.o" "tests/out/mod_b-$b.o" -o "tests/out/mod-$b" 2>>"tests/out/mod-$b.err"; then
		"./tests/out/mod-$b" >"tests/out/mod-$b.txt" 2>&1
		if [ "$(cat "tests/out/mod-$b.txt")" = "twice(5)=10" ]; then
			echo "ok   $b/modules(-c)"
		else
			echo "FAIL $b/modules(-c) output"
			cat "tests/out/mod-$b.txt"
			fail=1
		fi
	else
		echo "FAIL build $b/modules(-c)"
		head -5 "tests/out/mod-$b.err"
		fail=1
	fi
done

# linking against a C library with -L/-l
cc -c tests/clib.c -o tests/out/clib.o 2>/dev/null &&
	ar rcs tests/out/libhctest.a tests/out/clib.o 2>/dev/null
if [ -f tests/out/libhctest.a ]; then
	for b in $backends; do
		[ "$b" = js ] && continue
		if ./mhc -b "$b" tests/uselib.HC -L tests/out -lhctest \
			-o "tests/out/uselib-$b" 2>"tests/out/uselib-$b.err"; then
			"./tests/out/uselib-$b" >"tests/out/uselib-$b.txt" 2>&1
			if [ "$(cat "tests/out/uselib-$b.txt")" = "quad(7)=28" ]; then
				echo "ok   $b/clib(-L/-l)"
			else
				echo "FAIL $b/clib(-L/-l) output"
				cat "tests/out/uselib-$b.txt"
				fail=1
			fi
		else
			echo "FAIL build $b/clib(-L/-l)"
			head -5 "tests/out/uselib-$b.err"
			fail=1
		fi
	done
fi

# Native runtime exception state is TLS.  Synchronizing inside both try and
# catch makes a shared Fs or handler stack fail deterministically.
if cc -pthread -c tests/tls_threads.c -o tests/out/tls_threads.o 2>/dev/null; then
	for b in $backends; do
		[ "$b" = js ] && continue
		if ./mhc -b "$b" tests/tls_threads.HC tests/out/tls_threads.o -lpthread \
			-o "tests/out/tls_threads-$b" 2>"tests/out/tls_threads-$b.err"; then
			"tests/out/tls_threads-$b" >"tests/out/tls_threads-$b.txt" 2>&1
			if [ "$(cat "tests/out/tls_threads-$b.txt")" = "tls exceptions: 1" ]; then
				echo "ok   $b/exceptions(TLS)"
			else
				echo "FAIL $b/exceptions(TLS) output"
				cat "tests/out/tls_threads-$b.txt"
				fail=1
			fi
		else
			echo "FAIL build $b/exceptions(TLS)"
			head -5 "tests/out/tls_threads-$b.err"
			fail=1
		fi
	done
fi

if [ "$fail" = 0 ]; then
	echo "all tests passed"
fi
exit $fail
