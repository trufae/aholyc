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
		if ! ./aholyc -b "$b" -o "tests/out/$n-$b" "$f" \
			>"tests/out/$n-$b.build" 2>"tests/out/$n-$b.err"; then
			echo "FAIL build $b/$n"
			head -5 "tests/out/$n-$b.err"
			fail=1
			continue
		fi
		if [ "$n" = exe_symbols ] && [ -s "tests/out/$n-$b.build" ]; then
			echo "FAIL build $b/$n replayed outer startup"
			head -5 "tests/out/$n-$b.build"
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

# Native assembly: a top-level block defines a callable symbol, while an
# @inline function exercises local operands and block-local @@ labels.
asmok=1
case $(uname -m) in
	x86_64|amd64|arm64|aarch64|riscv64*|mips64*|s390x*) haveasm=1 ;;
	*) haveasm=0 ;;
esac
if [ "$haveasm" = 1 ]; then
	for b in $backends; do
		[ "$b" = js ] && continue
		if ./aholyc -b "$b" tests/asm.HC -o "tests/out/asm-$b" \
			2>"tests/out/asm-$b.err" &&
		   "tests/out/asm-$b" >"tests/out/asm-$b.txt" 2>&1 &&
		   cmp -s tests/expected/asm.out "tests/out/asm-$b.txt"; then
			echo "ok   $b/asm"
		else
			echo "FAIL $b/asm"
			head -5 "tests/out/asm-$b.err" 2>/dev/null
			asmok=0
		fi
		if ./aholyc -b "$b" examples/asm/data_directives.HC \
			-o "tests/out/asm-data-$b" 2>"tests/out/asm-data-$b.err" &&
		   "tests/out/asm-data-$b" >"tests/out/asm-data-$b.txt" 2>&1 &&
		   grep -qx 'assembly data directives built' \
			"tests/out/asm-data-$b.txt"; then
			echo "ok   $b/asm-data"
		else
			echo "FAIL $b/asm-data"
			head -5 "tests/out/asm-data-$b.err" 2>/dev/null
			asmok=0
		fi
	done
	if ! ./aholyc -S -b c tests/asm.HC -o tests/out/asm-inline.c ||
	   ! grep -Eq 'static inline __attribute__\(\(always_inline\)\) hc_i64 hc_ExerciseInlineAsm' \
		tests/out/asm-inline.c; then
		echo "FAIL c/asm-inline-hint"
		asmok=0
	fi
	case " $backends " in
		*" llvm "*)
			if ! ./aholyc -S -b llvm tests/asm.HC -o tests/out/asm-inline.ll ||
			   ! grep -Eq 'define .*hc_ExerciseInlineAsm.*alwaysinline' \
				tests/out/asm-inline.ll; then
				echo "FAIL llvm/asm-inline-hint"
				asmok=0
			fi
			;;
	esac
	if ! ./aholyc -S -b c tests/asm_directives.HC \
		-o tests/out/asm-directives.c ||
	   ! grep -Fq '.extern _ASM_IMPORT_A, _ASM_IMPORT_B' tests/out/asm-directives.c ||
	   ! grep -Fq '.ascii \"AB\"' tests/out/asm-directives.c ||
	   ! grep -Fq '.fill 2, 2, 4660' tests/out/asm-directives.c ||
	   ! grep -Fq '.balign 16, 0' tests/out/asm-directives.c ||
	   ! grep -Fq '.org 64' tests/out/asm-directives.c ||
	   ! grep -Fq '.incbin \"not-read-while-emitting-source.bin\"' \
		tests/out/asm-directives.c ||
	   grep -Eq '(^|[^A-Z])(LIST|NOLIST)([^A-Z]|$)' tests/out/asm-directives.c; then
		echo "FAIL asm-directive lowering"
		asmok=0
	fi
	printf '%s\n' 'U0 F() { asm { op %r0 } }' \
		>tests/out/asm-percent.HC
	if ! ./aholyc -S -b c tests/out/asm-percent.HC \
		-o tests/out/asm-percent.c ||
	   ! grep -Fq '"op %%r0\n"' tests/out/asm-percent.c; then
		echo "FAIL asm percent-register escaping"
		asmok=0
	fi
	printf '%s\n' '/* @inline */ asm { NOP }' \
		>tests/out/asm-hint-block.HC
	if ./aholyc -S -b c tests/out/asm-hint-block.HC \
		-o tests/out/asm-hint-block.c 2>tests/out/asm-hint-block.err ||
	   ! grep -q 'inline hints apply to the enclosing function declaration' \
		tests/out/asm-hint-block.err; then
		echo "FAIL asm block hint diagnostic"
		asmok=0
	fi
	printf '%s\n' '/* @inline */ public _extern _RAW I64 Raw();' \
		>tests/out/asm-hint-extern.HC
	if ./aholyc -S -b c tests/out/asm-hint-extern.HC \
		-o tests/out/asm-hint-extern.c 2>tests/out/asm-hint-extern.err ||
	   ! grep -q 'cannot @inline an _extern assembler symbol' \
		tests/out/asm-hint-extern.err; then
		echo "FAIL asm extern hint diagnostic"
		asmok=0
	fi
	printf '%s\n' 'asm {' '  DU8 1' '}' >tests/out/asm-missing-semi.HC
	if ./aholyc -S -b c tests/out/asm-missing-semi.HC \
		-o tests/out/asm-missing-semi.c 2>tests/out/asm-missing-semi.err ||
	   ! grep -q "DU8 requires a terminating ';'" tests/out/asm-missing-semi.err; then
		echo "FAIL asm directive semicolon diagnostic"
		asmok=0
	fi
	case " $backends " in
		*" js "*)
			if ./aholyc -S -b js tests/asm.HC -o tests/out/asm.js \
				>tests/out/asm-js.txt 2>tests/out/asm-js.err; then
				asmok=0
			elif ! grep -q 'asm statements are not supported by the js backend' \
				tests/out/asm-js.err; then
				asmok=0
			fi
			;;
	esac
fi
if [ "$asmok" = 1 ]; then
	echo "ok   asm(target syntax/backends)"
else
	echo "FAIL asm(target syntax/backends)"
	fail=1
fi

