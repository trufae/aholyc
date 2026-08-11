# Regular expressions

`regex.hc` is a dependency-free, UTF-8 regular-expression engine for HolyC.
It uses `lib/text/utf8.HC` and compiles patterns to a Thompson NFA, so matching
has predictable memory use and avoids the catastrophic backtracking found in
recursive backtracking engines. It has no built-in pattern-size limit and uses
the common `lib/alloc/alloc.hc` allocator interface.

## API

```c
#include "lib/regex/regex.hc"

CRegex regex;
CRegexMatch *item;
U8 output[128];

RegexInit(&regex);
if (!RegexCompile(&regex, "[A-Za-z_][A-Za-z0-9_]*"))
  "regex error at %d: %s\n", regex.error_offset,
    RegexErrorName(regex.error);

item = RegexFind(&regex, "123 hello");
if (item)
  "match bytes %d..%d\n", item->start, item->end;

RegexCompile(&regex, "^(👋|🌍)+$");
if (RegexFullMatch(&regex, "👋🌍"))
  "emoji match\n";

RegexReplace(&regex, "one two", "<$0>", output, sizeof(output));
RegexFini(&regex);
```

`RegexInit(&regex)` uses the default `MAlloc`/`Free` adapter. Pass a
`CAllocator *` as its optional second argument to use an arena, pool, or
stack-backed allocator instead. The descriptor is copied into `CRegex`, so it
may be temporary; its context and returned memory must outlive the regex.
`RegexMemorySize(pattern_length)` reports the worst-case allocation request
for arena planning.

For example, `lib/alloc/stack.HC` can supply storage without changing the
regex API: `StackAllocatorInit` initializes a `CStackAllocator` over a
suitably lived buffer and returns the pointer to pass to `RegexInit`.

Compile once and reuse the `CRegex`. `RegexFind` searches for the first
leftmost match; among matches beginning at the same byte it returns the
longest. `RegexFullMatch` requires the whole input to match. `RegexFindN`
accepts an explicit length and starting byte offset, so it supports buffers
containing NUL.
Positions and lengths remain byte offsets, while pattern atoms and input
characters are decoded as Unicode code points.
`RegexFini` releases the owned block through the configured allocator.

## Streaming matches

`RegexFind` returns the first non-overlapping match and starts a pull-style
traversal. Pass that match to `RegexNext` until it returns `NULL`; stop at any
time without a separate cursor initialization step:

```c
item = RegexFind(&regex, text);
while (item) {
  // item->start and item->end are byte offsets
  if (Enough(item))
    break;
  item = RegexNext(item);
}
```

`RegexFindN` accepts an explicit input length and starting offset. The returned
pointer belongs to `CRegex` and remains valid until another match operation,
compilation, or finalization. One expression supports one active traversal;
use separate compiled instances for simultaneous traversals.

`RegexReplace` replaces every non-overlapping match by default. Pass a
non-negative `limit` to restrict the number of replacements. `$0` inserts the
whole match and `$$` inserts a literal dollar sign. The function returns the
required byte count, excluding the final NUL. Pass `NULL, 0` to size first; a
buffer smaller than `required + 1` is left untouched. `-1` reports invalid
arguments or size overflow.

## Pattern syntax

- Literals, grouping with `(...)`, and alternation with `|`
- `.` for any valid UTF-8 code point
- Greedy `*`, `+`, and `?`
- `^` and `$` for absolute input boundaries
- Character classes, negated classes, and code-point ranges: `[abc]`,
  `[^0-9]`, `[α-ω]`, `[😀-🙏]`
- `\d`, `\w`, and `\s`, both inside and outside classes
- `\n`, `\r`, `\t`, `\f`, `\v`, `\xHH` (U+00HH), and escaped punctuation

Patterns must be valid UTF-8 or compilation fails with `REGEX_ERROR_UTF8`.
Malformed input bytes are skipped during searches and never matched by `.`, a
literal, or a class; consequently a full match rejects malformed input.
`\d`, `\w`, and `\s` intentionally retain their common ASCII meanings—Unicode
properties are not inferred from locale data.

There are no capture groups, backreferences, look-around assertions, counted
repetitions, lazy quantifiers, flags, or Unicode properties in this initial
API. A `CRegex` owns reusable matching workspace; do not use one instance
concurrently from multiple threads (separate compiled instances are
independent).
