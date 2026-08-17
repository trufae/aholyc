# RFC: OO method-call syntax for aholyc

- **Status:** Draft
- **Author:** pancake (via opencode analysis)
- **Date:** 2026-08-17
- **See also:** [dotref.md](dotref.md) (unified `.` operator, related but independent)

## Problem

HolyC uses a naming convention where functions operating on a class are
prefixed with the class name (minus the `C` prefix), and the first
argument is always a pointer to the object:

```holyc
class CStrs { I64 len; };
I64 StrsLen(CStrs *s);

CStrs *s = ...;
I64 l = StrsLen(s);     // verbose, non-OO
```

This works but is verbose and non-idiomatic for OO-style code.  Other
languages let you write `s.Len()` — the object is the syntactic focus,
not buried in the argument list.

This RFC proposes desugaring `foo.Method(args)` into `FooMethod(&foo,
args)` (value) or `FooMethod(foo, args)` (pointer) at parse time, using
the existing naming convention and type information.

## Background

### The naming convention in the codebase

The codebase follows a consistent pattern across 137 HolyC source files:

**`FunctionPrefix = StripC(ClassName) + Operation`**, first param is a
pointer to the class.

| Class        | Function                              | Signature                     |
|-------------|---------------------------------------|-------------------------------|
| `CStrs`     | `StrsLen`                            | `I64 StrsLen(CStrs *s)`       |
| `CStrs`     | `StrsFind`                           | `I64 StrsFind(CStrs *s, ...)` |
| `CStrBuf`   | `StrBufPutS`                         | `U0 StrBufPutS(CStrBuf *b, ...)` |
| `CStrBuf`   | `StrBufPrintf`                       | `U0 StrBufPrintf(CStrBuf *b, ...)` |
| `CList`     | `ListPushBack`                       | `U0 ListPushBack(CList *l, I64 v)` |
| `CList`     | `ListIsEmpty`                        | `Bool ListIsEmpty(CList *l)`  |
| `CVec`      | `VecPush`                            | `U0 VecPush(CVec *v, I64 val)` |
| `CVec`      | `VecSort`                            | `U0 VecSort(CVec *v)`         |
| `CThread`   | `ThreadCreate`                       | `U0 ThreadCreate(CThread *t, ...)` |
| `CThread`   | `ThreadJoin`                         | `U0 ThreadJoin(CThread *t)`   |
| `CRegex`    | `RegexCompile`                       | `Bool RegexCompile(CRegex *r, ...)` |
| `CRegex`    | `RegexEmit`                          | `U0 RegexEmit(CRegexCompiler *c, ...)` |
| `CAllocator`| `AllocatorAlloc`                     | `U8 *AllocatorAlloc(CAllocator *a, I64 sz)` |
| `CHashTable`| `HtFind`                            | `U8 *HtFind(CHashTable *t, ...)` |
| `CSsl`      | `SslRead`                            | `I64 SslRead(CSsl *tls, ...)` |
| `CHttpUrl`  | `HttpUrlParse`                       | `U0 HttpUrlParse(U8 *text, CHttpUrl *u)` |
| `HtkCtl`    | `HtkFire`                            | `U0 HtkFire(HtkCtl *c)`      |
| `UiCtl`     | `UiShow`                             | `U0 UiShow(UiCtl *w)`        |

There is **no function overloading** in HolyC.  `find_func()` does
simple name lookup — first match wins.  This makes the desugaring
deterministic: given a receiver type and a method name, there is at most
one function to call.

### How function calls are parsed today

Two paths in `parse.c`:

1. **Direct calls** (`primary()`, line 1163): `Ident(args)` — the parser
   looks up the identifier as a function with `find_func()`, parses
   args, and calls `make_call()`.

2. **Indirect calls** (`postfix()`, line 1279): `expr(args)` where
   `expr` is not a type — the parser calls `make_indirect_call()`.

