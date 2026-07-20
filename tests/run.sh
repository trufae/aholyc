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
# Main.  Exercise direct binaries and the compiler driver's `run` argv path; the
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
	./aholyc run -b "$b" -o "tests/out/args-run-bin-$b" tests/args.HC \
		alpha "two words" "" -x not-source.HC \
		>"tests/out/args-run-$b.txt" 2>"tests/out/args-run-$b.err" || argsok=0
	cmp -s tests/expected/args.out "tests/out/args-run-$b.txt" || argsok=0
	./aholyc run -b "$b" -o "tests/out/args-run-bin-$b" tests/args.HC \
		>"tests/out/args-run-none-$b.txt" 2>"tests/out/args-run-none-$b.err" || argsok=0
	cmp -s tests/expected/args-none.out "tests/out/args-run-none-$b.txt" || argsok=0
	./aholyc run -b "$b" -o "tests/out/args-run-bin-$b" tests/args.HC -- \
		2>/dev/null | grep -q '^arg0=<--> len=2$' || argsok=0
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
# an immediate escape that works from any call depth.  The driver's run status
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
	./aholyc run -b "$b" tests/exit_status.HC \
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

# run cannot execute modes that stop at source or object output, and the old
# -r/--run option spellings are rejected.
runmodeok=1
./aholyc run -b c -S tests/exit_status.HC -o tests/out/no-run.c \
	>/dev/null 2>&1 && runmodeok=0
./aholyc run -b c -c tests/exit_status.HC -o tests/out/no-run.o \
	>/dev/null 2>&1 && runmodeok=0
./aholyc -r tests/exit_status.HC >/dev/null 2>&1 && runmodeok=0
./aholyc --run tests/exit_status.HC >/dev/null 2>&1 && runmodeok=0
./aholyc -v | grep -q '^aholyc ' || runmodeok=0
./aholyc --help >/dev/null 2>&1 && runmodeok=0
./aholyc --version >/dev/null 2>&1 && runmodeok=0
if [ "$runmodeok" = 1 ]; then
	echo "ok   run-mode validation"
else
	echo "FAIL run-mode validation"
	fail=1
fi

# Comment hints are declaration metadata: LLVM narrows at SSA boundaries, C
# uses _BitInt where storage is not observable, and JS deliberately ignores
# them.  -fno-hints must make even malformed annotations ordinary comments.
hintsok=1
./aholyc -S -b llvm tests/hints.HC -o tests/out/hints.ll 2>tests/out/hints-ll.err || hintsok=0
grep -Eq 'trunc i64 .* to i1' tests/out/hints.ll || hintsok=0
grep -Eq 'trunc i64 .* to i4' tests/out/hints.ll || hintsok=0
grep -Eq 'sext i4 .* to i64' tests/out/hints.ll || hintsok=0
grep -Eq 'zext i4 .* to i64' tests/out/hints.ll || hintsok=0
grep -Eq '@g[0-9]+_global_bit = internal global i8 0' tests/out/hints.ll || hintsok=0
grep -Eq 'define internal i64 @hc_InlineAdd\(.*\) alwaysinline \{' tests/out/hints.ll || hintsok=0
grep -Eq 'define internal i64 @hc_NoInlineAdd\(.*\) noinline \{' tests/out/hints.ll || hintsok=0

./aholyc -S -b c tests/hints.HC -o tests/out/hints.c 2>tests/out/hints-c.err || hintsok=0
grep -Eq 'signed _BitInt\(4\) l[0-9]+_signed_nibble = 0' tests/out/hints.c || hintsok=0
grep -Eq 'unsigned _BitInt\(4\) l[0-9]+_unsigned_nibble = 0' tests/out/hints.c || hintsok=0
grep -Eq 'unsigned _BitInt\(1\) l[0-9]+_macro_bit = 0' tests/out/hints.c || hintsok=0
grep -Eq 'uint8_t l[0-9]+_addressed = 0' tests/out/hints.c || hintsok=0
grep -Eq 'unsigned _BitInt\(1\)' tests/out/hints.c || hintsok=0
grep -Eq 'int8_t l[0-9]+_signed_bit = 0' tests/out/hints.c || hintsok=0
grep -Eq '(^|[^[:alnum:]_])signed _BitInt\(1\)' tests/out/hints.c && hintsok=0
grep -Eq 'static inline hc_i64 hc_InlineAdd\(' tests/out/hints.c || hintsok=0
grep -Eq 'static __attribute__\(\(noinline\)\) hc_i64 hc_NoInlineAdd\(' tests/out/hints.c || hintsok=0

