# Pointer safety and resource contracts in aholyc

This is a design note, not a promise that every annotation below will be
implemented. Its purpose is to give aholyc a coherent direction for pointer
safety while keeping HolyC source readable and source-compatible with the
original compiler: every extension remains a comment hint.

```holyc
/* @nonnull */ U8 *Copy(/* @nonnull */ U8 *dst,
                        /* @nonnull */ U8 *src, I64 n);
```

An original HolyC compiler sees ordinary comments. aholyc may use them for
diagnostics, optimization, or both. `-fno-hints` makes all of them comments
again, so code that needs a safety guarantee must not rely on hints alone when
it also has to run under an implementation that ignores them.

## The distinctions matter

“Pointer safety” is not one property. These properties must stay separate:

| Property | What it proves | What it does **not** prove |
|---|---|---|
| nullability | whether an address can be zero | object lifetime, bounds, initialization |
| dereferenceability | a number of accessible bytes at this instant | ownership or future validity |
| bounds | an index/range is within a described region | that the region remains alive |
| ownership | who must release a resource | that every use is in bounds |
| borrowing | a value does not outlive its owner | thread safety or exclusivity |
| mutability / access | whether a function may read or write through it | aliasing or lifetime |
| provenance / aliasing | whether pointers refer to disjoint storage | nullability or bounds |

In particular, `@nonnull` means only “the address is not zero.” A non-zero
pointer can still be dangling, uninitialized, one-past-the-end, or invalid on
the current target. aholyc must never describe `@nonnull` as “valid pointer.”

## Status today

`@nonnull` is implemented for the outer pointer of variables, class members,
parameters, and pointer return values. Ordinary `T *` remains nullable.

```holyc
/* @nonnull */ U8 *MAlloc(I64 size);
U0 PutName(/* @nonnull */ U8 *name);

U0 Use(/* @nonnull */ CTask *task) {
  if (task == NULL)  // aholyc warns: always false
    return;
  task->except_ch = 1;
}
```

aholyc rejects a known null or a nullable pointer flowing into a non-null
assignment, parameter, or return. It recognizes addresses, string literals,
array decay, function addresses, and annotated function results as non-null.

The LLVM backend currently represents HolyC pointer values as `i64` at its
function ABI. It therefore emits `llvm.assume` for these facts rather than
LLVM's pointer-only `nonnull` signature attribute. A later ABI migration to
`ptr` signatures can emit `nonnull` and `noundef` directly.

## Nullability vocabulary

The source-level model should have three states, even if the first version
only exposes two annotations:

| State | Suggested spelling | Meaning |
|---|---|---|
| unknown / ordinary | `T *` | may be null; callers and dereferences need proof |
| non-null | `/* @nonnull */ T *` | address is never zero |
| explicitly nullable | `/* @nullable */ T *` | null is an intentional part of this API |

`@nullable` initially has the same representation as an ordinary pointer. It
is valuable documentation and makes API reviews explicit: a bare pointer is
legacy/unknown, while `@nullable` says that absence is a supported result or
argument. A strict project mode can require public pointer APIs to spell one
of `@nonnull` or `@nullable`.

### Optional parameters and nullable results

`@optional` is best treated as API intent layered on `@nullable`, not as a
third machine representation:

```holyc
U8 *FindUser(/* @optional */ U8 *name);
U0 Log(/* @optional */ U8 *prefix, /* @nonnull */ U8 *message);
```

It means a null argument/result is a normal, documented choice, normally
representing “not supplied” or “not found.” The checker should permit null at
the boundary but require a branch before dereference in the callee:

```holyc
if (prefix)
  Print("%s: ", prefix);
```

For parameters with defaults, use the existing HolyC default syntax for the
value and `@optional` to describe its semantics:

```holyc
U0 PrintLine(/* @optional */ U8 *prefix=NULL, /* @nonnull */ U8 *text);
```

`@optional` should not mean “the argument may be omitted from the call.” That
meaning already exists through `=default`; combining them would make calls
ambiguous.

### Is address zero a valid address?

This is distinct from nullable APIs. On hosted aholyc targets, zero is the
null sentinel and is not dereferenceable; the JavaScript backend explicitly
reserves address zero. Code that really maps or uses page zero needs a
target/ABI contract, not `@nullable`:

```holyc
// Future, target-specific and unsafe by nature:
// /* @null_address_valid */ U8 *PhysicalAddress(I64 address);
```

Such an annotation should be restricted to a module, function, or backend
configuration. It must never silently change the meaning of all pointers:
LLVM has a function-level `null_pointer_is_valid` concept, and applying it
globally would invalidate ordinary null-check reasoning. The JS backend must
reject it unless it gains a representation for page zero.

