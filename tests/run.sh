#!/bin/sh
# aholyc test harness: build + run every example on every available backend
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
		if ! ./aholyc -b "$b" -o "tests/out/$n-$b" "$f" 2>"tests/out/$n-$b.err"; then
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

# AOT process arguments: the synthetic top-level entry receives only the user
# arguments (not the executable name), then explicitly forwards argc/argv to
# Main.  Exercise direct binaries and the compiler driver's `-r --` path; the
# empty argument verifies that the vector is forwarded without shell-like
# reparsing.  VarCount in the fixture also guards the ordinary variadic pair.
for b in $backends; do
	argsok=1
	if ./aholyc -b "$b" tests/args.HC -o "tests/out/args-$b" \
		2>"tests/out/args-$b.err"; then
		"tests/out/args-$b" alpha "two words" "" -x not-source.HC \
			>"tests/out/args-$b.txt" 2>&1 || argsok=0
		cmp -s tests/expected/args.out "tests/out/args-$b.txt" || argsok=0
		"tests/out/args-$b" >"tests/out/args-none-$b.txt" 2>&1 || argsok=0
		cmp -s tests/expected/args-none.out "tests/out/args-none-$b.txt" || argsok=0
	else
		argsok=0
	fi
	./aholyc -b "$b" -r tests/args.HC -o "tests/out/args-run-bin-$b" -- \
		alpha "two words" "" -x not-source.HC \
		>"tests/out/args-run-$b.txt" 2>"tests/out/args-run-$b.err" || argsok=0
	cmp -s tests/expected/args.out "tests/out/args-run-$b.txt" || argsok=0
	./aholyc -b "$b" -r tests/args.HC -o "tests/out/args-run-bin-$b" -- \
		>"tests/out/args-run-none-$b.txt" 2>"tests/out/args-run-none-$b.err" || argsok=0
	cmp -s tests/expected/args-none.out "tests/out/args-run-none-$b.txt" || argsok=0
	if [ "$argsok" = 1 ]; then
		echo "ok   $b/process-args"
	else
		echo "FAIL $b/process-args"
		head -5 "tests/out/args-$b.err" 2>/dev/null
		diff tests/expected/args.out "tests/out/args-$b.txt" 2>/dev/null | head -10
		diff tests/expected/args-none.out "tests/out/args-none-$b.txt" 2>/dev/null | head -10
		head -5 "tests/out/args-run-$b.err" 2>/dev/null
		diff tests/expected/args.out "tests/out/args-run-$b.txt" 2>/dev/null | head -10
		diff tests/expected/args-none.out "tests/out/args-run-none-$b.txt" 2>/dev/null | head -10
		fail=1
	fi
done

# argc/argv are parameters of the synthetic startup function, not globals
# captured by every user function.  Referencing one without forwarding it is
# therefore a compile error.
if ./aholyc -S -b c tests/args_scope.HC -o tests/out/args-scope.c \
	>"tests/out/args-scope.txt" 2>"tests/out/args-scope.err"; then
	echo "FAIL process-args(scope leak)"
	fail=1
elif grep -q "undefined symbol 'argc'" tests/out/args-scope.err; then
	echo "ok   process-args(scope)"
else
	echo "FAIL process-args(scope error)"
	head -5 tests/out/args-scope.err
	fail=1
fi

# Hosted exit status: top-level return is the normal path; Exit(code) remains
# an immediate escape that works from any call depth.  The driver's -r status
# must be the program status rather than merely the compiler status.
for b in $backends; do
	statusok=1
	if ./aholyc -b "$b" tests/exit_status.HC -o "tests/out/exit-status-$b" \
		2>"tests/out/exit-status-$b.err"; then
		"tests/out/exit-status-$b" >/dev/null 2>&1
		[ "$?" = 37 ] || statusok=0
		"tests/out/exit-status-$b" now >/dev/null 2>&1
		[ "$?" = 23 ] || statusok=0
	else
		statusok=0
	fi
	./aholyc -b "$b" -r tests/exit_status.HC \
		>"tests/out/exit-status-run-$b.txt" 2>"tests/out/exit-status-run-$b.err"
	[ "$?" = 37 ] || statusok=0
	if [ "$statusok" = 1 ]; then
		echo "ok   $b/exit-status"
	else
		echo "FAIL $b/exit-status"
		head -5 "tests/out/exit-status-$b.err" 2>/dev/null
		head -5 "tests/out/exit-status-run-$b.err" 2>/dev/null
		fail=1
	fi
done

# -r cannot execute modes that stop at source or object output.
runmodeok=1
./aholyc -b c -r -S tests/exit_status.HC -o tests/out/no-run.c \
	>/dev/null 2>&1 && runmodeok=0
./aholyc -b c -r -c tests/exit_status.HC -o tests/out/no-run.o \
	>/dev/null 2>&1 && runmodeok=0
if [ "$runmodeok" = 1 ]; then
	echo "ok   run-mode validation"
else
	echo "FAIL run-mode validation"
	fail=1
fi