# -fno-asm is a parser policy, not merely a missing backend feature. It must
# reject surviving blocks at both scopes even if HAS_ASM is forced with -D.
noasmok=1
./aholyc -h | grep -q -- '-fno-asm' || noasmok=0
printf '%s\n' 'asm { NOP };' >tests/out/asm-disabled-file.HC
if ./aholyc -S -b c -fno-asm -D HAS_ASM=1 \
	-o tests/out/asm-disabled-file.c tests/out/asm-disabled-file.HC \
	2>tests/out/asm-disabled-file.err ||
   ! grep -q 'asm blocks are disabled by -fno-asm' \
	tests/out/asm-disabled-file.err; then
	noasmok=0
fi
printf '%s\n' 'U0 F() { asm { NOP }; }' >tests/out/asm-disabled-func.HC
if ./aholyc -S -b c -fno-asm \
	-o tests/out/asm-disabled-func.c tests/out/asm-disabled-func.HC \
	2>tests/out/asm-disabled-func.err ||
   ! grep -q 'asm blocks are disabled by -fno-asm' \
	tests/out/asm-disabled-func.err; then
	noasmok=0
fi

# HAS_ASM describes the selected compilation, so native backends define it,
# JS and -fno-asm do not.
printf '%s\n' '#ifdef HAS_ASM' '"enabled\n";' '#else' '"disabled\n";' \
	'#endif' >tests/out/asm-capability.HC
for b in $backends; do
	case "$b" in
	js) asmcap=disabled ;;
	*) asmcap=enabled ;;
	esac
	if ! ./aholyc run -b "$b" tests/out/asm-capability.HC \
		>"tests/out/asm-capability-$b.txt" 2>"tests/out/asm-capability-$b.err" ||
	   ! grep -qx "$asmcap" "tests/out/asm-capability-$b.txt"; then
		noasmok=0
	fi
	if ! ./aholyc run -b "$b" -fno-asm tests/out/asm-capability.HC \
		>"tests/out/asm-capability-no-$b.txt" \
		2>"tests/out/asm-capability-no-$b.err" ||
	   ! grep -qx disabled "tests/out/asm-capability-no-$b.txt"; then
		noasmok=0
	fi
done

# Force each example's platform guards while HAS_ASM is absent. No target
# assembler is involved, so all portable branches can run on every backend.
for n in arm64_darwin arm64_linux data_directives inline_x86_64 \
	mips64_linux riscv64_linux s390x_linux x86_64_linux; do
	case "$n" in
	arm64_darwin) asmout='arm64 darwin syscall' ;;
	arm64_linux) asmout='arm64 syscall' ;;
	data_directives) asmout='assembly data directives built' ;;
	inline_x86_64) asmout='AddOneInAsm(41)=42' ;;
	mips64_linux) asmout='mips64 syscall' ;;
	riscv64_linux) asmout='riscv syscall' ;;
	s390x_linux) asmout='s390x syscall' ;;
	x86_64_linux) asmout='x86-64 syscall' ;;
	esac
	for b in $backends; do
		if ! ./aholyc -b "$b" -fno-asm \
			-D IS_X86_64 -D IS_ARM_64 -D IS_RISCV -D IS_MIPS \
			-D IS_S390 \
			-D IS_LINUX -D IS_MACOS "examples/asm/$n.HC" \
			-o "tests/out/asm-fallback-$n-$b" \
			2>"tests/out/asm-fallback-$n-$b.err" ||
		   ! "tests/out/asm-fallback-$n-$b" \
			>"tests/out/asm-fallback-$n-$b.txt" 2>&1 ||
		   ! grep -qx "$asmout" "tests/out/asm-fallback-$n-$b.txt"; then
			noasmok=0
		fi
	done
done
if [ "$noasmok" = 1 ]; then
	echo "ok   asm(disabled/capability/fallbacks)"
else
	echo "FAIL asm(disabled/capability/fallbacks)"
	fail=1
fi

# -fno-pic reaches every native compiler invocation. Executable builds also
# disable PIE linking, while -c only selects non-PIC code generation.
nopicok=1
./aholyc -h | grep -q -- '-fno-pic' || nopicok=0
printf '%s\n' '"nopic\n";' >tests/out/nopic.HC
case $(uname -s) in
Darwin) piccode=' -mdynamic-no-pic'; pielink=' -Wl,-no_pie' ;;
*) piccode=' -fno-pic'; pielink=' -no-pie' ;;
esac
for b in $backends; do
	[ "$b" = js ] && continue
	if ! ./aholyc -V -fno-pic -b "$b" tests/out/nopic.HC \
		-o "tests/out/nopic-$b" 2>"tests/out/nopic-$b.err" ||
	   [ "$("tests/out/nopic-$b" 2>&1)" != nopic ] ||
	   ! grep -q -- "$piccode " "tests/out/nopic-$b.err" ||
	   ! grep -q -- "$pielink" "tests/out/nopic-$b.err"; then
		nopicok=0
	fi
done
if ! ./aholyc -V -fno-pic -b c -c tests/out/nopic.HC \
	-o tests/out/nopic.o 2>tests/out/nopic-obj.err ||
   ! grep -q -- "$piccode" tests/out/nopic-obj.err; then
	nopicok=0
fi
if grep -q -- ' -no-pie' tests/out/nopic-obj.err ||
   grep -q -- ' -Wl,-no_pie' tests/out/nopic-obj.err; then
	nopicok=0
fi
if [ "$nopicok" = 1 ]; then
	echo "ok   native code(no-pic/no-pie)"
else
	echo "FAIL native code(no-pic/no-pie)"
	fail=1
fi

# The command-line disable must reach native source and runtime compilation
# after environment flags, so it can override hardened CFLAGS explicitly.
stackprotok=1
./aholyc -h | grep -q -- '-fno-stack-protector' || stackprotok=0
for b in $backends; do
	[ "$b" = js ] && continue
	if ! CFLAGS=-fstack-protector-all ./aholyc -V -fno-stack-protector \
		-b "$b" tests/out/nopic.HC -o "tests/out/no-stack-$b" \
		2>"tests/out/no-stack-$b.err" ||
	   [ "$("tests/out/no-stack-$b" 2>&1)" != nopic ] ||
	   ! grep -q -- '-fstack-protector-all.*-fno-stack-protector' \
		"tests/out/no-stack-$b.err"; then
		stackprotok=0
	fi