Neither path handles `expr.Method(args)`.  The `.` and `->` operators
only do field access (`ND_MEMBER`).  If the field doesn't exist, it is
an error — there is no fallback to function lookup.

### `make_call()` (parse.c:908–983)

Constructs an `ND_CALL` node for direct calls:

1. Collects args into an array (up to 256).
2. For each parameter position, fills in defaults if no arg provided.
3. Applies type conversions (`F64` ↔ int).
4. Returns a completed `ND_CALL` node with `n->func = fn`.

The desugaring inserts the receiver as the first argument before this
process, so default args and type conversions work unchanged.

### `find_func()` (parse.c:157–164)

Linear scan of `ps->prog->funcs` linked list, comparing names with
`strcmp()`.  Returns the first match or NULL.  No type-based overload
resolution.

### `find_member()` (parse.c:63–72)

Walks the class hierarchy (`ty->parent`) looking for a member by name.
Returns the first match or NULL.

## Proposal

### Syntax

```
receiver.Method(args)
receiver->Method(args)     (same thing if -> auto-derefs; see dotref.md)
```

### Desugaring rules

#### Step 1: Determine the receiver type

After `.` or `->`, the parser has `base` (the receiver expression) with
a known type `base->ty`.

- If `base->ty` is `TY_PTR`, the base is a pointer.  For `->`, it is
  auto-dereferenced (or kept as-is for method calls — see below).
- If `base->ty` is `TY_CLASS`, the base is a value.

#### Step 2: Field lookup (fields always win)

Call `find_member(base->ty, method_name)`.  If a member is found, it is
field access — no method lookup occurs.  This guarantees backward
compatibility: existing `foo.field` code is never affected.

#### Step 3: Method lookup

If no member is found AND the next token is `(`:

1. Construct the function name:
   ```
   type_name = base->ty->name    (e.g. "CStrs")
   prefix = strip leading 'C'    (e.g. "Strs")
   func_name = prefix + method_name   (e.g. "StrsLen")
   ```
   The `C` is stripped only if the name starts with `C` followed by an
   uppercase letter.  Classes without the `C` prefix (e.g. `HtkCtl`)
   use their full name as the prefix.

2. Call `find_func(ps, func_name)`.  If NULL, emit an error.

3. Construct the receiver argument:
   - If `base->ty` is `TY_PTR`: pass `base` directly (already a pointer).
   - If `base->ty` is `TY_CLASS`: take the address — `&base` (creates
     an `ND_ADDR` node).  If `base` is an lvalue, this is valid.  If
     `base` is an rvalue (e.g. return value of a function), a temporary
     is introduced (see "rvalue handling" below).

4. Prepend the receiver to the argument list.

5. Call `make_call(ps, fn, args, 0, tok)` — the standard direct-call
   construction path.

#### Step 4: Continue

The result is a normal `ND_CALL` node.  The backends see nothing special.

### Calling convention summary

| Receiver type | `receiver.Method(args)` →        | First arg to function |
|--------------|------------------------------------|-----------------------|
| `CFoo` (value, lvalue) | `FooMethod(&receiver, args)` | pointer to receiver   |
| `CFoo` (value, rvalue) | temp = receiver; `FooMethod(&temp, args)` | pointer to temp |
| `CFoo *` (pointer) | `FooMethod(receiver, args)`  | the pointer itself    |
| `CFoo **` (pointer to pointer) | `FooMethod(*receiver, args)` | auto-deref'd pointer |

In all cases the function receives a pointer to the object.  This matches
the existing calling convention where the first parameter is always a
pointer to the class.

### Name construction algorithm

```
function make_method_name(class_name, method_name):
    if class_name starts with 'C' and len(class_name) > 1
       and class_name[1] is uppercase:
        prefix = class_name[1..]   // strip the C
    else:
        prefix = class_name
    return prefix + method_name
```

Examples:

| Class name     | Method  | Constructed function |
|---------------|---------|---------------------|
| `CStrs`       | `Len`   | `StrsLen`           |
| `CStrs`       | `Find`  | `StrsFind`          |
| `CStrBuf`     | `PutS`  | `StrBufPutS`        |
| `CList`       | `PushBack` | `ListPushBack`   |
| `CVec`        | `Push`  | `VecPush`           |
| `CThread`     | `Create`| `ThreadCreate`      |
| `CThread`     | `Join`  | `ThreadJoin`        |
| `CThreadMutex`| `Lock`  | `ThreadMutexLock`   |
| `CRegex`      | `Compile` | `RegexCompile`    |
| `CRegexCompiler` | `Emit` | `RegexCompileEmit` |
| `CHashTable`  | `Find`  | `HtFind`            |
| `HtkCtl`      | `Fire`  | `HtkCtlFire`        |
| `UiCtl`       | `Show`  | `UiCtlShow`         |
| `CSsl`        | `Read`  | `SslRead`           |

Note: `CHashTable` → `HtFind` (abbreviated prefix).  The heuristic
strips `C` → `HashTable`, but the actual function is `HtFind`, not
`HashTableFind`.  This is a **naming convention mismatch** — the
method-call syntax would look for `HashTableFind` and fail.  See
"Limitations" below.

### Rvalue handling

When the receiver is an rvalue (not an addressable lvalue), the compiler
must create a temporary:

```holyc
get_foo().Method(x)
// desugars to:
CFoo __tmp = get_foo();
FooMethod(&__tmp, x);
```

Implementation: if `base` is not an lvalue (check `is_lvalue()`), create
a `ND_EXPR_STMT` containing an assignment to a compiler-generated
temporary, then take the address of the temporary.

For the initial implementation, **rvalue receivers can be rejected** with
a clear error message: "cannot call method on rvalue; assign to a
temporary first".  This avoids the temporary-generation complexity and
can be added later.

### Chaining

If `Method()` returns a pointer to the same class, chaining works
naturally:

```holyc
list.PushBack(5).PushFront(6)
// desugars to:
ListPushBack(&list, 5);   // returns CList*
// then: ListPushBack(return_value, 6)
```

This works because `make_call()` sets `n->ty` to the function's return
type, and the postfix loop continues to the next `.`.

For `U0` returns, chaining is not possible (the result is void).  The
parser should error: "cannot chain on void return".

### Disambiguation rules

1. **Fields always win.** If `find_member()` succeeds, it is field
   access.  No method lookup occurs.

2. **Method only on `(`.** Method lookup only happens when the token
   after the name is `(`.  If `foo.Bar` and `Bar` is not a member, it
   is an error (no method lookup without parens).

3. **No fallback.** If `foo.Bar(x)` fails because `Bar` is not a member
   AND `StrBar` is not a function, the error message should list both
   failures:

   ```
   no member 'Bar' in class CFoo and no function 'StrBar()' found
   ```

## Implementation

### Parser changes (`parse.c`)

Modify the `.`/`->` branch in `postfix()` (line 1299).  The change is
~60 lines and touches only this one function.