# separate compilation: -c objects + link, with public/extern symbols
for b in $backends; do
	[ "$b" = js ] && continue
	if ./aholyc -c -b "$b" tests/mod_a.HC -o "tests/out/mod_a-$b.o" 2>"tests/out/mod-$b.err" &&
	   ./aholyc -c -b "$b" tests/mod_b.HC -o "tests/out/mod_b-$b.o" 2>>"tests/out/mod-$b.err" &&
	   ./aholyc -b "$b" "tests/out/mod_a-$b.o" "tests/out/mod_b-$b.o" -o "tests/out/mod-$b" 2>>"tests/out/mod-$b.err"; then
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

	# A source group linked with a module remains the executable entry (not
	# another constructor), so it must receive the real process arguments.
	mixok=1
	./aholyc -b "$b" tests/args.HC "tests/out/mod_a-$b.o" \
		-o "tests/out/args-mixed-$b" 2>"tests/out/args-mixed-$b.err" || mixok=0
	"tests/out/args-mixed-$b" alpha "two words" "" -x not-source.HC \
		>"tests/out/args-mixed-$b.txt" 2>&1 || mixok=0
	cmp -s tests/expected/args.out "tests/out/args-mixed-$b.txt" || mixok=0
	if [ "$mixok" = 1 ]; then
		echo "ok   $b/source+object(args)"
	else
		echo "FAIL $b/source+object(args)"
		head -5 "tests/out/args-mixed-$b.err" 2>/dev/null
		fail=1
	fi

	# #exe uses an isolated synthetic startup while the outer compilation is
	# in constructor mode.  This catches mode restoration/signature regressions.
	if ./aholyc -c -b "$b" examples/exe.HC -o "tests/out/exe-module-$b.o" \
		2>"tests/out/exe-module-$b.err"; then
		echo "ok   $b/#exe(-c)"
	else
		echo "FAIL $b/#exe(-c)"
		head -5 "tests/out/exe-module-$b.err"
		fail=1
	fi
done

# linking against a C library with -L/-l
cc -c tests/clib.c -o tests/out/clib.o 2>/dev/null &&
	ar rcs tests/out/libhctest.a tests/out/clib.o 2>/dev/null
if [ -f tests/out/libhctest.a ]; then
	for b in $backends; do
		[ "$b" = js ] && continue
		if ./aholyc -b "$b" tests/uselib.HC -L tests/out -lhctest \
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
		if ./aholyc -b "$b" tests/tls_threads.HC tests/out/tls_threads.o -lpthread \
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

# stdin as a source: aholyc -r - < prog.HC builds a scratch ./.a.out, runs it,
# and removes it — nothing is left behind in the working directory
printf '%s\n' '"stdin ok\n";' > tests/out/stdin.HC
rm -rf tests/out/stdin.d
mkdir -p tests/out/stdin.d
for b in $backends; do
	out=$(cd tests/out/stdin.d && ../../../aholyc -b "$b" -r - < ../stdin.HC 2>"../stdin-$b.err")
	if [ "$out" = "stdin ok" ] && [ -z "$(ls -A tests/out/stdin.d)" ]; then
		echo "ok   $b/stdin(-r)"
	else
		echo "FAIL $b/stdin(-r)"
		head -5 "tests/out/stdin-$b.err"
		fail=1
	fi
done
stdinok=1
# explicit '-' input and -S -o -: backend source artifact on stdout
./aholyc -S -b c -o - - < tests/out/stdin.HC 2>/dev/null | grep -q __hc_start || stdinok=0
# No input argument is a usage error, even when stdin has data.
echo '"x";' | (cd tests/out/stdin.d && ../../../aholyc) >/dev/null 2>&1 && stdinok=0
[ -z "$(ls -A tests/out/stdin.d)" ] || stdinok=0
# -o - only means stdout with -S
echo '"x";' | ./aholyc -o - - >/dev/null 2>&1 && stdinok=0
if [ "$stdinok" = 1 ]; then
	echo "ok   stdin(edge cases)"
else
	echo "FAIL stdin(edge cases)"
	fail=1
fi

# formatter: idempotent, whitespace-only, and semantics-preserving
fmtok=1
printf 'U0 F(I64 x) {//c\nif (x) {\n"y\\n";\n}\n}\n' > tests/out/fmt_in.HC
printf 'U0 F(I64 x)\n{//c\n  if (x) {\n    "y\\n";\n  }\n}\n' > tests/out/fmt_exp.HC
./aholyc fmt tests/out/fmt_in.HC > tests/out/fmt_got.HC 2>/dev/null
cmp -s tests/out/fmt_exp.HC tests/out/fmt_got.HC || fmtok=0
./aholyc fmt -q tests/out/fmt_in.HC >/dev/null && fmtok=0   # must exit 1
./aholyc fmt -q - < tests/out/fmt_got.HC || fmtok=0         # must exit 0
for f in examples/*.HC; do
	n=$(basename "$f" .HC)
	./aholyc fmt "$f" > "tests/out/fmt-$n.HC" || { fmtok=0; continue; }
	./aholyc fmt - < "tests/out/fmt-$n.HC" | cmp -s - "tests/out/fmt-$n.HC" || fmtok=0
	[ -f "tests/expected/$n.out" ] || continue
	if ./aholyc -b c "tests/out/fmt-$n.HC" -o "tests/out/fmt-$n" 2>/dev/null; then
		"./tests/out/fmt-$n" >"tests/out/fmt-$n.txt" 2>&1
		cmp -s "tests/expected/$n.out" "tests/out/fmt-$n.txt" || fmtok=0
	else
		fmtok=0
	fi
done
if [ "$fmtok" = 1 ]; then
	echo "ok   fmt"
else
	echo "FAIL fmt"
	fail=1
fi

if [ "$fail" = 0 ]; then
	echo "all tests passed"
fi
exit $fail