done
if [ "$stackprotok" = 1 ]; then
	echo "ok   native code(no-stack-protector)"
else
	echo "FAIL native code(no-stack-protector)"
	fail=1
fi

# -shared uses the native object path, exports public symbols, and runs the
# HolyC top-level initializer when the library is loaded.
sharedok=1
./aholyc -h | grep -q -- '-shared' || sharedok=0
case $(uname -s) in
Darwin) sharedext=dylib; sharedgc=' -Wl,-dead_strip' ;;
*) sharedext=so; sharedgc=' -Wl,--gc-sections' ;;
esac
if ! cc tests/shared_client.c -o tests/out/shared-client -ldl 2>/dev/null; then
	sharedok=0
fi
for b in $backends; do
	[ "$b" = js ] && continue
	lib="tests/out/libshared-$b.$sharedext"
	secondlib="tests/out/libshared-second-$b.$sharedext"
	obj="tests/out/shared-$b.o"
	objlib="tests/out/libshared-obj-$b.$sharedext"
	if ! ./aholyc -V -shared -b "$b" tests/shared.HC -o "$lib" \
		2>"tests/out/shared-$b.err" ||
	   ! grep -q -- ' -shared' "tests/out/shared-$b.err" ||
	   ! grep -q -- ' -fPIC' "tests/out/shared-$b.err" ||
	   ! grep -q -- ' -ffunction-sections' "tests/out/shared-$b.err" ||
	   ! grep -q -- "$sharedgc" "tests/out/shared-$b.err" ||
	   [ "$(tests/out/shared-client "$(pwd)/$lib" 2>&1)" != \
		'SharedAdd(2)=42' ]; then
		sharedok=0
	fi
	if ! ./aholyc -shared -b "$b" tests/shared_second.HC -o "$secondlib" ||
	   [ "$(tests/out/shared-client "$(pwd)/$lib" \
		"$(pwd)/$secondlib" 2>&1)" != \
		"$(printf 'SharedAdd(2)=42\nSharedDouble()=42')" ]; then
		sharedok=0
	fi
	if ! ./aholyc -b "$b" -c tests/shared.HC -o "$obj" ||
	   ! ./aholyc -shared -b "$b" "$obj" -o "$objlib" ||
	   [ "$(tests/out/shared-client "$(pwd)/$objlib" 2>&1)" != \
		'SharedAdd(2)=42' ]; then
		sharedok=0
	fi
done
# A function-only module has no top-level startup and needs no constructor or
# registration helper in its emitted object.
./aholyc -S -shared -b c tests/shared_plain.HC \
	-o tests/out/shared-plain.c || sharedok=0
grep -q '__attribute__((constructor))' tests/out/shared-plain.c && sharedok=0
if echo "$backends" | grep -q llvm; then
	./aholyc -S -shared -b llvm tests/shared_plain.HC \
		-o tests/out/shared-plain.ll || sharedok=0
	grep -q '@llvm.global_ctors' tests/out/shared-plain.ll && sharedok=0
fi
./aholyc -shared -b js tests/shared.HC -o tests/out/shared.js \
	>/dev/null 2>&1 && sharedok=0
./aholyc -shared -c tests/shared.HC -o tests/out/shared.o \
	>/dev/null 2>&1 && sharedok=0
./aholyc run -shared tests/shared.HC >/dev/null 2>&1 && sharedok=0
if [ "$sharedok" = 1 ]; then
	echo "ok   native shared libraries"
else
	echo "FAIL native shared libraries"
	fail=1
fi

# -sarchive packages the native object path for a later static link.
archiveok=1
./aholyc -h | grep -q -- '-sarchive' || archiveok=0
for b in $backends; do
	[ "$b" = js ] && continue
	lib="tests/out/libarchive-$b.a"
	if ! ./aholyc -V -sarchive -b "$b" tests/shared.HC -o "$lib" \
		2>"tests/out/archive-$b.err" ||
	   ! grep -q -- ' ar rcs ' "tests/out/archive-$b.err" ||
	   ! ar t "$lib" | grep -q '\.aholyc\.o$' ||
	   ! ./aholyc -b "$b" tests/archive_use.HC "$lib" \
		-o "tests/out/archive-use-$b" ||
	   [ "$(tests/out/archive-use-$b 2>&1)" != '42' ]; then
		archiveok=0
	fi
done
./aholyc -sarchive -b js tests/shared.HC -o tests/out/archive.js \
	>/dev/null 2>&1 && archiveok=0
./aholyc -sarchive -c tests/shared.HC -o tests/out/archive.o \
	>/dev/null 2>&1 && archiveok=0
./aholyc run -sarchive tests/shared.HC >/dev/null 2>&1 && archiveok=0
if [ "$archiveok" = 1 ]; then
	echo "ok   native static archives"
else
	echo "FAIL native static archives"
	fail=1
fi

# The portable thread library targets native OS threads.  Exercise both
# native code generators; JS intentionally has no FFI/thread backend.
for b in $backends; do
	[ "$b" = js ] && continue
	if ./aholyc -b "$b" tests/thread.HC -o "tests/out/thread-$b" \
		2>"tests/out/thread-$b.err"; then
		"tests/out/thread-$b" >"tests/out/thread-$b.txt" 2>&1
		if cmp -s tests/expected/thread.out "tests/out/thread-$b.txt"; then
			echo "ok   $b/thread-library"
		else
			echo "FAIL $b/thread-library"
			diff tests/expected/thread.out "tests/out/thread-$b.txt" | head -10
			fail=1
		fi
	else
		echo "FAIL build $b/thread-library"
		head -5 "tests/out/thread-$b.err"
		fail=1
	fi
done

# Compile the same fixture against Win32 when the optional MinGW cross
# toolchain used by demos/windows is installed.
if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 &&
   [ -x demos/windows/ccwin.sh ] &&
   CC=demos/windows/ccwin.sh ./aholyc -b c -DTHREAD_WINDOWS tests/thread.HC \
	-o tests/out/thread-windows.exe 2>tests/out/thread-windows.err; then
	if command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1 &&
	   x86_64-w64-mingw32-objdump -p tests/out/thread-windows.exe |
		grep -q 'libwinpthread'; then
		echo "FAIL windows/thread-library imported libwinpthread"
		fail=1
	else
		echo "ok   windows/thread-library(cross-build)"
	fi
