# RFC: Unified dot operator and OO method-call syntax

- **Status:** Draft
- **Author:** pancake (via opencode analysis)
- **Date:** 2026-08-17
- **Depends on:** —
- **Supersedes:** —

## Problem

HolyC has two member-access operators (`.` and `->`) that are **mutually
exclusive**: `.` only works on class values, `->` only works on pointers.
Aholyc inherits this split.  There is no way to call a function as a
method on an object — users must write `FooMethod(foo)` instead of
`foo.Method()`.

This RFC proposes two related changes:

1. **Unified `.` operator** — `.` auto-dereferences pointers, making
   `->` an optional synonym (kept for backward compatibility).
2. **OO method-call syntax** — `foo.Method(args)` desugars to
   `FooMethod(&foo, args)` (value) or `FooMethod(foo, args)` (pointer).

Both are pure parser desugaring.  No AST changes, no backend changes.

## Background

### Current state of `.` vs `->`

The parser (`parse.c:1299–1336`) treats `.` and `->` as separate
branches:

```c
if (is_punct(ps, ".") || is_punct(ps, "->")) {
    bool arrow = is_punct(ps, "->");
    // ...
    if (arrow) {
        base = rvalize(n);
        if (base->ty->kind != TY_PTR || !base->ty->base)
            error_tok(ps->cc, t, "'->' on a non-pointer");
        Node *d = new_unary(ps, ND_DEREF, base, t);
        d->ty = base->ty->base;
        base = d;
    }
    // field lookup on base...
}
```

`ptr.field` errors with "member access on a non-class value".
`val->field` errors with "'->' on a non-pointer".

The distinction is purely a **parser constraint** — the AST is identical
in both cases:

| Source      | AST                                |
|-------------|-------------------------------------|
| `val.field` | `ND_MEMBER(val, field)`             |
| `ptr->field`| `ND_MEMBER(ND_DEREF(ptr), field)`   |

Both backends emit the same code: `base_addr + offset`.

### Usage in the codebase

| Metric                  | Count  |
|-------------------------|--------|
| `->` occurrences        | 3,275  |
| `.` member-access       | 274    |
| `->` as % of total      | 92.3%  |

`->` dominates because most objects in HolyC are heap-allocated pointers
(`MAlloc`/`MAllocAligned`).  Stack-allocated class values are rare.

### HolyC naming convention

Functions that operate on a class follow the pattern:

```
FunctionName = StripC(ClassName) + Verb
```

First parameter is always a pointer to the class:

| Class     | Function                | Proposed syntax   |
|-----------|-------------------------|--------------------|
| `CStrs`   | `StrsLen(CStrs *s)`    | `s.Len()`          |
| `CStrBuf` | `StrBufPutS(CStrBuf *b, ...)` | `b.PutS(...)` |
| `CList`   | `ListPushBack(CList *l, ...)` | `l.PushBack(...)` |
| `CVec`    | `VecPush(CVec *v, ...)` | `v.Push()`         |
| `CThread` | `ThreadCreate(CThread *t, ...)` | `t.Create(...)` |
| `CRegex`  | `RegexCompile(CRegex *r, ...)` | `r.Compile(...)` |

The `C` prefix on class names is the convention.  Functions strip it.

## Proposal

### Part 1: Unified `.` operator (auto-deref)

Change the `.` branch in `postfix()` to auto-dereference pointers:

```
Current:  .field  →  base must be TY_CLASS, else error
          ->field →  base must be TY_PTR, deref, then TY_CLASS

Proposed: .field  →  if TY_PTR, auto-deref; then TY_CLASS
          ->field →  same (backward compat alias)
```

The `->` operator is **not removed** — it continues to work identically.
It becomes a deprecated synonym.

#### Semantics

| Expression    | `foo` type   | Result                              |
|---------------|-------------|--------------------------------------|
| `foo.field`   | `CFoo`      | Direct field access (unchanged)      |
| `foo.field`   | `CFoo *`    | Auto-deref, then field access        |
| `foo.field`   | `TY_INT`    | Sub-int view access (unchanged)      |
| `foo->field`  | `CFoo *`    | Deref, then field access (unchanged)|
| `foo->field`  | `CFoo`      | Error (non-pointer) — **still** error|
| `foo.field`   | `CFoo **`   | Auto-deref once → `CFoo *` field     |

`->` on a non-pointer remains an error.  `.` on a non-class non-int
non-pointer remains an error.

#### Implementation patch