```c
if (is_punct(ps, ".") || is_punct(ps, "->")) {
    ps->tk = ps->tk->next;
    Token *mt = ps->tk;
    reject_reserved_name(ps, mt, "member name", true);
    if (!is_lexical_name(mt)) {
        error_tok(ps->cc, mt, "expected member name");
    }
    Node *base = n;
    /* auto-deref pointers (see dotref.md) */
    if (base->ty->kind == TY_PTR && base->ty->base) {
        base = rvalize(n);
        Node *d = new_unary(ps, ND_DEREF, base, t);
        d->ty = base->ty->base;
        base = d;
    }
    if (base->ty->kind == TY_INT) {
        n = subint_access(ps, base, t);
        continue;
    }
    char *member_name = take_name(ps, "member name", true);
    if (base->ty->kind != TY_CLASS) {
        error_tok(ps->cc, t, "member access on a non-class value");
    }
    /* field lookup first */
    Member *m = find_member(base->ty, member_name);
    if (m) {
        Node *mn = new_node(ND_MEMBER, t);
        mn->lhs = base;
        mn->member_ref = m;
        mn->ty = m->ty;
        n = mn;
        continue;
    }
    /* not a field: try OO method call */
    if (eat(ps, "(")) {
        Type *ty = base->ty;
        char *prefix = ty->name && ty->name[0] == 'C'
            && ty->name[1] >= 'A' && ty->name[1] <= 'Z'
            ? ty->name + 1 : ty->name;
        char *fname = xasprintf(ps->cc, "%s%s", prefix, member_name);
        Obj *fn = find_func(ps, fname);
        if (!fn) {
            error_tok(ps->cc, mt,
                "no member '%s' in class %s "
                "and no function '%s()' found",
                member_name,
                ty->name ? ty->name : "?",
                fname);
        }
        /* receiver: pointer as-is, value as &receiver */
        Node *receiver = base;
        if (base->ty->kind != TY_PTR) {
            if (!is_lvalue(base)) {
                error_tok(ps->cc, t,
                    "cannot call method on rvalue; "
                    "assign to a temporary first");
            }
            receiver = new_unary(ps, ND_ADDR, rvalize(base), t);
            receiver->ty = ptr_to(base->ty);
        }
        Node *args = parse_args(ps);
        /* prepend receiver to arg list */
        if (args) {
            Node *tail = args;
            while (tail->next) tail = tail->next;
            tail->next = args;
            args = receiver;
        } else {
            args = receiver;
        }
        n = make_call(ps, fn, args, 0, t);
        continue;
    }
    error_tok(ps->cc, mt, "no member '%s' in class %s",
        member_name,
        ty->name ? ty->name : "?");
}
```

### What does NOT change

- **AST node types.** The result is a normal `ND_CALL`.  No new node
  kinds needed.
- **Backends.** `back_ll.c`, `back_c.c`, `back_js.c` see a standard
  `ND_CALL` with a direct `func` reference.  No changes.
- **Type system.** No new type kinds.  The receiver is typed as a
  pointer, same as any other function argument.
- **Formatter.** `fmt.c` doesn't parse expressions.  No changes.
- **Effect analysis.** `effects.c` propagates `can_throw` through the
  call graph.  A desugared method call is a normal call.  No changes.
- **Lexer.** `.` and `(` are already tokens.  No changes.

### Total lines changed

~60 lines in `parse.c`.  Optional: 3 lines in `aholyc.h` and 3 lines in
`aholyc.c` for the `-fno-oocall` flag.

## Limitations

### 1. Naming convention mismatches

The heuristic assumes `StripC(ClassName) + Method` matches the function
name.  This fails when:

- The prefix is abbreviated: `CHashTable` → functions use `Ht*`, not
  `HashTable*`.  `table.Find()` looks for `HashTableFind`, not `HtFind`.
- The prefix is a different word: `CAllocationManager` → functions use
  `Arena*`.  `manager.Alloc()` looks for `AllocationManagerAlloc`, not
  `ArenaAlloc`.
- Multiple classes share a prefix with different sub-words: `CJsonValue`
  and `CJsonDecoder` both have `Json*` functions, but `JsonValueAsI64`
  vs `JsonDecode` have different sub-words.