elif command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 &&
     [ -x demos/windows/ccwin.sh ]; then
	echo "FAIL build windows/thread-library"
	head -5 tests/out/thread-windows.err
	fail=1
fi

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

# A function-looking declaration in a block is not a malformed local
# variable: HolyC deliberately has no local functions. Diagnose the actual
# unsupported construct instead of falling through to "expected ','".
localfnok=1
if printf '%s\n' 'U0 Foo() { U0 Bar() {} }' |
	./aholyc -S -b c -o tests/out/local-function.c - \
		>/dev/null 2>tests/out/local-function.err; then
	localfnok=0
elif ! grep -Fq \
	"local functions are not allowed in HolyC; move 'Bar' to file scope" \
	tests/out/local-function.err; then
	localfnok=0
fi
if [ "$localfnok" = 1 ]; then
	echo "ok   local-function diagnostic"
else
	echo "FAIL local-function diagnostic"
	head -1 tests/out/local-function.err 2>/dev/null
	fail=1
fi

# A typed function pointer carries its full signature through globals, class
# members, nested callback parameters, and direct function designators.
fnptrsigok=1
if printf '%s\n' \
	'class Ops { I64 (*call)(I64 left, I64 right); };' \
	'Ops ops; ops.call(1);' |
	./aholyc -S -b c -o tests/out/fnptr-too-few.c - \
		>/dev/null 2>tests/out/fnptr-too-few.err; then
	fnptrsigok=0
elif ! grep -Fq 'too few arguments to function pointer (takes 2)' \
	tests/out/fnptr-too-few.err; then
	fnptrsigok=0
fi
if printf '%s\n' \
	'I64 One(I64 value) { return value; }' \
	'(&One)(1, 2);' |
	./aholyc -S -b c -o tests/out/fnptr-too-many.c - \
		>/dev/null 2>tests/out/fnptr-too-many.err; then
	fnptrsigok=0
elif ! grep -Fq 'too many arguments to function pointer (takes 1)' \
	tests/out/fnptr-too-many.err; then
	fnptrsigok=0
fi
if ! printf '%s\n' \
	'I64 (*call)(I64 fixed, ...);' \
	'call(1, 2, 3);' |
	./aholyc -S -b c -o tests/out/fnptr-variadic.c - >/dev/null 2>&1; then
	fnptrsigok=0
fi
if printf '%s\n' \
	'F64 Wrong(F64 value) { return value; }' \
	'I64 (*call)(I64 value) = &Wrong;' |
	./aholyc -S -b c -o tests/out/fnptr-incompatible.c - \
		>/dev/null 2>tests/out/fnptr-incompatible.err; then
	fnptrsigok=0
elif ! grep -Fq 'incompatible function-pointer signature' \
	tests/out/fnptr-incompatible.err; then
	fnptrsigok=0
fi
if printf '%s\n' \
	'I64 Conflict(I64 value);' \
	'I64 Conflict(F64 value) { return value; }' |
	./aholyc -S -b c -o tests/out/fnptr-conflict.c - \
		>/dev/null 2>tests/out/fnptr-conflict.err; then
	fnptrsigok=0
elif ! grep -Fq 'conflicting declaration of function Conflict' \
	tests/out/fnptr-conflict.err; then
	fnptrsigok=0
fi
if [ "$fnptrsigok" = 1 ]; then
	echo "ok   function-pointer signatures"
else
	echo "FAIL function-pointer signatures"
	head -1 tests/out/fnptr-too-few.err 2>/dev/null
	head -1 tests/out/fnptr-too-many.err 2>/dev/null
	fail=1
fi

# Primitive types, class types, and hard keywords are not legal symbol names.
# Keep the cases separate so every declaration path reaches the same early
# reserved-name validation instead of leaking a bad name into a backend.
reservedok=1
check_reserved_name() {
	label=$1
	source=$2
	expected=$3
	if printf '%s\n' "$source" |
		./aholyc -S -b c -o tests/out/reserved-name.c - \
			>/dev/null 2>tests/out/reserved-name.err; then
		echo "  accepted: $label"
		reservedok=0
	elif ! grep -Fq "$expected" tests/out/reserved-name.err; then
		echo "  wrong diagnostic: $label"
		head -1 tests/out/reserved-name.err
		reservedok=0
	fi
}
check_reserved_name "global/type" \
	'I64 I64 = 0;' "'I64' is reserved"
check_reserved_name "global/pointer-type" \
	'I64 *F64;' "'F64' is reserved"
check_reserved_name "global/keyword" \
	'I64 if = 0;' "'if' is reserved"
check_reserved_name "secondary declarator" \
	'I64 good, return;' "'return' is reserved"
check_reserved_name "function/type" \
	'I64 U64() { return 0; }' "'U64' is reserved"
check_reserved_name "parameter/keyword" \
	'I64 Good(I64 while) { return 0; }' "'while' is reserved"
check_reserved_name "local/keyword" \
	'I64 Good() { I64 public = 0; return 0; }' "'public' is reserved"
check_reserved_name "class/type" \
	'class I32 { I64 value; };' "'I32' is reserved"
check_reserved_name "member/type" \
	'class Good { I64 U8; };' "'U8' is reserved"
check_reserved_name "function-pointer/keyword" \
	'I64 (*return)(I64);' "'return' is reserved"
check_reserved_name "goto/type-label" \
	'I64 Good() { goto I16; }' "'I16' is reserved"
check_reserved_name "keyword-label" \
	'I64 Good() { return: return 0; }' "'return' is reserved"
check_reserved_name "class-name/global" \
	'class Thing { I64 value; }; I64 Thing;' \
	"'Thing' is a type name"
check_reserved_name "class-name/function" \
	'class Thing { I64 value; }; I64 Thing() { return 0; }' \
	"'Thing' is a type name"
check_reserved_name "class-name/member" \
	'class Thing { I64 value; }; class Box { I64 Thing; };' \
	"'Thing' is a type name"
check_reserved_name "macro-expanded/type" \
	'#define BAD I64
I64 BAD;' "'I64' is reserved"

