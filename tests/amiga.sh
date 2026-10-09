#!/bin/sh
# Cross-link tests; running Hunk executables requires an Amiga or emulator.
set -eu
cd "$(dirname "$0")/.."
mkdir -p tests/out/amiga
out=tests/out/amiga

# Target selection and preprocessing work without a cross compiler installed.
./aholyc -t amiga -S tests/amiga.HC -o "$out/checks.c"
./aholyc -t amiga -S tests/ui_amiga_layout.HC -o "$out/ui-layout.c"
${CC:-cc} -w -Os "$out/ui-layout.c" tests/ui_amiga_stubs.c -lm -o "$out/ui-layout"
"$out/ui-layout" >"$out/ui-abi.c"
grep -q 'sizeof NewGadget' "$out/ui-abi.c"
echo "ok   amiga UI(model/layout/ownership/visibility)"
for backend in llvm js; do
	if ./aholyc -t amiga -b "$backend" -S examples/hello.HC \
		-o "$out/invalid" >"$out/invalid.txt" 2>"$out/invalid.err"; then
		echo "FAIL amiga accepted $backend backend"
		exit 1
	fi
	grep -q 'requires the C backend' "$out/invalid.err"
done
if ./aholyc run -t amiga examples/hello.HC \
	>"$out/invalid.txt" 2>"$out/invalid.err"; then
	echo "FAIL amiga accepted host execution"
	exit 1
fi
grep -q 'cannot execute Amiga binaries' "$out/invalid.err"
if ./aholyc -t amiga -shared -S examples/hello.HC \
	-o "$out/invalid" >"$out/invalid.txt" 2>"$out/invalid.err"; then
	echo "FAIL amiga accepted shared library"
	exit 1
fi
grep -q 'does not support -shared' "$out/invalid.err"
echo "ok   amiga(target selection/macros/unsupported modes)"

cross_cc=${AMIGA_CC:-m68k-amigaos-gcc}
if ! command -v "$cross_cc" >/dev/null 2>&1; then
	if [ -z "${AMIGA_CC:-}" ] && [ -x /opt/amiga/bin/m68k-amigaos-gcc ]; then
		cross_cc=/opt/amiga/bin/m68k-amigaos-gcc
	else
		if [ -n "${AMIGA_CC:-}" ]; then
			echo "FAIL Amiga compiler not found: $AMIGA_CC"
			exit 1
		fi
		echo "skip amiga cross-link tests (set AMIGA_CC)"
		exit 0
	fi
fi
AMIGA_CC=$cross_cc
export AMIGA_CC

check_hunk() {
	# HUNK_HEADER (1011) is the executable's first big-endian word.
	[ "$(od -An -tx1 -N4 "$1" | tr -d ' \n')" = 000003f3 ] || {
		echo "FAIL amiga Hunk header: $1"
		exit 1
	}
}

for src in examples/*.HC tests/amiga.HC tests/args.HC tests/exceptions_lowering.HC; do
	name=$(basename "$src" .HC)
	./aholyc -t amiga "$src" -o "$out/$name"
	check_hunk "$out/$name"
done
echo "ok   amiga(examples/packed fields/argv/exceptions/atomics/#exe)"

"$cross_cc" -std=gnu99 -c "$out/ui-abi.c" -o "$out/ui-abi.o"
for name in amiga simpledemo demo draw table tree; do
	./aholyc -t amiga "examples/ui/$name.hc" -o "$out/ui-$name"
	check_hunk "$out/ui-$name"
done
echo "ok   amiga UI(NDK layouts/native gadget/drawing/table/tree cross-link)"

# These modes link the complete runtime separately, exercising dependencies
# that whole-program dead-code elimination can otherwise hide.
./aholyc -t amiga -c tests/mod_a.HC -o "$out/module.o"
./aholyc -t amiga tests/mod_b.HC "$out/module.o" -o "$out/objects"
check_hunk "$out/objects"
./aholyc -t amiga -sarchive tests/mod_a.HC -o "$out/module.a"
./aholyc -t amiga tests/mod_b.HC "$out/module.a" -o "$out/archive"
check_hunk "$out/archive"
./aholyc -t amiga -fno-exceptions -fno-pic -fno-stack-protector \
	examples/hello.HC -o "$out/no-features"
check_hunk "$out/no-features"
echo "ok   amiga(objects/archives/disabled features)"