./aholyc -fno-hints -S -b llvm tests/hints.HC -o tests/out/hints-no.ll \
	2>tests/out/hints-no-ll.err || hintsok=0
grep -Eq 'trunc i64 .* to i(1|3|4)' tests/out/hints-no.ll && hintsok=0
grep -Eq '(alwaysinline|noinline)' tests/out/hints-no.ll && hintsok=0
./aholyc -fno-hints -S -b c tests/hints.HC -o tests/out/hints-no.c \
	2>tests/out/hints-no-c.err || hintsok=0
grep -q '_BitInt' tests/out/hints-no.c && hintsok=0
grep -Eq '(static inline hc_i64 hc_InlineAdd|noinline.*hc_NoInlineAdd)' tests/out/hints-no.c && hintsok=0
./aholyc -S -b js tests/hints.HC -o tests/out/hints.js 2>tests/out/hints-js.err || hintsok=0
./aholyc -fno-hints -S -b js tests/hints.HC -o tests/out/hints-no.js \
	2>tests/out/hints-no-js.err || hintsok=0
cmp -s tests/out/hints.js tests/out/hints-no.js || hintsok=0

./aholyc -S -b llvm tests/align.HC -o tests/out/align.ll || hintsok=0
grep -Eq 'alloca i64, align 8' tests/out/align.ll || hintsok=0
./aholyc -S -b c tests/align.HC -o tests/out/align.c || hintsok=0
grep -Eq '_Alignas\(8\) hc_i64 .*_b' tests/out/align.c || hintsok=0
grep -Eq '_Alignas\(16\) hc_i64 .*_wide' tests/out/align.c || hintsok=0
grep -Eq 'alloca i64, align 16' tests/out/align.ll || hintsok=0

for a in 3 c natural; do
	printf '/* @align=%s */ class Bad { I64 x; };\n' "$a" > tests/out/align-invalid.HC
	./aholyc -S -b c tests/out/align-invalid.HC -o tests/out/align-invalid.c \
		>/dev/null 2>&1 && hintsok=0
done
./aholyc -fno-hints -S -b c tests/out/align-invalid.HC \
	-o tests/out/align-invalid-disabled.c >/dev/null 2>&1 || hintsok=0

for b in $backends; do
	exp=tests/expected/align.out
	[ "$b" = js ] && exp=tests/expected/align-no.out
	./aholyc -b "$b" tests/align.HC -o "tests/out/align-$b" || hintsok=0
	"tests/out/align-$b" >"tests/out/align-$b.txt" || hintsok=0
	cmp -s "$exp" "tests/out/align-$b.txt" || hintsok=0
	./aholyc -fno-hints -b "$b" tests/align.HC -o "tests/out/align-no-$b" || hintsok=0
	"tests/out/align-no-$b" >"tests/out/align-no-$b.txt" || hintsok=0
	cmp -s tests/expected/align-no.out "tests/out/align-no-$b.txt" || hintsok=0
done

for b in $backends; do
	exp=tests/expected/hints.out
	[ "$b" = js ] && exp=tests/expected/hints-no.out
	./aholyc -b "$b" tests/hints.HC -o "tests/out/hints-$b" \
		2>"tests/out/hints-$b.err" || { hintsok=0; continue; }
	"tests/out/hints-$b" >"tests/out/hints-$b.txt" 2>&1 || hintsok=0
	cmp -s "$exp" "tests/out/hints-$b.txt" || hintsok=0
	./aholyc -fno-hints -b "$b" tests/hints.HC -o "tests/out/hints-no-$b" \
		2>"tests/out/hints-no-$b.err" || { hintsok=0; continue; }
	"tests/out/hints-no-$b" >"tests/out/hints-no-$b.txt" 2>&1 || hintsok=0
	cmp -s tests/expected/hints-no.out "tests/out/hints-no-$b.txt" || hintsok=0
done

printf '%s\n' '/* @bits=0 */ U8 bad;' > tests/out/hints-invalid.HC
./aholyc -S -b c tests/out/hints-invalid.HC -o tests/out/hints-invalid.c \
	>/dev/null 2>&1 && hintsok=0
./aholyc -fno-hints -S -b c tests/out/hints-invalid.HC \
	-o tests/out/hints-invalid-disabled.c >/dev/null 2>&1 || hintsok=0