# These spellings are contextual in HolyC and remain usable as ordinary names
# where their special grammar is not active.  Directives must also keep
# working now that #if/#else arrive from the lexer as keyword tokens.
printf '%s\n' \
	'I64 start = 0, end = 1, reg = 2, noreg = 3;' \
	'class Context { I64 offset; I64 reg; };' \
	'Context value;' \
	'value.offset = start + end + reg + noreg;' \
	'#if 1' 'I64 ordinary = 4;' '#else' 'I64 skipped = 5;' '#endif' \
	> tests/out/reserved-context.HC
./aholyc -S -b c tests/out/reserved-context.HC \
	-o tests/out/reserved-context.c >/dev/null 2>&1 || reservedok=0
echo 'I64 value;' |
	./aholyc -S -b c -DI64=1 -o tests/out/reserved-define.c - \
		>/dev/null 2>&1 && reservedok=0
if [ "$reservedok" = 1 ]; then
	echo "ok   reserved names"
else
	echo "FAIL reserved names"
	fail=1
fi

# -D defines: dispatch is plain #ifdef on distinct macros (no automatic
# name_value combo define), the last -D of a name wins, #undef in the source
# beats the command line, a missing name is an error, and the host platform
# macro is predefined
defok=1
printf '%s\n' '#ifdef UI_GTK4' '"gtk4\n";' '#else' '#ifdef UI_COCOA' \
	'"cocoa\n";' '#else' '"none\n";' '#endif' '#endif' \
	> tests/out/def-dispatch.HC
[ "$(./aholyc run -b c tests/out/def-dispatch.HC 2>/dev/null)" = none ] || defok=0
[ "$(./aholyc run -b c -DUI_GTK4 tests/out/def-dispatch.HC 2>/dev/null)" = gtk4 ] || defok=0
[ "$(./aholyc run -b c -DUI_COCOA tests/out/def-dispatch.HC 2>/dev/null)" = cocoa ] || defok=0
[ "$(./aholyc run -b c -DUI_BACKEND=UI_GTK4 tests/out/def-dispatch.HC 2>/dev/null)" = none ] || defok=0
printf '%s\n' '"v=%d\n", VAL;' '#ifdef VAL_7' '"combo\n";' '#endif' \
	> tests/out/def-value.HC
[ "$(./aholyc run -b c -DVAL=7 tests/out/def-value.HC 2>/dev/null)" = "v=7" ] || defok=0
printf '%s\n' '#undef FEATURE' '#ifdef FEATURE' '"feature\n";' '#else' \
	'"clean\n";' '#endif' > tests/out/def-undef.HC
[ "$(./aholyc run -b c -DFEATURE=1 tests/out/def-undef.HC 2>/dev/null)" = clean ] || defok=0
./aholyc run -b c -D=word tests/out/def-dispatch.HC >/dev/null 2>&1 && defok=0
printf '%s\n' '#ifdef IS_MACOS' '"apple\n";' '#else' '#ifdef IS_LINUX' \
	'"linux\n";' '#else' '"other\n";' '#endif' '#endif' > tests/out/def-host.HC
case "$(uname -s)" in
Darwin) host=apple ;;
Linux) host=linux ;;
*) host=other ;;
esac
[ "$(./aholyc run -b c tests/out/def-host.HC 2>/dev/null)" = "$host" ] || defok=0
printf '%s\n' '#ifdef IS_UNIX' '"unix\n";' '#else' '"other\n";' '#endif' > tests/out/def-unix.HC
case "$host" in
apple|linux) unix=unix ;;
*) unix=other ;;
esac
[ "$(./aholyc run -b c tests/out/def-unix.HC 2>/dev/null)" = "$unix" ] || defok=0
for platform in NETBSD OPENBSD FREEBSD; do
	macro_file="tests/out/def-${platform}.HC"
	printf '%s\n' "#ifdef IS_${platform}" '"yes\n";' '#else' '"no\n";' '#endif' > "$macro_file"
	case "$(uname -s)" in
	NetBSD) expected=$([ "$platform" = NETBSD ] && echo yes || echo no) ;;
	OpenBSD) expected=$([ "$platform" = OPENBSD ] && echo yes || echo no) ;;
	FreeBSD) expected=$([ "$platform" = FREEBSD ] && echo yes || echo no) ;;
	*) expected=no ;;
	esac
	[ "$(./aholyc run -b c "$macro_file" 2>/dev/null)" = "$expected" ] || defok=0
done
if [ "$defok" = 1 ]; then
	echo "ok   defines(-D)"
else
	echo "FAIL defines(-D)"
	fail=1
fi

# A #! on the physical first line is interpreter metadata, not a directive;
# the same token sequence later in the source must still be diagnosed.
hashbangok=1
printf '%s\n' '#!/usr/bin/env aholyc run' '"hashbang\n";' \
	>tests/out/hashbang.HC
[ "$(./aholyc run -b c tests/out/hashbang.HC 2>/dev/null)" = hashbang ] || \
	hashbangok=0
printf '%s\n' '"before\n";' '#!/usr/bin/env aholyc run' \
	>tests/out/hashbang-late.HC
if ./aholyc run -b c tests/out/hashbang-late.HC \
	>tests/out/hashbang-late.out 2>tests/out/hashbang-late.err ||
   ! grep -q 'invalid preprocessor directive' tests/out/hashbang-late.err; then
	hashbangok=0
fi
if [ "$hashbangok" = 1 ]; then
	echo "ok   hashbang"
else
	echo "FAIL hashbang"
	fail=1
fi

# #if constant expressions: comparisons, defined(), boolean/bitwise ops,
# macro expansion, HolyC precedence (shifts bind tighter than *), nesting,
# undefined name is 0, #else, and malformed expressions are errors
ppifok=1
printf '%s\n' '#if 2 > 1' '"a\n";' '#endif' \
	'#if 2 < 1' '"b\n";' '#else' '"c\n";' '#endif' \
	'#if defined(NOPE)' '"d\n";' '#else' '"e\n";' '#endif' \
	'#if UNSET' '"f\n";' '#else' '"g\n";' '#endif' \
	> tests/out/ppif.HC
[ "$(./aholyc run -b c tests/out/ppif.HC 2>/dev/null)" = "$(printf 'a\nc\ne\ng')" ] || ppifok=0
printf '%s\n' '#if X == 5 && X > 3' '"lo\n";' '#endif' \
	'#if X | 2 == 7' '"hi\n";' '#endif' > tests/out/ppif2.HC