```diff
--- a/src/parse.c
+++ b/src/parse.c
@@ -1299,14 +1299,13 @@ static Node *postfix(Parser *ps) {
 		if (is_punct (ps, ".") || is_punct (ps, "->")) {
-			bool arrow = is_punct (ps, "->");
 			ps->tk = ps->tk->next;
 			Token *mt = ps->tk;
 			reject_reserved_name (ps, mt, "member name", true);
 			if (!is_lexical_name (mt)) {
 				error_tok (ps->cc, mt, "expected member name");
 			}
 			Node *base = n;
-			if (arrow) {
+			/* auto-dereference pointers on both . and -> */
+			if (base->ty->kind == TY_PTR && base->ty->base) {
 				base = rvalize (n);
-				if (base->ty->kind != TY_PTR || !base->ty->base) {
-					error_tok (ps->cc, t, "'->' on a non-pointer");
-				}
 				Node *d = new_unary (ps, ND_DEREF, base, t);
 				d->ty = base->ty->base;
 				base = d;
 			}
```

Note: `->` no longer *requires* a pointer — it just *allows* one.  If
the base is already a class value, `->` works the same as `.`.  If the
base is a non-pointer non-class (e.g. `TY_INT`), the existing
`subint_access()` or error path handles it.

**Alternative (stricter):** Keep `->` as pointer-only and only change
`.` to auto-deref.  This preserves the "arrow means pointer" signal:

```diff
--- a/src/parse.c
+++ b/src/parse.c
@@ -1299,14 +1299,13 @@ static Node *postfix(Parser *ps) {
 		if (is_punct (ps, ".") || is_punct (ps, "->")) {
-			bool arrow = is_punct (ps, "->");
 			ps->tk = ps->tk->next;
 			Token *mt = ps->tk;
 			reject_reserved_name (ps, mt, "member name", true);
 			if (!is_lexical_name (mt)) {
 				error_tok (ps->cc, mt, "expected member name");
 			}
 			Node *base = n;
-			if (arrow) {
+			/* auto-deref pointers on . (-> also works for compat) */
+			if (base->ty->kind == TY_PTR && base->ty->base) {
 				base = rvalize (n);
-				if (base->ty->kind != TY_PTR || !base->ty->base) {
-					error_tok (ps->cc, t, "'->' on a non-pointer");
-				}
 				Node *d = new_unary (ps, ND_DEREF, base, t);
 				d->ty = base->ty->base;
 				base = d;
 			}
```

This version: `.` auto-derefs.  `->` also auto-derefs (for backward
compat).  Both `.` and `->` error on non-pointer non-class types.

### Part 2: OO method-call syntax

When `.` or `->` is followed by an identifier **and** `(`, and the
identifier is **not** a class member, look up a function named
`StripC(base_type_name) + identifier` and desugar to a call with the
receiver as the first argument.

#### Name construction

```
base_type = "CFoo"  →  func_prefix = "Foo"
base_type = "CList" →  func_prefix = "List"
base_type = "HtkCtl"→  func_prefix = "HtkCtl"  (no C to strip)
```

Strip the leading `C` if present and the remainder starts with an
uppercase letter.  Append the method name.

#### Calling convention

| `foo` type   | `foo.Method(args)` desugars to     |
|-------------|--------------------------------------|
| `CFoo`      | `FooMethod(&foo, args)`             |
| `CFoo *`    | `FooMethod(foo, args)`              |
| `CFoo **`   | `FooMethod(*foo, args)` (auto-deref)|

For rvalues (non-lvalues), a temporary is introduced:

```holyc
get_foo().Method(x)
// becomes:
CFoo __tmp = get_foo();
FooMethod(&__tmp, x);
```

This matches C++ reference binding rules.

#### Disambiguation: fields vs methods

**Fields always win.** If `find_member()` succeeds, it is field access
(no method lookup).  Method lookup only happens when:

1. The name after `.` is **not** a member of the class, AND
2. The next token is `(` (it is a call expression)

If the name is not a member and no `(` follows, it is an error (same as
today).  If the name is not a member and `(` follows but no function
matches, it is an error.

This guarantees **100% backward compatibility** — existing `foo.field`
code is never affected.

#### Implementation patch