## Flow-sensitive null checking

The checker should track a pointer's state per control-flow path:

```holyc
U0 PrintIfPresent(U8 *s) {
  if (s) {
    PutS(s);              // `s` is non-null in this block
  }
  // `s` is nullable again here
}
```

It should understand `p`, `!p`, `p == NULL`, `p != 0`, short-circuit `&&` and
`||`, and assignments. A merge after an `if` keeps a fact only when both
incoming paths prove it. Loops need a conservative fixed point. `goto`, inline
assembly, calls through unknown function pointers, and writes through aliases
should invalidate facts rather than creating unsound proof.

Suggested diagnostics:

* Passing nullable to `@nonnull`, assigning it there, or returning it there:
  error in checked mode.
* Dereferencing nullable/unknown: warning first, error under
  `-fptr-safety=strict`.
* Checking `@nonnull` against null: warning; it is dead defensive code.
* Returning `NULL` from an `@nonnull` function: error.
* Falling off the end of an `@nonnull` result function: error unless all
  reachable paths return a proven non-null value.

Explicit casts must not forge a proof. A cast from `T *` to a non-null
declaration should remain nullable and fail at the checked boundary. If an
escape hatch is necessary, make it noisy:

```holyc
/* future builtin: documents an unchecked proof obligation */
U8 *q = AssumeNonNull(p);
```

`AssumeNonNull` should issue a warning in normal builds, be banned by a strict
mode, and lower to an LLVM assumption where applicable.

## Validity, bounds, and access

Nullability alone cannot make dereference safe. The next useful contracts
describe a borrowed region:

```holyc
U0 MemCpy(
  /* @nonnull @writeable @count=n */ U8 *dst,
  /* @nonnull @readable  @count=n */ U8 *src,
  I64 n);

I64 StrLen(/* @nonnull @readable @nul_terminated */ U8 *s);
```

Possible vocabulary:

| Hint | Proposed meaning |
|---|---|
| `@readable` / `@writeable` | function may read / write through the pointer |
| `@count=name` | region contains `name` elements of the pointee type |
| `@bytes=name` | region contains `name` bytes |
| `@nul_terminated` | a readable byte sequence eventually has a terminating zero |
| `@valid` | avoid this vague spelling; require a size/access contract instead |
| `@aligned=N` | pointer value is aligned to `N`, distinct from object-layout `@align` |

`@count` and `@bytes` should accept only a named parameter or a simple constant
initially. General expressions need a shared expression representation and are
harder to validate across declarations. For a function body, the checker can
prove `p[i]` only after proving `0 <= i < count`; it can also diagnose obvious
constant out-of-range indexes.

A later, more ergonomic representation is a class/slice pair rather than an
ever-growing annotation language:

```holyc
class CByteSlice { U8 *data; I64 len; };
```

Hints can make that convention recognized without changing its ABI:
`@slice(data,len)`.

## Ownership and release

Ownership answers who is responsible for releasing an allocation or resource.
It should be generic enough for `Free`, file handles, locks, and GUI objects,
not hard-coded to only heap pointers.

```holyc
/* @returns_owned @nonnull */ U8 *MAlloc(I64 n);
U0 Free(/* @takes */ U8 *p);

U0 Example() {
  /* @owned */ U8 *buf = MAlloc(128);
  Free(buf);             // ownership consumed
  // use or Free(buf) again: diagnostic
}
```

Suggested ownership contracts:

| Hint | Proposed meaning |
|---|---|
| `@owned` | local/field/return owns one release obligation |
| `@returns_owned` | successful return transfers a release obligation to caller |
| `@returns_borrowed=arg` | return borrows from a named argument or receiver |
| `@borrowed` | value is usable but does not own release responsibility |
| `@takes` | callee consumes ownership, even if it later fails/throws as specified |
| `@frees` | callee frees but does not necessarily model transfer; useful for C APIs |
| `@noescape` | callee does not retain the pointer beyond the call |
| `@nocapture` | callee does not store/return the pointer's provenance |
| `@noalias` | accessed storage is disjoint for the annotated call contract |

`@takes` needs precise exceptional behavior. A conservative first rule is:
the caller treats the value as moved immediately after the call. If an API
retains ownership on failure, use a separate result convention rather than an
ambiguous annotation.

Moving an `@owned` value should leave the source unusable:

```holyc
/* @owned */ U8 *a = MAlloc(32);
/* @owned */ U8 *b = a;  // move, not an aliasing copy
Free(b);
```

Copying an owning pointer must be rejected unless a `Retain`-style operation
creates an independently releasable reference. Assignment to a plain or
`@borrowed` pointer creates a borrow, not a second owner.

## Borrowing and lifetime