[ "$(./aholyc run -b c -DX=5 tests/out/ppif2.HC 2>/dev/null)" = "$(printf 'lo\nhi')" ] || ppifok=0
# HolyC precedence: 1<<2*3 is (1<<2)*3 == 12, not 1<<(2*3) == 64
printf '%s\n' '#if 1<<2*3 == 12' '"prec\n";' '#else' '"cprec\n";' '#endif' \
	> tests/out/ppif3.HC
[ "$(./aholyc run -b c tests/out/ppif3.HC 2>/dev/null)" = prec ] || ppifok=0
# nesting + macro expansion in the condition
printf '%s\n' '#define TWO 2' '#if LVL > TWO' '#if defined(LVL)' \
	'"nest\n";' '#endif' '#endif' > tests/out/ppif4.HC
[ "$(./aholyc run -b c -DLVL=3 tests/out/ppif4.HC 2>/dev/null)" = nest ] || ppifok=0
[ -z "$(./aholyc run -b c -DLVL=1 tests/out/ppif4.HC 2>/dev/null)" ] || ppifok=0
# errors: empty expression, trailing tokens, divide by zero
printf '%s\n' '#if' '"x";' '#endif' > tests/out/ppif-bad.HC
./aholyc run -b c tests/out/ppif-bad.HC >/dev/null 2>&1 && ppifok=0
printf '%s\n' '#if 1 2' '"x";' '#endif' > tests/out/ppif-bad2.HC
./aholyc run -b c tests/out/ppif-bad2.HC >/dev/null 2>&1 && ppifok=0
printf '%s\n' '#if 1/0' '"x";' '#endif' > tests/out/ppif-bad3.HC
./aholyc run -b c tests/out/ppif-bad3.HC >/dev/null 2>&1 && ppifok=0
if [ "$ppifok" = 1 ]; then
	echo "ok   preprocessor #if"
else
	echo "FAIL preprocessor #if"
	fail=1
fi

# #assert: a false constant expression warns (to stderr) but keeps compiling;
# a true one is silent; the warning must not reach stdout; the same
# expression grammar as #if (incl. defined()); an empty expression errors
passok=1
printf '%s\n' '#assert 1 > 2' '"ran\n";' > tests/out/passfail.HC
[ "$(./aholyc run -b c tests/out/passfail.HC 2>/dev/null)" = ran ] || passok=0   # stdout clean, still runs
./aholyc run -b c tests/out/passfail.HC 2>&1 >/dev/null | grep -q 'warning: assertion failed' || passok=0
./aholyc -b c tests/out/passfail.HC -o tests/out/passfail 2>/dev/null || passok=0  # compiles despite the warning
printf '%s\n' '#assert 2 > 1' '"ok\n";' > tests/out/passok.HC
[ -z "$(./aholyc run -b c tests/out/passok.HC 2>&1 >/dev/null)" ] || passok=0      # true assert: no warning
printf '%s\n' '#assert defined(FEATURE)' '"ok\n";' > tests/out/passdef.HC
./aholyc run -b c tests/out/passdef.HC 2>&1 >/dev/null | grep -q 'assertion failed' || passok=0
[ -z "$(./aholyc run -b c -DFEATURE tests/out/passdef.HC 2>&1 >/dev/null)" ] || passok=0
printf '%s\n' '#assert' '"x";' > tests/out/passbad.HC
./aholyc run -b c tests/out/passbad.HC >/dev/null 2>&1 && passok=0                 # empty -> error
if [ "$passok" = 1 ]; then
	echo "ok   preprocessor #assert"
else
	echo "FAIL preprocessor #assert"
	fail=1
fi

# Unhandled exception message: throw() takes an up-to-8-char constant, so a
# printable one shows as its name; a non-printable value (e.g. a mistaken
# string/pointer throw) degrades to hex instead of spewing raw bytes.
excmsgok=1
for b in $backends; do
	[ "$b" = js ] && continue
	got=$(printf "throw('Boom');\n" | ./aholyc run -b "$b" - 2>&1)
	[ "$got" = "Unhandled Exception 'Boom'" ] || excmsgok=0
	got=$(printf 'throw(0xDEAD00BEEF);\n' | ./aholyc run -b "$b" - 2>&1)
	[ "$got" = "Unhandled Exception '0xDEAD00BEEF'" ] || excmsgok=0
done
if [ "$excmsgok" = 1 ]; then
	echo "ok   unhandled-exception message"
else
	echo "FAIL unhandled-exception message"
	fail=1
fi

# -fno-exceptions removes catch/unwind lowering and exposes a capability macro
# for source fallbacks. A surviving throw has a stable diagnostic and abort
# status, distinct from an ordinary SIGSEGV.
noexceptok=1
./aholyc -h | grep -q -- '-fno-exceptions' || noexceptok=0
printf '%s\n' '#ifdef HAS_EXCEPTIONS' 'try {' "  throw('NoExc');" \
	'} catch {' '  "exceptions=enabled\n";' \
	'  Fs->catch_except = TRUE;' '}' '#else' \
	'"exceptions=disabled fallback\n";' '#endif' \
	>tests/out/no-exceptions-cap.HC
printf '%s\n' 'try {' '  "body-only\n";' '} catch {' \
	'  throw(0xBAD);' '}' >tests/out/no-exceptions-try.HC