printf '%s\n' '/* @bits=9 */ U8 bad;' > tests/out/hints-wide.HC
./aholyc -S -b c tests/out/hints-wide.HC -o tests/out/hints-wide.c \
	>/dev/null 2>&1 && hintsok=0
printf '%s\n' '/* @bits=129 */ U64 bad;' > tests/out/hints-over-max.HC
./aholyc -S -b c tests/out/hints-over-max.HC -o tests/out/hints-over-max.c \
	>/dev/null 2>&1 && hintsok=0
printf '%s\n' '/* @bits=4 */ F64 bad;' > tests/out/hints-float.HC
./aholyc -S -b c tests/out/hints-float.HC -o tests/out/hints-float.c \
	>/dev/null 2>&1 && hintsok=0

printf '%s\n' '#define N /* @bits=3 */ U8' '/* @bits=4 */ N duplicate;' \
	> tests/out/hints-macro-duplicate.HC
./aholyc -S -b c tests/out/hints-macro-duplicate.HC \
	-o tests/out/hints-macro-duplicate.c >/dev/null 2>&1 && hintsok=0
printf '%s\n' 'DECL' > tests/out/hints-define.HC
./aholyc '-DDECL=/* @bits=0 */ U8 defined;' -fno-hints -S -b c \
	tests/out/hints-define.HC -o tests/out/hints-define-a.c >/dev/null 2>&1 || hintsok=0
./aholyc -fno-hints '-DDECL=/* @bits=0 */ U8 defined;' -S -b c \
	tests/out/hints-define.HC -o tests/out/hints-define-b.c >/dev/null 2>&1 || hintsok=0
./aholyc '-DDECL=/* @bits=0 */ U8 defined;' -S -b c \
	tests/out/hints-define.HC -o tests/out/hints-define-bad.c >/dev/null 2>&1 && hintsok=0
./aholyc -h | grep -q -- '-fno-hints' || hintsok=0

if [ "$hintsok" = 1 ]; then
	echo "ok   source hints"
else
	echo "FAIL source hints"
	head -5 tests/out/hints-ll.err 2>/dev/null
	head -5 tests/out/hints-c.err 2>/dev/null
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

	# A program built through -c has no distinguished source at final link.
	# Its registered module startup still receives argv and supplies status.
	objargsok=1
	./aholyc -c -b "$b" tests/args.HC -o "tests/out/args-object-$b.o" \
		2>"tests/out/args-object-$b.err" || objargsok=0
	./aholyc -b "$b" "tests/out/args-object-$b.o" \
		-o "tests/out/args-object-$b" 2>>"tests/out/args-object-$b.err" || objargsok=0
	"tests/out/args-object-$b" alpha "two words" "" -x not-source.HC \
		>"tests/out/args-object-$b.txt" 2>&1 || objargsok=0
	cmp -s tests/expected/args.out "tests/out/args-object-$b.txt" || objargsok=0
	./aholyc -c -b "$b" tests/exit_status.HC -o "tests/out/status-object-$b.o" \
		2>"tests/out/status-object-$b.err" || objargsok=0
	./aholyc -b "$b" "tests/out/status-object-$b.o" \
		-o "tests/out/status-object-$b" 2>>"tests/out/status-object-$b.err" || objargsok=0
	"tests/out/status-object-$b" >/dev/null 2>&1
	[ "$?" = 37 ] || objargsok=0
	"tests/out/status-object-$b" now >/dev/null 2>&1
	[ "$?" = 23 ] || objargsok=0
	if [ "$objargsok" = 1 ]; then
		echo "ok   $b/object-program(args/status)"
	else
		echo "FAIL $b/object-program(args/status)"
		head -5 "tests/out/args-object-$b.err" 2>/dev/null
		head -5 "tests/out/status-object-$b.err" 2>/dev/null
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

# stdin as a source: aholyc run - < prog.HC builds a scratch ./.a.out, runs it,
# and removes it — nothing is left behind in the working directory
printf '%s\n' '"stdin ok\n";' > tests/out/stdin.HC
rm -rf tests/out/stdin.d
mkdir -p tests/out/stdin.d
for b in $backends; do
	out=$(cd tests/out/stdin.d && ../../../aholyc run -b "$b" - < ../stdin.HC 2>"../stdin-$b.err")
	if [ "$out" = "stdin ok" ] && [ -z "$(ls -A tests/out/stdin.d)" ]; then
		echo "ok   $b/stdin(run)"
	else
		echo "FAIL $b/stdin(run)"
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