Borrowing needs a lexical first implementation before attempting Rust-like
general lifetime syntax:

```holyc
U8 *FirstByte(/* @borrowed @count=n */ U8 *data, I64 n);
```

The result should be known to borrow from `data` and must not escape the
owner's scope or outlive an ownership-consuming call. For ordinary locals, a
lexical rule catches the valuable cases:

* an `@borrowed` pointer may not be returned unless the function says
  `@returns_borrowed=...`;
* it may not be stored in a global, heap object, or longer-lived field;
* it may not be used after its owner is freed or moved;
* a function accepting `@noescape @borrowed` may use it during the call only.

Named lifetime regions can come later if real code requires them:

```holyc
// Future spelling; avoid implementing until lexical borrowing is useful.
// /* @borrow='a */ U8 *Find(/* @borrow='a */ U8 *data, I64 n);
```

Do not add lifetime syntax merely to imitate another language. aholyc should
first make common HolyC allocation patterns safer with a small, explainable
set of rules.

## Mutability, aliases, and concurrency

HolyC has raw mutable pointers, so mutability annotations should begin as
contracts rather than a new `const` system:

```holyc
I64 MemCmp(/* @readonly @count=n */ U8 *a,
           /* @readonly @count=n */ U8 *b, I64 n);
```

`@readonly` tells the checker that a function body must not write through that
parameter. `@writeonly` and `@readwrite` can follow when useful. These are
different from `@noalias`; read-only buffers can still alias.

Concurrency needs a separate family: `@guarded_by=lock`, `@atomic`, or
`@thread_local`-style declarations. They should not be smuggled into ownership
rules, because shared reference-counted ownership and exclusive mutable access
are different problems.

## Interop and function pointers

External C declarations have no automatically trustworthy contract. By
default, aholyc should treat unknown `extern` pointer parameters/results as
nullable, borrowed, and possibly capturing. Library headers can add hints
after auditing the real ABI:

```holyc
extern /* @returns_owned @nonnull */ U8 *LibraryAlloc(I64 n);
extern U0 LibraryUse(/* @nonnull @noescape */ U8 *data);
```

Function-pointer declarations retain their full call signature, including
parameter-level `@nonnull`, so indirect calls can enforce parameter contracts.
The pointer to the function and its parameters still need unambiguous,
separate nullability syntax:

```holyc
// Future outer-pointer contract syntax:
// /* @nonnull */ U0 (*callback)(/* @nonnull */ U8 *data);
```

Until the outer-pointer syntax is settled, the function pointer itself remains
nullable by default even when its parameter contracts are known.

## Backend mapping

When a fact is proven and the ABI supports it, backends can map it to native
attributes. These mappings are optimizations; aholyc's own checker remains the
source of diagnostics.

| aholyc contract | LLVM direction | C/Clang direction |
|---|---|---|
| `@nonnull` parameter/result | `nonnull`, normally with `noundef` | `nonnull`, `returns_nonnull` |
| `@count` / `@bytes` | `dereferenceable(N)` when `N` is proven | `access`/`nonnull` where supported |
| `@noescape` / `@nocapture` | `captures(none)` or appropriate capture set | `nocapture` where available |
| `@noalias` | `noalias` | `restrict` only when source semantics permit it |
| `@returns_owned` | possibly `noalias` on allocation-like results | `malloc`-style attribute where valid |
| valid zero address | `null_pointer_is_valid` at function scope | target-specific; no portable C equivalent |

These attributes are promises to optimizers. Emitting a stronger fact than the
checker proves can miscompile code, not merely produce a warning. In
particular, `nonnull` is not `dereferenceable`, and `noalias` is much stronger
than “the pointers are usually different.”

## Suggested implementation order

1. Finish nullability: flow-sensitive narrowing, dereference diagnostics,
   explicit `@nullable`, `@optional`, and all-path return checking.
2. Add pointer/result contracts to the internal representation and preserve
   them through direct calls, macros, declarations, and separate compilation.
3. Add lexical `@owned`, `@borrowed`, `@takes`, and `@returns_owned`; diagnose
   use-after-move, double release, and obvious leaks.
4. Add `@count`/`@bytes` plus simple index checking and runtime assertion
   insertion only behind an explicit safety mode.
5. Move LLVM pointer ABI boundaries from `i64` to `ptr` where compatible, then
   emit standard LLVM parameter/return attributes.
6. Consider advanced alias, lifetime, concurrency, and page-zero contracts
   only after the simpler contracts have real-world test coverage.

Every stage should be opt-in or warning-first for existing HolyC code. The
goal is to make low-level intent visible and mechanically checked, not to make
ordinary TempleOS-style programs impossible to compile.