printf '%s\n' 'throw(0x1234ABCD);' >tests/out/no-exceptions-crash.HC
for b in $backends; do
	if ! ./aholyc run -b "$b" tests/out/no-exceptions-cap.HC \
		>"tests/out/exceptions-cap-$b.txt" 2>"tests/out/exceptions-cap-$b.err" ||
	   [ "$(cat "tests/out/exceptions-cap-$b.txt")" != \
		'exceptions=enabled' ]; then
		noexceptok=0
	fi
	if ! ./aholyc run -fno-exceptions -b "$b" tests/out/no-exceptions-cap.HC \
		>"tests/out/no-exceptions-cap-$b.txt" \
		2>"tests/out/no-exceptions-cap-$b.err" ||
	   [ "$(cat "tests/out/no-exceptions-cap-$b.txt")" != \
		'exceptions=disabled fallback' ]; then
		noexceptok=0
	fi
	if ! ./aholyc run -fno-exceptions -b "$b" \
		tests/out/no-exceptions-try.HC \
		>"tests/out/no-exceptions-try-$b.txt" \
		2>"tests/out/no-exceptions-try-$b.err" ||
	   [ "$(cat "tests/out/no-exceptions-try-$b.txt")" != body-only ]; then
		noexceptok=0
	fi
	crash="tests/out/no-exceptions-crash-$b"
	if ! ./aholyc -fno-exceptions -b "$b" \
		tests/out/no-exceptions-crash.HC -o "$crash" \
		2>"tests/out/no-exceptions-crash-$b.build"; then
		noexceptok=0
		continue
	fi
	"$crash" >"tests/out/no-exceptions-crash-$b.txt" \
		2>"tests/out/no-exceptions-crash-$b.err"
	[ "$?" = 134 ] || noexceptok=0
	grep -q '^AHOLYC_EXCEPTION=0x000000001234ABCD$' \
		"tests/out/no-exceptions-crash-$b.err" || noexceptok=0
	if [ "$b" = js ]; then
		grep -q 'process.abort' "$crash" || noexceptok=0
		grep -Eq 'HCEXC|hcThrowFn|finally|catch[[:space:]]*\(' \
			"$crash" && noexceptok=0
		if ! ./aholyc -S -fno-exceptions -b js examples/classes.HC \
			-o tests/out/no-exceptions-runtime.js 2>/dev/null ||
		   grep -Eq 'HCEXC|hcThrowFn|finally|catch[[:space:]]*\(' \
			tests/out/no-exceptions-runtime.js; then
			noexceptok=0
		fi
	elif command -v nm >/dev/null 2>&1; then
		nm "$crash" 2>/dev/null | grep -q '__hc_try_push\|hc_frames' && \
			noexceptok=0
	fi
done
./aholyc -S -shared -fno-exceptions -b c tests/exceptions_lowering.HC \
	-o tests/out/exceptions-disabled.c 2>/dev/null || noexceptok=0
grep -q '_setjmp\|__hc_try_push' tests/out/exceptions-disabled.c && noexceptok=0
./aholyc -S -fno-exceptions -b llvm tests/exceptions_lowering.HC \
	-o tests/out/exceptions-disabled.ll 2>/dev/null || noexceptok=0
grep -q 'call i32 @_setjmp\|call ptr @__hc_try_push' \
	tests/out/exceptions-disabled.ll && noexceptok=0
if [ "$noexceptok" = 1 ]; then
	echo "ok   exceptions(disabled/capability/crash)"
else
	echo "FAIL exceptions(disabled/capability/crash)"
	fail=1
fi

# Native exception lowering: no-throw tries need no handler, local throws use
# branches, and only the six call-crossing handlers in this fixture setjmp.
exceptlowerok=1
./aholyc -S -b c tests/exceptions_lowering.HC \
	-o tests/out/exceptions-lowering.c 2>tests/out/exceptions-lowering-c.err || exceptlowerok=0
[ "$(grep -c '_setjmp(' tests/out/exceptions-lowering.c)" = 6 ] || exceptlowerok=0
grep -q 'goto Lhc_catch' tests/out/exceptions-lowering.c || exceptlowerok=0
./aholyc -S -b llvm tests/exceptions_lowering.HC \
	-o tests/out/exceptions-lowering.ll 2>tests/out/exceptions-lowering-ll.err || exceptlowerok=0
[ "$(grep -c 'call i32 @_setjmp' tests/out/exceptions-lowering.ll)" = 6 ] || exceptlowerok=0
grep -Eq 'br label %Bcatch[0-9]+' tests/out/exceptions-lowering.ll || exceptlowerok=0
for b in $backends; do
	./aholyc -b "$b" tests/exceptions_lowering.HC \
		-o "tests/out/exceptions-lowering-$b" 2>"tests/out/exceptions-lowering-$b.err" || {
		exceptlowerok=0
		continue
	}
	"tests/out/exceptions-lowering-$b" >"tests/out/exceptions-lowering-$b.txt" 2>&1 || exceptlowerok=0
	cmp -s tests/expected/exceptions_lowering.out \
		"tests/out/exceptions-lowering-$b.txt" || exceptlowerok=0
done
if [ "$exceptlowerok" = 1 ]; then
	echo "ok   native exception lowering"
else
	echo "FAIL native exception lowering"
	head -5 tests/out/exceptions-lowering-c.err 2>/dev/null
	head -5 tests/out/exceptions-lowering-ll.err 2>/dev/null
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
grep -Eq 'static inline (__attribute__\(\(always_inline\)\) )?hc_i64 hc_InlineAdd\(' \
	tests/out/hints.c || hintsok=0
grep -Eq 'static __attribute__\(\(noinline\)\) hc_i64 hc_NoInlineAdd\(' tests/out/hints.c || hintsok=0

./aholyc -fno-hints -S -b llvm tests/hints.HC -o tests/out/hints-no.ll \
	2>tests/out/hints-no-ll.err || hintsok=0
grep -Eq 'trunc i64 .* to i(1|3|4)' tests/out/hints-no.ll && hintsok=0
grep -Eq '(alwaysinline|noinline)' tests/out/hints-no.ll && hintsok=0
./aholyc -fno-hints -S -b c tests/hints.HC -o tests/out/hints-no.c \
	2>tests/out/hints-no-c.err || hintsok=0
grep -q '_BitInt' tests/out/hints-no.c && hintsok=0
grep -Eq '(always_inline.*hc_InlineAdd|static inline hc_i64 hc_InlineAdd|noinline.*hc_NoInlineAdd)' \
	tests/out/hints-no.c && hintsok=0
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

./aholyc -S -b llvm tests/nonnull.HC -o tests/out/nonnull.ll \
	2>tests/out/nonnull.err || hintsok=0
grep -q 'comparison with null on @nonnull pointer is always false' tests/out/nonnull.err || hintsok=0
grep -q 'call void @llvm.assume(i1 ' tests/out/nonnull.ll || hintsok=0
printf '%s\n' 'U0 F(/* @nonnull */ U8 *p) {}' 'F(NULL);' > tests/out/nonnull-invalid.HC
if ./aholyc -S -b c tests/out/nonnull-invalid.HC -o tests/out/nonnull-invalid.c \
	2>tests/out/nonnull-invalid.err ||
	! grep -q 'null passed to @nonnull parameter' tests/out/nonnull-invalid.err; then
	hintsok=0