```diff
--- a/src/parse.c
+++ b/src/parse.c
@@ -1299,14 +1299,44 @@ static Node *postfix(Parser *ps) {
 		if (is_punct (ps, ".") || is_punct (ps, "->")) {
 			ps->tk = ps->tk->next;
 			Token *mt = ps->tk;
 			reject_reserved_name (ps, mt, "member name", true);
 			if (!is_lexical_name (mt)) {
 				error_tok (ps->cc, mt, "expected member name");
 			}
 			Node *base = n;
+			/* auto-deref pointers */
+			if (base->ty->kind == TY_PTR && base->ty->base) {
+				base = rvalize (n);
+				Node *d = new_unary (ps, ND_DEREF, base, t);
+				d->ty = base->ty->base;
+				base = d;
+			}
 			if (base->ty->kind == TY_INT) {
 				n = subint_access (ps, base, t);
 				continue;
 			}
 			char *member_name = take_name (ps, "member name", true);
-			if (base->ty->kind != TY_CLASS) {
-				error_tok (ps->cc, t, "member access on a non-class value");
+			if (base->ty->kind != TY_CLASS) {
+				error_tok (ps->cc, t,
+					"member access on a non-class value");
 			}
-			Member *m = find_member (base->ty, member_name);
-			if (!m) {
-				error_tok (ps->cc, mt, "no member '%s' in class %s",
-					member_name,
-					base->ty->name? base->ty->name: "?");
+			/* field lookup first (fields always win) */
+			Member *m = find_member (base->ty, member_name);
+			if (m) {
+				Node *mn = new_node (ND_MEMBER, t);
+				mn->lhs = base;
+				mn->member_ref = m;
+				mn->ty = m->ty;
+				n = mn;
+				continue;
+			}
+			/* not a field: try OO method call if ( follows */
+			if (eat (ps, "(")) {
+				Type *ty = base->ty;
+				char *prefix = ty->name && ty->name[0] == 'C'
+					&& ty->name[1] >= 'A' && ty->name[1] <= 'Z'
+					? ty->name + 1 : ty->name;
+				char *fname = xasprintf (ps->cc, "%s%s",
+					prefix, member_name);
+				Obj *fn = find_func (ps, fname);
+				if (!fn) {
+					error_tok (ps->cc, mt,
+						"no member '%s' in class %s "
+						"and no function '%s()' found",
+						member_name,
+						ty->name? ty->name: "?",
+						fname);
+				}
+				/* prepend receiver as first argument */
+				Node *receiver = base;
+				if (base->ty->kind != TY_PTR) {
+					receiver = new_unary (ps, ND_ADDR,
+						rvalize (base), t);
+					receiver->ty = ptr_to (base->ty);
+				}
+				Node *args = parse_args (ps);
+				/* prepend receiver to arg list */
+				if (args) {
+					Node *tail = args;
+					while (tail->next) tail = tail->next;
+					tail->next = args;
+					args = receiver;
+				} else {
+					args = receiver;
+				}
+				n = make_call (ps, fn, args, 0, t);
+				continue;
 			}
-			Node *mn = new_node (ND_MEMBER, t);
-			mn->lhs = base;
-			mn->member_ref = m;
-			mn->ty = m->ty;
-			n = mn;
-			continue;
+			error_tok (ps->cc, mt, "no member '%s' in class %s",
+				member_name,
+				ty->name? ty->name: "?");
 		}
```

### Part 3: `-fno-arrow` flag

Add a compiler flag that makes `->` an error, forcing migration to `.`.

#### `Aholyc` struct change (`aholyc.h`)

```diff
 struct Aholyc {
 	// ...
 	bool verbose, keep, shared, archive, use_hints, use_asm, use_pic;
-	bool use_exceptions, use_stack_protector, error_active;
+	bool use_exceptions, use_stack_protector, error_active, no_arrow;
 };
```

#### Flag parsing (`aholyc.c`)

```diff
 		} else if (!strcmp (go.arg, "no-stack-protector")) {
 			cc->use_stack_protector = false;
+		} else if (!strcmp (go.arg, "no-arrow")) {
+			cc->no_arrow = true;
 		} else {
```

#### Parser enforcement (`parse.c`)

```diff
 		if (is_punct (ps, ".") || is_punct (ps, "->")) {
+			if (is_punct (ps, "->") && ps->cc->no_arrow) {
+				error_tok (ps->cc, ps->tk,
+					"'->' is disabled; use '.' instead "
+					"(pass -fno-arrow=0 to allow)");
+			}
 			ps->tk = ps->tk->next;
```

## Migration strategy

### Phase 1: Enable auto-deref (default on)

Ship the unified `.` as the default.  `->` continues to work.
No code breaks.

### Phase 2: `-fno-arrow` warning mode

Add a `-farrow-warn` flag (or make `-fno-arrow` emit warnings instead
of errors) so users can see which files still use `->`.

```
aholyc -farrow-warn *.hc
# warning: foo.hc:42: '->' is deprecated; use '.' instead
```

### Phase 3: `-fno-arrow` error mode

Default to `-fno-arrow` for new projects.  Existing projects opt in.

### Phase 4: Remove `->` (future major version)

After a deprecation cycle, `->` becomes a syntax error by default.

## Pros and cons

### Pros

- **One syntax for member access.** `.` does everything.  Less to learn.
- **OO method calls.** `s.Len()` instead of `StrsLen(s)`.  Matches
  intuition from other languages.