**Mitigation:** These classes can still use the traditional call syntax.
The method syntax is a convenience, not a requirement.  A future
`@method_prefix` annotation could override the heuristic (see "Future
work").

### 2. No overload resolution

HolyC has no function overloading.  If two functions have the same
constructed name (e.g. two different classes both produce `FooBar`),
`find_func()` returns the first match.  This is incorrect.

**Mitigation:** This cannot happen with well-named code because class
names are unique and the prefix is derived from the class name.  Two
different classes produce two different prefixes.  The only risk is if
someone defines `FooBar` for class `CFoo` and also defines an unrelated
`FooBar` function — but that is already a name collision in HolyC's flat
namespace.

### 3. `U0` return type

If the method returns `U0` (void), the result cannot be used in
expressions or chained.  This is standard HolyC behavior but may
surprise users who expect `list.Push(5).Push(6)` to work.

**Mitigation:** The parser already handles `U0` returns in `make_call()`.
Chaining on `U0` produces a type error downstream, which is the correct
behavior.

### 4. Method on inherited members

If class `CDog` inherits from `CAnimal`, and there is an `AnimalFeed`
function, can you write `dog.Feed()`?  Yes — `find_member()` walks the
parent chain, and the type name is `CDog`, so the constructed function
name is `DogFeed`, not `AnimalFeed`.

If the user wants `dog.Feed()` to call `AnimalFeed`, they must define a
`DogFeed` wrapper or use the traditional call syntax.

### 5. Pointer-to-pointer receivers

`CFoo **pp` → `pp.Method()` auto-derefs once to `CFoo *`, then passes
that pointer.  This is correct but may surprise users who expect `pp` to
be the receiver.

**Mitigation:** Document that method calls auto-deref one level.  For
double-pointer receivers, use the traditional call syntax.

## Alternatives considered

### 1. `:` operator (`foo:Method()`)

Use `:` instead of `.` for method calls.  Cleaner visual separation, no
ambiguity with field access.

**Verdict:** Rejected because `:` is already used in `case X:`,
`class A : B`, and (in standard C) the ternary operator.  While these
are not in expression position, the visual overlap hurts readability.
Overloading `.` is simpler.

### 2. Macro-based dispatch

```holyc
#define METHOD(Type, Name, ...) Type##Name(__VA_ARGS__)
```

**Verdict:** Fragile, no type safety, no IDE support, requires per-
function opt-in.  Worse than a compiler feature.

### 3. `#method` decorator

```holyc
#method StrsLen(CStrs *s) { ... }
```

**Verdict:** Requires explicit opt-in, adds syntax, doesn't solve the
call-site ergonomics without additional compiler support.  The method
syntax should work for all functions that follow the naming convention,
not just annotated ones.

### 4. Virtual dispatch / vtables

Add `virtual` methods to classes with runtime dispatch.

**Verdict:** Out of scope.  This RFC is about syntactic sugar for direct
calls, not dynamic dispatch.  HolyC has no vtable mechanism.

### 5. Don't do it

Keep `FooMethod(foo)` as the only way.

**Verdict:** The convention works but is verbose.  With 3,275 `->` calls
in the codebase, the method syntax would significantly improve
readability for library code.

## Future work

- **`@method_prefix` annotation.**  Allow classes to specify their
  function prefix explicitly:

  ```holyc
  /* @method_prefix(Ht) */
  class CHashTable { ... };
  ```

  This overrides the `StripC` heuristic and enables `table.Find()` to
  resolve to `HtFind`.

- **Rvalue temporaries.**  Automatically create temporaries for rvalue
  receivers, enabling `get_foo().Method()`.

- **Chaining on `U0`.**  Return `self` from methods that would otherwise
  return `U0`, enabling `list.Push(5).Push(6)`.  This requires a
  language-level `self` or `this` concept, which is out of scope.

## References

- `src/parse.c:1299–1336` — current `.`/`->` handling in `postfix()`
- `src/parse.c:908–983` — `make_call()` (direct call construction)
- `src/parse.c:986–1047` — `make_indirect_call()` (indirect call)
- `src/parse.c:1049–1072` — `parse_args()` (argument parsing)
- `src/parse.c:157–164` — `find_func()` (function name lookup)
- `src/parse.c:63–72` — `find_member()` (field lookup with inheritance)
- `src/parse.c:396–401` — `new_var_node()` (variable reference)
- `src/parse.c:449–457` — `rvalize()` (array-to-pointer decay)
- `src/aholyc.h:157–184` — `Node` struct (AST node)
- `src/aholyc.h:188–214` — `Obj` struct (function/variable symbol)
- `doc/language.md` — language specification
- [dotref.md](dotref.md) — related RFC for unified `.` operator
