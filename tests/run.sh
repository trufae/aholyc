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

if [ "$fail" = 0 ]; then
	echo "all tests passed"
fi
exit $fail