- **Zero runtime cost.** Pure parser desugaring.  Same AST, same code.
- **100% backward compatible.** `->` still works.  Fields shadow methods.
- **Small patch.** ~60 lines of parser changes.  No AST, backend, or
  type-system changes needed.
- **Formatter is unaffected.** `fmt.c` doesn't parse expressions.
- **Pointer semantics preserved.** `.` auto-derefs, so `ptr.field`
  works naturally without losing the ability to see that `ptr` is a
  pointer (the type system still knows).

### Cons

- **Loses explicit pointer signal.** A reader can't glance at `obj.x`
  and know if `obj` is a pointer or value.  In low-level code this can
  matter for reasoning about lifetimes.  (Mitigated by: HolyC is
  garbage-collected; explicit pointer reasoning is less common than in C.)
- **`StripC` heuristic is fragile.** Classes not following the `C`-prefix
  convention (e.g. `HtkCtl`, `UiCtl`) produce unintuitive function
  names.  The heuristic can be extended or made configurable, but it is
  inherently a convention, not a type-system guarantee.
- **Field shadowing.** If a class has a field `Init` and a function
  `FooInit` exists, `foo.Init` accesses the field, not the function.
  This is the correct behavior (fields win), but may surprise users who
  expect method dispatch.
- **No overload resolution.** HolyC has no function overloading.
  `foo.Bar()` resolves to exactly one `FooBar()` function.  If two
  classes share a prefix (e.g. `CJsonValue` and `CJsonDecoder` both
  using `Json*`), disambiguation depends entirely on the receiver type.
  This is correct but inflexible.
- **Sub-int view interaction.** `q.u8[5]` on `TY_INT` uses `.` for
  sub-int views.  If `q` were a pointer to an int (`I64 *q`), auto-deref
  would make `q.u8[5]` dereference then sub-int-view.  This is
  semantically correct but may surprise users who expect `q.u8[5]` to
  mean "byte 5 of the pointer value itself" (address arithmetic).
- **Backward-compat debt.** `->` works forever but should eventually
  die.  The deprecation cycle is additional maintenance burden.

## Alternatives considered

### 1. New operator (`:`, `->>`, `::`)

Use `buf:PutS("hi")` or `buf->>PutS("hi")` instead of `buf.PutS("hi")`.

| Operator | Pros | Cons |
|----------|------|------|
| `:`      | No ambiguity with `.`; clean visual separator | `:` already used in `case X:`, `class A : B`, ternary (though HolyC has no ternary) |
| `->>`    | Explicit "method call on pointer" | Ugly; non-standard |
| `::`     | Used in some OO languages | Already rejected by parser (`ident ':'` not `ident '::'` check) |

**Verdict:** `:` is the cleanest alternative but adds syntax that
conflicts with `case`/`class` contexts (even though they're not in
expression position, it hurts readability).  Overloading `.` is simpler
and more consistent.

### 2. Macro-based approach

```holyc
#define METHOD(Type, Name, ...) Type##Name(__VA_ARGS__)
```

**Verdict:** Fragile, no type safety, no IDE support, requires
per-function opt-in.  Worse than a compiler feature.

### 3. `#method` decorator

```holyc
#method StrsLen(CStrs *s) { return s->len; }
```

**Verdict:** Requires explicit opt-in, adds syntax, doesn't solve the
call-site ergonomics without additional compiler support anyway.

### 4. Don't do it

Keep `FooMethod(foo)` as the only way.

**Verdict:** The codebase has 3,275 `->` calls and 274 `.` field
accesses.  The convention works but is verbose.  The method syntax is a
significant ergonomic improvement for the 137 library files.

## Open questions

1. **Should `->` auto-deref too?**  The stricter approach keeps `->`
   as pointer-only and only changes `.`.  This preserves the "arrow
   means pointer" signal for readers.  The permissive approach unifies
   both.

2. **Rvalue handling for method calls.**  `get_foo().Method()` on a
   value type needs a temporary.  Should the compiler always create one,
   or should it be an error ("cannot call method on rvalue")?

3. **Chaining.**  Should `list.PushBack(5).PushFront(6)` work when
   `PushBack` returns `CList *`?  This requires the parser to know the
   return type at parse time (it does — `make_call` sets `n->ty`).

4. **`StripC` configurability.**  Should users be able to annotate
   a class with `@method_prefix(Foo)` to override the automatic prefix
   derivation?

## References

- `src/parse.c:1299–1336` — current `.`/`->` handling
- `src/parse.c:908–983` — `make_call()` (direct call construction)
- `src/parse.c:157–164` — `find_func()` (function name lookup)
- `src/parse.c:63–72` — `find_member()` (field lookup with inheritance)
- `src/aholyc.h:268–283` — `Aholyc` compiler struct
- `src/aholyc.c:199–212` — `-f*` flag parsing
- `doc/language.md` — language specification
