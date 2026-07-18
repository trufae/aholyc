# `ahc fmt` — HolyC source formatting

`ahc fmt` formats and format-checks HolyC sources so a codebase can
follow one standard. It lives entirely in `src/fmt.c`, separate from
the compiler proper.

## The style

TempleOS never shipped a formatter, but its sources follow a
consistent conventional style, and that is what `ahc fmt` enforces:

* Two spaces per nesting level.
* Opening braces generally on their own line for functions/classes.
* Closing braces aligned with the construct that opened them.
* Statements inside a block indented two spaces.
* `case` labels typically indented with the surrounding switch style.

Concretely (all real TempleOS shapes):

```holyc
U0 StreamPrint(U8 *fmt, ...)
{//Comments may ride on the brace line.
  if (ok) {
    "yes\n";
  } else {
    "no\n";
  }
  switch (ch) {
    case 'a':
      DoA;
      break;
    default:
      DoB;
      break;
  }
}
```

Control-flow braces stay on the statement line (`if (x) {`); only
function and class/union headers get the brace on its own line.
One-line bodies like `U0 Tiny() {return;}` are left alone — TempleOS
itself writes those.

Further rules, all taken from shapes in the TempleOS sources:

* the body of a braceless `if`/`else`/`for`/`while`/`do` indents one
  level (`if (x)` ⏎ `  stmt;`), nesting as needed;
* in a `sub_switch` group, `case` labels between `start:` and `end:`
  go one level deeper than the group labels (`Compiler/CMain.HC`);
* plain `goto` labels (`done:` alone on a line) sit at column 0
  (`Adam/AMathODE.HC`);
* a statement continued on the next line without open parentheses
  (e.g. a print statement broken after a comma) indents one level;
  lines inside unclosed `(`/`[` indent one level per open paren.

## Usage

```console
$ ahc fmt file.HC ...        # print formatted source to stdout
$ ahc fmt -w file.HC ...     # rewrite files in place (only if changed)
$ ahc fmt -q file.HC ...     # check: list files needing formatting,
                             #        exit 1 if any (nothing rewritten)
$ ahc fmt - < in > out       # filter stdin to stdout ('-' or no args)
$ make fmt                   # normalize every .HC/.hc in the repo
```

Options are environment variables, so the compiler CLI stays small:

| variable | meaning |
|----------|---------|
| `AHC_FMT_INDENT=n` | spaces per nesting level (default 2) |
| `AHC_FMT_BRACES=0` | don't move function/class `{` to its own line |

## What it changes — and what it never touches

The formatter only rewrites **whitespace**: leading indentation,
trailing blanks, and (for function/class headers) a newline before the
`{`. Everything else passes through untouched:

* comments are preserved exactly (it has its own scanner — the
  compiler's lexer drops comments, so it is never used here);
* the interior lines of multi-line strings and block comments are
  emitted verbatim;
* intra-line spacing and tab alignment inside a line are kept;
* blank lines between code are kept (trailing ones at EOF dropped).

Continuation lines inside unclosed `(`/`[` get one extra level per
open paren; a line starting with the closer aligns with the opener's
statement.

## Safety

Formatting must never destroy code, including code that does not
parse:

* Before printing or writing anything, the output is verified to be
  byte-identical to the input after removing all whitespace. If that
  check ever fails, the file is reported and left untouched.
* Unterminated strings or comments degrade gracefully: affected lines
  pass through verbatim.
* `-w` writes to a temporary file in the same directory and renames it
  over the original, and only when the content actually changed.
* The formatter is idempotent; `tests/run.sh` verifies idempotency and
  that every formatted example still compiles to identical output.

Exit status: `0` on success, `1` if `-q` found unformatted files or
any file could not be read/verified.