fi

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

# variadic FFI, both directions: a bodiless extern with ... calls a real
# C varargs function (printf/snprintf, F64 re-blessed as double), and C
# calls a public HolyC variadic through its (argc, I64 *argv) pair
cc -c tests/varargs_ffi.c -o tests/out/varargs_ffi.o 2>/dev/null
if [ -f tests/out/varargs_ffi.o ]; then
	for b in $backends; do
		[ "$b" = js ] && continue
		if ./aholyc -b "$b" tests/varargs.HC tests/out/varargs_ffi.o \
			-o "tests/out/varargs-ffi-$b" 2>"tests/out/varargs-ffi-$b.err"; then
			"./tests/out/varargs-ffi-$b" >"tests/out/varargs-ffi-$b.txt" 2>&1
			if cmp -s tests/expected/varargs_ffi.out "tests/out/varargs-ffi-$b.txt"; then
				echo "ok   $b/varargs-ffi"
			else
				echo "FAIL $b/varargs-ffi output"
				diff tests/expected/varargs_ffi.out "tests/out/varargs-ffi-$b.txt" | head -10
				fail=1
			fi
		else
			echo "FAIL build $b/varargs-ffi"
			head -5 "tests/out/varargs-ffi-$b.err"
			fail=1
		fi
	done
fi

# make-style env flags: $CFLAGS joins every compile, $LDFLAGS only a link;
# linking through LDFLAGS alone proves the words reach the toolchain
envok=1
if [ -f tests/out/libhctest.a ]; then
	LDFLAGS='-Ltests/out -lhctest' ./aholyc -b c tests/uselib.HC \
		-o tests/out/uselib-env 2>tests/out/env-flags.err || envok=0
	[ "$(tests/out/uselib-env 2>&1)" = "quad(7)=28" ] || envok=0
fi
CFLAGS='-DHC_ENV_CFLAG' LDFLAGS='-DHC_ENV_LDFLAG' ./aholyc -V -b c -c \
	tests/mod_a.HC -o tests/out/mod_env.o 2>>tests/out/env-flags.err || envok=0
grep -q 'HC_ENV_CFLAG' tests/out/env-flags.err || envok=0
grep -q 'HC_ENV_LDFLAG' tests/out/env-flags.err && envok=0
# @cflags/@ldflags source hints feed the same streams; -fno-hints ignores
# them, which must surface as a link failure here
printf '%s\n' '// @cflags=-DHC_HINT_CFLAG' '// @ldflags=-Ltests/out -lhctest' \
	'extern I64 Quad(I64 x);' '"quad(%d)=%d\n", 7, Quad(7);' \
	> tests/out/hintflags.HC
if [ -f tests/out/libhctest.a ]; then
	./aholyc -V -b c tests/out/hintflags.HC -o tests/out/hintflags \
		2>tests/out/hint-flags.err || envok=0
	grep -q 'HC_HINT_CFLAG' tests/out/hint-flags.err || envok=0
	[ "$(tests/out/hintflags 2>&1)" = "quad(7)=28" ] || envok=0
	./aholyc -fno-hints -b c tests/out/hintflags.HC \
		-o tests/out/hintflags-no 2>/dev/null && envok=0
fi
if [ "$envok" = 1 ]; then
	echo "ok   env-flags(CFLAGS/LDFLAGS)"
else
	echo "FAIL env-flags(CFLAGS/LDFLAGS)"
	head -5 tests/out/env-flags.err 2>/dev/null
	fail=1
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

# `aholyc run file.HC` (no -o) must leave no binary behind, while a plain
# build still writes a.out and `run -o name` keeps the named binary
runclean=1
rm -rf tests/out/runclean.d
mkdir -p tests/out/runclean.d
printf '%s\n' '"run ok\n";' > tests/out/runclean.d/t.HC
for b in $backends; do
	[ "$b" = js ] && continue   # js output name is the -o path, not a.out
	out=$(cd tests/out/runclean.d && ../../../aholyc run -b "$b" t.HC 2>/dev/null)
	left=$(cd tests/out/runclean.d && ls -A | grep -v '^t.HC$')
	[ "$out" = "run ok" ] && [ -z "$left" ] || { runclean=0; echo "  left: [$left]"; }
	(cd tests/out/runclean.d && ../../../aholyc -b "$b" t.HC >/dev/null 2>&1)
	[ -f tests/out/runclean.d/a.out ] || runclean=0        # plain build keeps a.out
	rm -f tests/out/runclean.d/a.out
	(cd tests/out/runclean.d && ../../../aholyc run -b "$b" -o keep t.HC >/dev/null 2>&1)
	[ -f tests/out/runclean.d/keep ] || runclean=0          # run -o keeps the binary
	rm -f tests/out/runclean.d/keep
done
if [ "$runclean" = 1 ]; then
	echo "ok   run(no binary left behind)"
else
	echo "FAIL run(no binary left behind)"
	fail=1
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
./aholyc fmt tests/asm.HC > tests/out/fmt-asm.HC || fmtok=0
./aholyc fmt -q - < tests/out/fmt-asm.HC || fmtok=0
if [ "$haveasm" = 1 ]; then
	if ./aholyc -b c tests/out/fmt-asm.HC -o tests/out/fmt-asm \
		2>/dev/null; then
		tests/out/fmt-asm >tests/out/fmt-asm.txt 2>&1 || fmtok=0
		cmp -s tests/expected/asm.out tests/out/fmt-asm.txt || fmtok=0
	else
		fmtok=0
	fi
fi
rm -rf tests/out/fmtroot
mkdir -p tests/out/fmtroot/examples
ln -s ../../../lib tests/out/fmtroot/lib 2>/dev/null ||
	cp -R lib tests/out/fmtroot/lib
for f in examples/*.HC; do
	n=$(basename "$f" .HC)
	fmtf="tests/out/fmtroot/examples/$n.HC"
	./aholyc fmt "$f" > "$fmtf" || { fmtok=0; continue; }
	./aholyc fmt - < "$fmtf" | cmp -s - "$fmtf" || fmtok=0
	[ -f "tests/expected/$n.out" ] || continue
	if ./aholyc -b c "$fmtf" -o "tests/out/fmt-$n" 2>/dev/null; then
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
