/* aholyc parser: HolyC grammar -> core AST.
 * Sugar (default args, implicit Print, switch, range comparisons, ++/--,
 * compound assignment) is lowered here so backends stay small.
 */
#include "aholyc.h"

/* ------------------------------------------------------------- type pool */

static const Type ty_u0_ = { .kind = TY_VOID, .size = 0, .align = 1 };
static const Type ty_i8_ = { .kind = TY_INT, .size = 1, .align = 1 };
static const Type ty_u8_ = { .kind = TY_INT, .size = 1, .align = 1, .is_unsigned = true };
static const Type ty_i16_ = { .kind = TY_INT, .size = 2, .align = 2 };
static const Type ty_u16_ = { .kind = TY_INT, .size = 2, .align = 2, .is_unsigned = true };
static const Type ty_i32_ = { .kind = TY_INT, .size = 4, .align = 4 };
static const Type ty_u32_ = { .kind = TY_INT, .size = 4, .align = 4, .is_unsigned = true };
static const Type ty_i64_ = { .kind = TY_INT, .size = 8, .align = 8 };
static const Type ty_u64_ = { .kind = TY_INT, .size = 8, .align = 8, .is_unsigned = true };
static const Type ty_f64_ = { .kind = TY_F64, .size = 8, .align = 8 };

/* Type links predate const-qualified AST types. These private aliases are
 * read-only; declaration hints always copy before modifying a primitive. */
static Type *const ty_u0 = (Type *)(const void *)&ty_u0_;
static Type *const ty_i8 = (Type *)(const void *)&ty_i8_;
static Type *const ty_u8 = (Type *)(const void *)&ty_u8_;
static Type *const ty_i16 = (Type *)(const void *)&ty_i16_;
static Type *const ty_u16 = (Type *)(const void *)&ty_u16_;
static Type *const ty_i32 = (Type *)(const void *)&ty_i32_;
static Type *const ty_u32 = (Type *)(const void *)&ty_u32_;
static Type *const ty_i64 = (Type *)(const void *)&ty_i64_;
static Type *const ty_u64 = (Type *)(const void *)&ty_u64_;
static Type *const ty_f64 = (Type *)(const void *)&ty_f64_;

static Type *new_type(Aholyc *cc, TypeKind k, int size, int align) {
	Type *t = xcalloc (cc, 1, sizeof(Type));
	t->kind = k;
	t->size = size;
	t->align = align;
	return t;
}

static Type *ptr_to(Aholyc *cc, Type *base) {
	Type *t = new_type (cc, TY_PTR, 8, 8);
	t->base = base;
	return t;
}

static Type *array_of(Aholyc *cc, Type *base, int len) {
	Type *t = new_type (cc, TY_ARRAY, base->size * len, base->align);
	t->base = base;
	t->array_len = len;
	return t;
}

static bool is_integer(Type *ty) { return ty->kind == TY_INT; }
static bool is_ptrish(Type *ty) { return ty->kind == TY_PTR || ty->kind == TY_ARRAY; }

static Member *find_member(Type *ty, char *name) {
	for (; ty; ty = ty->parent) {
		for (Member *m = ty->members; m; m = m->next) {
			if (!strcmp (m->name, name)) {
				return m;
			}
		}
	}
	return NULL;
}

/* --------------------------------------------------------- parser state */

typedef struct VarScope VarScope;
struct VarScope { VarScope *next; char *name; Obj *var; };

typedef struct Scope Scope;
struct Scope { Scope *next; VarScope *vars; };

typedef struct SwGroup SwGroup;

typedef struct ClassEnt ClassEnt;
struct ClassEnt { ClassEnt *next; char *name; Type *ty; };

typedef struct LabelRef LabelRef;
struct LabelRef { LabelRef *next; char *name; Token *tok; bool defined; };

typedef struct {
	Aholyc *cc;
	Token *tk;
	Scope *scope;
	Program *prog;
	Obj *cur_fn, *fn_locals, *funcs_tail, *globals_tail;
	char *break_label;
	ClassEnt *classes;
	LabelRef *fn_labels;
	int uid_counter, label_counter, class_dol_offset;
	bool in_class_body, align_hints;
} Parser;

/* '$$' inside a class/union body is the offset where the next member will
 * land (TempleOS class_dol_offset); outside it is the current code address. */

/* ------------------------------------------------------------- helpers */

static void enter_scope(Parser *ps) {
	Scope *s = xcalloc (ps->cc, 1, sizeof(Scope));
	s->next = ps->scope;
	ps->scope = s;
}

static void leave_scope(Parser *ps) {
	ps->scope = ps->scope->next;
}

static Obj *find_var(Parser *ps, const char *name) {
	for (Scope *s = ps->scope; s; s = s->next) {
		for (VarScope *v = s->vars; v; v = v->next) {
			if (!strcmp (v->name, name)) {
				return v->var;
			}
		}
	}
	/* A whole program's top-level code is its synthetic entry function.
	 * Its argc/argv pair is intentionally visible only there: putting these
	 * names in global scope would let ordinary functions capture parameters
	 * that do not belong to their frame. */
	if (ps->prog && ps->cur_fn == ps->prog->startup) {
		for (Obj *p = ps->prog->startup->params; p; p = p->next) {
			if (!strcmp (p->name, name)) {
				return p;
			}
		}
	}
	return NULL;
}

static Obj *find_func(Parser *ps, const char *name) {
	for (Obj *f = ps->prog->funcs; f; f = f->next) {
		if (!strcmp (f->name, name)) {
			return f;
		}
	}
	return NULL;
}

static Type *find_class(Parser *ps, const char *name) {
	for (ClassEnt *c = ps->classes; c; c = c->next) {
		if (!strcmp (c->name, name)) {
			return c->ty;
		}
	}
	return NULL;
}

static void scope_push(Parser *ps, char *name, Obj *var) {
	VarScope *v = xcalloc (ps->cc, 1, sizeof(VarScope));
	v->name = name;
	v->var = var;
	v->next = ps->scope->vars;
	ps->scope->vars = v;
}

static Obj *new_obj(Parser *ps, char *name, Type *ty) {
	Obj *o = xcalloc (ps->cc, 1, sizeof(Obj));
	o->name = name;
	o->ty = ty;
	o->uid = ps->uid_counter++;
	return o;
}

static Obj *new_local(Parser *ps, char *name, Type *ty) {
	Obj *o = new_obj (ps, name, ty);
	o->next = ps->fn_locals;
	ps->fn_locals = o;
	scope_push (ps, name, o);
	return o;
}

static Obj *new_temp(Parser *ps, Type *ty) {
	char *name = xasprintf (ps->cc, "tmp%d", ps->uid_counter);
	Obj *o = new_obj (ps, name, ty);
	o->next = ps->fn_locals;
	ps->fn_locals = o;
	/* not in scope: invisible to source code */
	return o;
}

static Obj *new_global(Parser *ps, char *name, Type *ty) {
	Obj *o = new_obj (ps, name, ty);
	o->is_global = true;
	o->is_static_dur = true;
	if (ps->globals_tail) {
		ps->globals_tail->next = o;
	} else {
		ps->prog->globals = o;
	}
	ps->globals_tail = o;
	scope_push (ps, name, o);
	return o;
}

static char *new_label(Parser *ps, const char *hint) {
	return xasprintf (ps->cc, ".%s%d", hint, ps->label_counter++);
}

/* token cursor */
static bool is_punct(Parser *ps, const char *s) {
	return ps->tk->kind == TK_PUNCT && !strcmp (ps->tk->str, s);
}

static bool is_kw(Parser *ps, const char *s) {
	return ps->tk->kind == TK_ID && !strcmp (ps->tk->str, s);
}

static bool eat(Parser *ps, const char *s) {
	if ((ps->tk->kind == TK_PUNCT || ps->tk->kind == TK_ID) && ps->tk->str && !strcmp (ps->tk->str, s)) {
		ps->tk = ps->tk->next;
		return true;
	}
	return false;
}

static void expect(Parser *ps, const char *s) {
	if (!eat (ps, s)) {
		error_tok (ps->cc, ps->tk, "expected '%s'", s);
	}
}

static void collect_hints(Parser *ps, Token *t, Token **bits, Token **func, Token **align) {
	if (t && t->hint_bits) {
		if (*bits) {
			error_tok (ps->cc, t, "duplicate @bits hint on declaration");
		}
		*bits = t;
	}
	if (t && (t->hints & (HINT_INLINE | HINT_NOINLINE))) {
		if (*func) {
			error_tok (ps->cc, t, "duplicate inline hint on declaration");
		}
		*func = t;
	}
	if (t && t->hint_align) {
		if (*align) {
			error_tok (ps->cc, t, "duplicate @align hint on declaration");
		}
		*align = t;
	}
}

static void reject_func_hint(Parser *ps, Token *t) {
	if (t) {
		error_tok (ps->cc, t, "inline hints apply only to function declarations");
	}
}

static void collect_bits_hint(Parser *ps, Token *t, Token **bits) {
	Token *func = NULL;
	Token *align = NULL;
	collect_hints (ps, t, bits, &func, &align);
	reject_func_hint (ps, func);
	if (align) {
		error_tok (ps->cc, align, "@align applies only to classes, fields, and local variables");
	}
}

static int align_up(int n, int a) {
	return (n + a - 1) & -a;
}

static int hint_alignment(Parser *ps, Type *ty, Token *hint) {
	return !hint || !ps->align_hints? 0:
		hint->hint_align < 0? ty->align: hint->hint_align;
}

/* Builtin types are shared, so attach declaration metadata to a shallow copy. */
static Type *hinted_type(Parser *ps, Type *ty, Token *hint) {
	if (!hint) {
		return ty;
	}
	if (!is_integer (ty)) {
		error_tok (ps->cc, hint, "@bits requires an integer declaration");
	}
	int bits = hint->hint_bits;
	if (bits > ty->size * 8) {
		error_tok (ps->cc, hint, "@bits=%d exceeds the declared %d-bit integer width",
			bits, ty->size * 8);
	}
	Type *t = xmalloc (ps->cc, sizeof(*t));
	*t = *ty;
	t->bits = bits;
	return t;
}

/* ------------------------------------------------------------ AST nodes */

static Node *new_node(NodeKind kind, Token *tok) {
	Node *n = xcalloc (tok->cc, 1, sizeof(Node));
	n->kind = kind;
	n->tok = tok;
	return n;
}

static Node *new_num(int64_t v, Token *tok) {
	Node *n = new_node (ND_NUM, tok);
	n->ival = v;
	n->ty = ty_i64;
	return n;
}

static Node *new_fnum(double v, Token *tok) {
	Node *n = new_node (ND_FNUM, tok);
	n->fval = v;
	n->ty = ty_f64;
	return n;
}

static Node *new_var_node(Obj *var, Token *tok) {
	Node *n = new_node (ND_VAR, tok);
	n->var = var;
	n->ty = var->ty;
	return n;
}

static Node *new_cast(Node *expr, Type *ty) {
	if (expr->ty == ty) {
		return expr;
	}
	Node *n = new_node (ND_CAST, expr->tok);
	n->lhs = expr;
	n->ty = ty;
	return n;
}

/* value type after loading: everything widens to 64-bit */
static Type *value_type(Aholyc *cc, Type *ty) {
	if (ty->kind == TY_INT) {
		return ty->is_unsigned? ty_u64: ty_i64;
	}
	if (ty->kind == TY_ARRAY) {
		return ptr_to (cc, ty->base);
	}
	return ty;
}

/* decay arrays, keep class values as-is */
static Node *rvalize(Node *n) {
	if (n->ty && n->ty->kind == TY_ARRAY) {
		Node *a = new_node (ND_ADDR, n->tok);
		a->lhs = n;
		a->ty = ptr_to (n->tok->cc, n->ty->base);
		return a;
	}
	return n;
}

static Node *new_binary(Parser *ps, NodeKind kind, Node *lhs, Node *rhs, Token *tok);

/* convert to boolean context i64 */
static Node *to_bool(Parser *ps, Node *n) {
	if (n->ty->kind == TY_F64) {
		return new_binary (ps, ND_NE, n, new_fnum (0.0, n->tok), n->tok);
	}
	return n;
}

static Node *to_f64(Node *n) {
	return n->ty->kind == TY_F64? n: new_cast (n, ty_f64);
}

static Node *to_int(Node *n) {
	if (n->ty->kind == TY_F64) {
		return new_cast (n, ty_i64);
	}
	return n;
}

static Node *new_binary(Parser *ps, NodeKind kind, Node *lhs, Node *rhs, Token *tok) {
	lhs = rvalize (lhs);
	rhs = rvalize (rhs);
	Node *n = new_node (kind, tok);
	switch (kind) {
	case ND_ADD:
	case ND_SUB:
		if (is_ptrish (lhs->ty) || is_ptrish (rhs->ty)) {
			if (is_ptrish (lhs->ty) && is_ptrish (rhs->ty)) {
				/* ptr - ptr: element difference (C semantics) */
				n->ty = ty_i64;
			} else {
				if (is_ptrish (rhs->ty)) { /* int + ptr */
					Node *t = lhs; lhs = rhs; rhs = t;
				}
				rhs = to_int (rhs);
				n->ty = lhs->ty;
			}
			n->lhs = lhs;
			n->rhs = rhs;
			return n;
		}
		/* fall through: plain numeric add/sub */
		/* FALLTHRU */
	case ND_MUL:
	case ND_DIV:
		if (lhs->ty->kind == TY_F64 || rhs->ty->kind == TY_F64) {
			lhs = to_f64 (lhs);
			rhs = to_f64 (rhs);
			n->ty = ty_f64;
		} else {
			n->ty = (value_type (ps->cc, lhs->ty)->is_unsigned ||
			         value_type (ps->cc, rhs->ty)->is_unsigned)? ty_u64: ty_i64;
		}
		break;
	case ND_MOD:
	case ND_AND:
	case ND_OR:
	case ND_XOR:
	case ND_SHL:
	case ND_SHR:
		lhs = to_int (lhs);
		rhs = to_int (rhs);
		n->ty = (value_type (ps->cc, lhs->ty)->is_unsigned ||
		         value_type (ps->cc, rhs->ty)->is_unsigned)? ty_u64: ty_i64;
		break;
	case ND_POW:
		lhs = to_f64 (lhs);
		rhs = to_f64 (rhs);
		n->ty = ty_f64;
		break;
	case ND_EQ:
	case ND_NE:
	case ND_LT:
	case ND_LE:
		if (lhs->ty->kind == TY_F64 || rhs->ty->kind == TY_F64) {
			lhs = to_f64 (lhs);
			rhs = to_f64 (rhs);
		}
		n->ty = ty_i64;
		break;
	case ND_LOGAND:
	case ND_LOGOR:
	case ND_LOGXOR:
		lhs = to_bool (ps, lhs);
		rhs = to_bool (ps, rhs);
		n->ty = ty_i64;
		break;
	case ND_COMMA:
		n->ty = rhs->ty;
		break;
	default:
		n->ty = ty_i64;
		break;
	}
	n->lhs = lhs;
	n->rhs = rhs;
	return n;
}

static Node *new_unary(Parser *ps, NodeKind kind, Node *lhs, Token *tok) {
	Node *n = new_node (kind, tok);
	n->lhs = lhs;
	if (kind == ND_ADDR && lhs->kind == ND_VAR) {
		lhs->var->address_taken = true;
	}
	switch (kind) {
	case ND_NEG:
		n->ty = lhs->ty->kind == TY_F64? ty_f64: ty_i64;
		break;
	case ND_NOT:
		n->lhs = to_bool (ps, rvalize (lhs));
		n->ty = ty_i64;
		break;
	case ND_BITNOT:
		n->lhs = to_int (rvalize (lhs));
		n->ty = ty_i64;
		break;
	default:
		n->ty = ty_i64;
		break;
	}
	return n;
}

static bool is_lvalue(Node *n) {
	return n->kind == ND_VAR || n->kind == ND_DEREF || n->kind == ND_MEMBER;
}

static Node *new_assign(Parser *ps, Node *lhs, Node *rhs, Token *tok) {
	if (!is_lvalue (lhs)) {
		error_tok (ps->cc, tok, "not an assignable expression");
	}
	if (lhs->ty->kind == TY_ARRAY) {
		error_tok (ps->cc, tok, "cannot assign to an array");
	}
	rhs = rvalize (rhs);
	/* implicit conversion to stored type */
	if (lhs->ty->kind == TY_F64 && rhs->ty->kind != TY_F64) {
		rhs = new_cast (rhs, ty_f64);
	} else if (lhs->ty->kind == TY_INT && rhs->ty->kind == TY_F64) {
		rhs = new_cast (rhs, ty_i64);
	}
	Node *n = new_node (ND_ASSIGN, tok);
	n->lhs = lhs;
	n->rhs = rhs;
	n->ty = value_type (ps->cc, lhs->ty);
	return n;
}

/* ------------------------------------------------------------ type names */

static Type *builtin_type(const char *s) {
	if (!strcmp (s, "U0")) return ty_u0;
	if (!strcmp (s, "I8")) return ty_i8;
	if (!strcmp (s, "U8")) return ty_u8;
	if (!strcmp (s, "I16")) return ty_i16;
	if (!strcmp (s, "U16")) return ty_u16;
	if (!strcmp (s, "I32")) return ty_i32;
	if (!strcmp (s, "U32")) return ty_u32;
	if (!strcmp (s, "I64")) return ty_i64;
	if (!strcmp (s, "U64")) return ty_u64;
	if (!strcmp (s, "F64")) return ty_f64;
	return NULL;
}

static bool is_type_start(Parser *ps, Token *t) {
	if (t->kind != TK_ID) {
		return false;
	}
	return builtin_type (t->str) || find_class (ps, t->str);
}

/* parse base type + leading stars */
static Type *parse_typespec(Parser *ps) {
	Type *ty = builtin_type (ps->tk->str);
	if (!ty) {
		ty = find_class (ps, ps->tk->str);
	}
	if (!ty) {
		error_tok (ps->cc, ps->tk, "unknown type '%s'", ps->tk->str);
	}
	ps->tk = ps->tk->next;
	while (is_punct (ps, "*")) {
		ps->tk = ps->tk->next;
		ty = ptr_to (ps->cc, ty);
	}
	return ty;
}

/* --------------------------------------------------------- const eval */

static int64_t eval_const(Parser *ps, Node *n) {
	switch (n->kind) {
	case ND_NUM: return n->ival;
	case ND_FNUM: return (int64_t)n->fval;
	case ND_NEG: return -eval_const (ps, n->lhs);
	case ND_BITNOT: return ~eval_const (ps, n->lhs);
	case ND_NOT: return !eval_const (ps, n->lhs);
	case ND_CAST: return eval_const (ps, n->lhs);
	case ND_ADD: return eval_const (ps, n->lhs) + eval_const (ps, n->rhs);
	case ND_SUB: return eval_const (ps, n->lhs) - eval_const (ps, n->rhs);
	case ND_MUL: return eval_const (ps, n->lhs) * eval_const (ps, n->rhs);
	case ND_DIV: {
		int64_t d = eval_const (ps, n->rhs);
		if (!d) error_tok (ps->cc, n->tok, "division by zero in constant");
		return eval_const (ps, n->lhs) / d;
	}
	case ND_MOD: {
		int64_t d = eval_const (ps, n->rhs);
		if (!d) error_tok (ps->cc, n->tok, "division by zero in constant");
		return eval_const (ps, n->lhs) % d;
	}
	case ND_AND: return eval_const (ps, n->lhs) & eval_const (ps, n->rhs);
	case ND_OR: return eval_const (ps, n->lhs) | eval_const (ps, n->rhs);
	case ND_XOR: return eval_const (ps, n->lhs) ^ eval_const (ps, n->rhs);
	case ND_SHL: return eval_const (ps, n->lhs) << (eval_const (ps, n->rhs) & 63);
	case ND_SHR: {
		Type *t = value_type (ps->cc, n->lhs->ty);
		if (t->is_unsigned) {
			return (int64_t)((uint64_t)eval_const (ps, n->lhs) >> (eval_const (ps, n->rhs) & 63));
		}
		return eval_const (ps, n->lhs) >> (eval_const (ps, n->rhs) & 63);
	}
	case ND_EQ: return eval_const (ps, n->lhs) == eval_const (ps, n->rhs);
	case ND_NE: return eval_const (ps, n->lhs) != eval_const (ps, n->rhs);
	case ND_LT: return eval_const (ps, n->lhs) < eval_const (ps, n->rhs);
	case ND_LE: return eval_const (ps, n->lhs) <= eval_const (ps, n->rhs);
	default:
		error_tok (ps->cc, n->tok, "not a constant expression");
		return 0;
	}
}

/* ---------------------------------------------------------- expressions */

static Node *expr(Parser *ps);        /* assignment level */
static Node *comma_expr(Parser *ps);
static Node *unary(Parser *ps);
static Node *stmt(Parser *ps);
static Node *block_stmt(Parser *ps);

static Node *new_str_node(Parser *ps, char *data, int len, Token *tok) {
	Node *n = new_node (ND_STR, tok);
	StrLit *s = xcalloc (ps->cc, 1, sizeof(StrLit));
	s->data = data;
	s->len = len;
	s->id = ps->prog->nstrings++;
	s->next = ps->prog->strings;
	ps->prog->strings = s;
	n->str = data;
	n->str_len = len;
	n->str_id = s->id;
	n->ty = ptr_to (ps->cc, ty_u8);
	return n;
}

static Node *make_call(Parser *ps, Obj *fn, Node *args, int nargs, Token *tok);

/* sentinel default for `=lastclass` params, resolved per call site */
static const Node nd_lastclass_;
static Node *const nd_lastclass = (Node *)(const void *)&nd_lastclass_;

/* HolyC name of a type with pointer/array levels stripped (for lastclass) */
static const char *holyc_type_name(Type *ty) {
	while (ty->kind == TY_PTR || ty->kind == TY_ARRAY) {
		ty = ty->base;
	}
	switch (ty->kind) {
	case TY_CLASS: return ty->name;
	case TY_F64: return "F64";
	case TY_VOID: return "U0";
	case TY_INT: {
		static const char *const names[2][4] = {
			{ "I8", "I16", "I32", "I64" },
			{ "U8", "U16", "U32", "U64" },
		};
		int i = ty->size == 1? 0: ty->size == 2? 1: ty->size == 4? 2: 3;
		return names[ty->is_unsigned? 1: 0][i];
	}
	default: return "U0";
	}
}

/* Build a direct call to a runtime/prelude function by name. */
static Node *call_named(Parser *ps, const char *name, Node *args, int nargs, Token *tok) {
	Obj *fn = find_func (ps, name);
	if (!fn) {
		error_tok (ps->cc, tok, "runtime function '%s' is not declared (missing prelude?)", name);
	}
	return make_call (ps, fn, args, nargs, tok);
}

/* Fill default arguments, verify count, insert conversions. args is the
 * chain of provided args, NULL nodes mark holes from `f(,x)`. */
static Node *make_call(Parser *ps, Obj *fn, Node *args, int nargs, Token *tok) {
	Node *n = new_node (ND_CALL, tok);
	n->func = fn;
	n->ty = value_type (ps->cc, fn->ty->base? fn->ty->base: ty_i64);
	/* collect into array for easy manipulation */
	Node *argv[256];
	int i, argc = 0;
	for (Node *a = args; a; a = a->next) {
		if (argc >= 256) {
			error_tok (ps->cc, tok, "too many arguments");
		}
		argv[argc++] = a;
	}
	(void)nargs;
	if (!fn->is_variadic && argc > fn->nparams) {
		error_tok (ps->cc, tok, "too many arguments to %s() (takes %d)", fn->name, fn->nparams);
	}
	int nfixed = fn->nparams < argc? fn->nparams: argc;
	Obj *p = fn->params;
	Type *prev_ty = NULL;
	for (i = 0; i < fn->nparams; i++, p = p->next) {
		Node *a = i < argc? argv[i]: NULL;
		if (a && a->kind == ND_NOP) { /* hole */
			a = NULL;
		}
		if (!a) {
			if (!fn->defaults || !fn->defaults[i]) {
				error_tok (ps->cc, tok, "missing argument %d in call to %s() and no default", i + 1, fn->name);
			}
			a = fn->defaults[i];
			if (a == nd_lastclass) {
				if (!prev_ty) {
					error_tok (ps->cc, tok, "lastclass argument %d in call to %s() has no previous argument", i + 1, fn->name);
				}
				const char *nm = holyc_type_name (prev_ty);
				a = new_str_node (ps, xstrdup (ps->cc, nm), strlen (nm), tok);
			}
		}
		a = rvalize (a);
		prev_ty = a->ty; /* lastclass sees the arg's own type, pre-conversion */
		/* convert to param type */
		if (p->ty->kind == TY_F64 && a->ty->kind != TY_F64) {
			a = new_cast (a, ty_f64);
		} else if (p->ty->kind != TY_F64 && p->ty->kind != TY_CLASS && a->ty->kind == TY_F64) {
			a = new_cast (a, ty_i64);
		}
		argv[i] = a;
	}
	nfixed = fn->nparams;
	/* variadic extras keep their own types (F64 slots bit-copied) */
	for (i = fn->nparams; i < argc; i++) {
		if (argv[i]->kind == ND_NOP) {
			error_tok (ps->cc, tok, "empty variadic argument");
		}
		argv[i] = rvalize (argv[i]);
	}
	int total = fn->is_variadic? argc: fn->nparams;
	if (total < fn->nparams) {
		total = fn->nparams;
	}
	Node head = {0};
	Node *cur = &head;
	for (i = 0; i < total; i++) {
		/* shallow-clone: default exprs are shared between call sites, so
		 * never relink the original nodes' next pointers */
		Node *c = xmalloc (ps->cc, sizeof(Node));
		*c = *argv[i];
		c->next = NULL;
		cur->next = c;
		cur = c;
	}
	n->args = head.next;
	n->nfixed = nfixed;
	return n;
}

/* indirect call through pointer value */
static Node *make_indirect_call(Parser *ps, Node *callee, Node *args, Token *tok) {
	Node *n = new_node (ND_CALL, tok);
	n->lhs = callee;
	Type *fnty = NULL;
	if (callee->ty->kind == TY_PTR && callee->ty->base && callee->ty->base->kind == TY_FUNC) {
		fnty = callee->ty->base;
	}
	n->ty = fnty && fnty->base? value_type (ps->cc, fnty->base): ty_i64;
	for (Node *a = args; a; a = a->next) {
		if (a->kind == ND_NOP) {
			error_tok (ps->cc, tok, "default arguments require a direct call");
		}
	}
	n->args = args;
	int cnt = 0;
	for (Node *a = args; a; a = a->next) cnt++;
	n->nfixed = cnt;
	return n;
}

static Node *parse_args(Parser *ps) {
	/* returns chain; holes become ND_NOP nodes */
	Node head = {0};
	Node *cur = &head;
	bool first = true;
	while (!is_punct (ps, ")")) {
		if (!first) {
			expect (ps, ",");
		}
		first = false;
		if (is_punct (ps, ",") || is_punct (ps, ")")) {
			Node *hole = new_node (ND_NOP, ps->tk);
			hole->ty = ty_i64;
			cur->next = hole;
			cur = hole;
			continue;
		}
		Node *a = rvalize (expr (ps));
		cur->next = a;
		cur = a;
	}
	expect (ps, ")");
	return head.next;
}

static Node *primary(Parser *ps) {
	Token *t = ps->tk;
	if (eat (ps, "(")) {
		Node *n = comma_expr (ps);
		expect (ps, ")");
		return n;
	}
	if (t->kind == TK_NUM) {
		ps->tk = ps->tk->next;
		return new_num (t->ival, t);
	}
	if (t->kind == TK_CHR) {
		ps->tk = ps->tk->next;
		return new_num (t->ival, t);
	}
	if (t->kind == TK_FNUM) {
		ps->tk = ps->tk->next;
		return new_fnum (t->fval, t);
	}
	if (t->kind == TK_STR) {
		/* concat adjacent strings */
		int len = t->len;
		Token *q = t->next;
		while (q->kind == TK_STR) {
			len += q->len;
			q = q->next;
		}
		char *buf = xmalloc (ps->cc, len + 1);
		int off = 0;
		for (Token *s = t; s != q; s = s->next) {
			memcpy (buf + off, s->str, s->len);
			off += s->len;
		}
		buf[len] = 0;
		ps->tk = q;
		return new_str_node (ps, buf, len, t);
	}
	if (is_kw (ps, "sizeof")) {
		ps->tk = ps->tk->next;
		bool paren = eat (ps, "(");
		Node *n;
		if (paren && is_type_start (ps, ps->tk)) {
			Type *ty = parse_typespec (ps);
			n = new_num (ty->size, t);
		} else {
			Node *e = paren? comma_expr (ps): unary (ps);
			n = new_num (e->ty->size, t);
		}
		if (paren) {
			expect (ps, ")");
		}
		return n;
	}
	if (is_kw (ps, "offset")) {
		ps->tk = ps->tk->next;
		expect (ps, "(");
		Type *cls = is_type_start (ps, ps->tk)? parse_typespec (ps): NULL;
		if (!cls || cls->kind != TY_CLASS) {
			error_tok (ps->cc, t, "offset(Class.member) expects a class name");
		}
		expect (ps, ".");
		if (ps->tk->kind != TK_ID) {
			error_tok (ps->cc, ps->tk, "expected member name");
		}
		Member *m = find_member (cls, ps->tk->str);
		if (!m) {
			error_tok (ps->cc, ps->tk, "no member '%s' in class %s", ps->tk->str, cls->name);
		}
		ps->tk = ps->tk->next;
		expect (ps, ")");
		return new_num (m->offset, t);
	}
	if (is_punct (ps, "$$")) {
		ps->tk = ps->tk->next;
		if (ps->in_class_body) {
			return new_num (ps->class_dol_offset, t);
		}
		/* current address in the generated code (TempleOS RIP) */
		Obj *fn = find_func (ps, "__hc_rip");
		if (!fn) {
			error_tok (ps->cc, t, "'$$' needs the runtime prelude");
		}
		return make_call (ps, fn, NULL, 0, t);
	}
	if (t->kind == TK_ID) {
		Obj *var = find_var (ps, t->str);
		if (var) {
			ps->tk = ps->tk->next;
			return new_var_node (var, t);
		}
		Obj *fn = find_func (ps, t->str);
		if (fn) {
			ps->tk = ps->tk->next;
			if (eat (ps, "(")) {
				Node *args = parse_args (ps);
				return make_call (ps, fn, args, 0, t);
			}
			/* paren-less call: Dir; Ret = F; etc. */
			return make_call (ps, fn, NULL, 0, t);
		}
		error_tok (ps->cc, t, "undefined symbol '%s'", t->str);
	}
	error_tok (ps->cc, t, "expected an expression");
	return NULL;
}

/* lower `lval OP= x` and ++/-- via pointer temp when lval is complex */
static Node *lval_addr_temp(Parser *ps, Node *lval, Node **out_deref, Token *t) {
	if (lval->kind == ND_VAR) {
		*out_deref = lval;
		return NULL; /* no setup needed */
	}
	Obj *tmp = new_temp (ps, ptr_to (ps->cc, lval->ty));
	Node *addr = new_unary (ps, ND_ADDR, lval, t);
	addr->ty = ptr_to (ps->cc, lval->ty);
	Node *setup = new_assign (ps, new_var_node (tmp, t), addr, t);
	Node *deref = new_unary (ps, ND_DEREF, new_var_node (tmp, t), t);
	deref->ty = lval->ty;
	*out_deref = deref;
	return setup;
}

static Node *incdec(Parser *ps, Node *lval, int delta, bool post, Token *t) {
	if (!is_lvalue (lval)) {
		error_tok (ps->cc, t, "++/-- needs an lvalue");
	}
	Node *place, *setup = lval_addr_temp (ps, lval, &place, t);
	Node *one = new_num (delta, t);
	Node *val;
	if (post) {
		/* (old = place, place = old + 1, old) */
		Obj *old = new_temp (ps, value_type (ps->cc, place->ty));
		Node *save = new_assign (ps, new_var_node (old, t), place, t);
		Node *upd = new_assign (ps, place, new_binary (ps, ND_ADD, new_var_node (old, t), one, t), t);
		val = new_binary (ps, ND_COMMA, save, new_binary (ps, ND_COMMA, upd, new_var_node (old, t), t), t);
	} else {
		val = new_assign (ps, place, new_binary (ps, ND_ADD, place, one, t), t);
	}
	if (setup) {
		val = new_binary (ps, ND_COMMA, setup, val, t);
	}
	return val;
}

static Type *subint_view_type(const char *name) {
	if (!strcmp (name, "i8")) return ty_i8;
	if (!strcmp (name, "u8")) return ty_u8;
	if (!strcmp (name, "i16")) return ty_i16;
	if (!strcmp (name, "u16")) return ty_u16;
	if (!strcmp (name, "i32")) return ty_i32;
	if (!strcmp (name, "u32")) return ty_u32;
	return NULL;
}

/* TempleOS sub-int access (doc/subint.md): an integer lvalue doubles as a
 * little-endian array of any strictly smaller int, so q.u8[5] reads byte 5
 * of q, q.u8[0] = x stores one byte, and views chain: q.i32[1].u8[2].
 * Lowered to *(view(*)[n])&base so the regular subscript, assignment and
 * decay machinery does the rest. */
static Node *subint_access(Parser *ps, Node *base, Token *t) {
	Type *view = subint_view_type (ps->tk->str);
	if (!view) {
		error_tok (ps->cc, ps->tk, "no member '%s' in an integer", ps->tk->str);
	}
	if (view->size >= base->ty->size) {
		error_tok (ps->cc, ps->tk, "sub-int view '%s' needs a wider int than %s",
			ps->tk->str, base->ty->size == 1? "a byte":
			base->ty->size == 2? "U16": "U32");
	}
	if (!is_lvalue (base)) {
		error_tok (ps->cc, t, "sub-int access needs an addressable value");
	}
	/* narrow params live sign-extended in a full 64-bit slot; a store
	 * through a view would leave the slot badly extended */
	if (base->kind == ND_VAR && base->var->is_param && base->ty->size < 8) {
		error_tok (ps->cc, t, "sub-int access on a narrow parameter; copy it to a local");
	}
	Type *arr = array_of (ps->cc, view, base->ty->size / view->size);
	Node *a = new_unary (ps, ND_ADDR, base, t);
	a->ty = ptr_to (ps->cc, base->ty);
	Node *d = new_unary (ps, ND_DEREF,
		new_cast (a, ptr_to (ps->cc, arr)), t);
	d->ty = arr;
	ps->tk = ps->tk->next;
	return d;
}

static Node *postfix(Parser *ps) {
	Node *n = primary (ps);
	for (;;) {
		Token *t = ps->tk;
		if (is_punct (ps, "(")) {
			/* postfix cast or indirect call */
			if (is_type_start (ps, ps->tk->next)) {
				ps->tk = ps->tk->next;
				Type *ty = parse_typespec (ps);
				expect (ps, ")");
				n = new_cast (rvalize (n), ty);
				continue;
			}
			ps->tk = ps->tk->next;
			Node *args = parse_args (ps);
			n = make_indirect_call (ps, rvalize (n), args, t);
			continue;
		}
		if (eat (ps, "[")) {
			Node *idx = comma_expr (ps);
			expect (ps, "]");
			Node *sum = new_binary (ps, ND_ADD, n, idx, t);
			if (!is_ptrish (sum->ty) && sum->ty->kind != TY_PTR) {
				error_tok (ps->cc, t, "subscript on a non-pointer");
			}
			Node *d = new_unary (ps, ND_DEREF, sum, t);
			if (sum->ty->kind != TY_PTR || !sum->ty->base) {
				error_tok (ps->cc, t, "cannot index this expression");
			}
			d->ty = sum->ty->base;
			n = d;
			continue;
		}
		if (is_punct (ps, ".") || is_punct (ps, "->")) {
			bool arrow = is_punct (ps, "->");
			ps->tk = ps->tk->next;
			if (ps->tk->kind != TK_ID) {
				error_tok (ps->cc, ps->tk, "expected member name");
			}
			Node *base = n;
			if (arrow) {
				base = rvalize (n);
				if (base->ty->kind != TY_PTR || !base->ty->base) {
					error_tok (ps->cc, t, "'->' on a non-pointer");
				}
				Node *d = new_unary (ps, ND_DEREF, base, t);
				d->ty = base->ty->base;
				base = d;
			}
			if (base->ty->kind == TY_INT) {
				n = subint_access (ps, base, t);
				continue;
			}
			if (base->ty->kind != TY_CLASS) {
				error_tok (ps->cc, t, "member access on a non-class value");
			}
			Member *m = find_member (base->ty, ps->tk->str);
			if (!m) {
				error_tok (ps->cc, ps->tk, "no member '%s' in class %s", ps->tk->str,
					base->ty->name? base->ty->name: "?");
			}
			Node *mn = new_node (ND_MEMBER, t);
			mn->lhs = base;
			mn->member_ref = m;
			mn->ty = m->ty;
			ps->tk = ps->tk->next;
			n = mn;
			continue;
		}
		if (is_punct (ps, "++") || is_punct (ps, "--")) {
			int d = is_punct (ps, "++")? 1: -1;
			ps->tk = ps->tk->next;
			n = incdec (ps, n, d, true, t);
			continue;
		}
		break;
	}
	return n;
}

static Node *unary(Parser *ps) {
	Token *t = ps->tk;
	if (eat (ps, "+")) {
		return unary (ps);
	}
	if (eat (ps, "-")) {
		Node *n = rvalize (unary (ps));
		if (n->kind == ND_NUM) {
			n->ival = -n->ival;
			return n;
		}
		if (n->kind == ND_FNUM) {
			n->fval = -n->fval;
			return n;
		}
		return new_unary (ps, ND_NEG, n, t);
	}
	if (eat (ps, "!")) {
		return new_unary (ps, ND_NOT, unary (ps), t);
	}
	if (eat (ps, "~")) {
		return new_unary (ps, ND_BITNOT, unary (ps), t);
	}
	if (eat (ps, "*")) {
		Node *n = rvalize (unary (ps));
		if (n->ty->kind != TY_PTR || !n->ty->base) {
			error_tok (ps->cc, t, "dereference of a non-pointer");
		}
		Node *d = new_unary (ps, ND_DEREF, n, t);
		d->ty = n->ty->base;
		return d;
	}
	if (eat (ps, "&")) {
		/* &FuncName -> function pointer */
		if (ps->tk->kind == TK_ID && !find_var (ps, ps->tk->str)) {
			Obj *fn = find_func (ps, ps->tk->str);
			if (fn) {
				Node *n = new_node (ND_FUNCNAME, t);
				n->func = fn;
				n->ty = ptr_to (ps->cc, fn->ty);
				ps->tk = ps->tk->next;
				return n;
			}
		}
		Node *n = unary (ps);
		if (!is_lvalue (n)) {
			error_tok (ps->cc, t, "'&' needs an lvalue");
		}
		Node *a = new_unary (ps, ND_ADDR, n, t);
		a->ty = ptr_to (ps->cc, n->ty);
		return a;
	}
	if (is_punct (ps, "++") || is_punct (ps, "--")) {
		int d = is_punct (ps, "++")? 1: -1;
		ps->tk = ps->tk->next;
		return incdec (ps, unary (ps), d, false, t);
	}
	return postfix (ps);
}

/* HolyC precedence, tightest first:
 *   ` << >>  |  * / %  |  &  |  ^  |  |  |  + -  |  < > <= >= (chained)
 *   |  == !=  |  &&  |  ^^  |  ||  |  assignment
 */
static Node *powshift(Parser *ps) {
	Node *n = unary (ps);
	for (;;) {
		Token *t = ps->tk;
		if (eat (ps, "`")) {
			n = new_binary (ps, ND_POW, n, unary (ps), t);
		} else if (eat (ps, "<<")) {
			n = new_binary (ps, ND_SHL, n, unary (ps), t);
		} else if (eat (ps, ">>")) {
			n = new_binary (ps, ND_SHR, n, unary (ps), t);
		} else {
			return n;
		}
	}
}

static Node *mul(Parser *ps) {
	Node *n = powshift (ps);
	for (;;) {
		Token *t = ps->tk;
		if (eat (ps, "*")) {
			n = new_binary (ps, ND_MUL, n, powshift (ps), t);
		} else if (eat (ps, "/")) {
			n = new_binary (ps, ND_DIV, n, powshift (ps), t);
		} else if (eat (ps, "%")) {
			n = new_binary (ps, ND_MOD, n, powshift (ps), t);
		} else {
			return n;
		}
	}
}

static Node *bitand_(Parser *ps) {
	Node *n = mul (ps);
	while (is_punct (ps, "&")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_AND, n, mul (ps), t);
	}
	return n;
}

static Node *bitxor_(Parser *ps) {
	Node *n = bitand_ (ps);
	while (is_punct (ps, "^")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_XOR, n, bitand_ (ps), t);
	}
	return n;
}

static Node *bitor_(Parser *ps) {
	Node *n = bitxor_ (ps);
	while (is_punct (ps, "|")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_OR, n, bitxor_ (ps), t);
	}
	return n;
}

static Node *addsub(Parser *ps) {
	Node *n = bitor_ (ps);
	for (;;) {
		Token *t = ps->tk;
		if (eat (ps, "+")) {
			n = new_binary (ps, ND_ADD, n, bitor_ (ps), t);
		} else if (eat (ps, "-")) {
			n = new_binary (ps, ND_SUB, n, bitor_ (ps), t);
		} else {
			return n;
		}
	}
}

/* relational with HolyC chaining: a<b<c => (a < (t=b)) && (t < c) */
static Node *relational(Parser *ps) {
	Node *n = addsub (ps);
	Node *chain = NULL;
	for (;;) {
		Token *t = ps->tk;
		NodeKind k;
		bool swap = false;
		if (is_punct (ps, "<")) k = ND_LT;
		else if (is_punct (ps, "<=")) k = ND_LE;
		else if (is_punct (ps, ">")) { k = ND_LT; swap = true; }
		else if (is_punct (ps, ">=")) { k = ND_LE; swap = true; }
		else break;
		ps->tk = ps->tk->next;
		Node *rhs = rvalize (addsub (ps));
		/* peek: is another relational op coming? */
		bool more = is_punct (ps, "<") || is_punct (ps, "<=") || is_punct (ps, ">") || is_punct (ps, ">=");
		Node *rhs_val = rhs;
		if (more) {
			Obj *tmp = new_temp (ps, value_type (ps->cc, rhs->ty));
			rhs = new_assign (ps, new_var_node (tmp, t), rhs, t);
			rhs_val = new_var_node (tmp, t);
		}
		Node *cmp = swap? new_binary (ps, k, rhs, rvalize (n), t)
		                : new_binary (ps, k, rvalize (n), rhs, t);
		chain = chain? new_binary (ps, ND_LOGAND, chain, cmp, t): cmp;
		if (!more) {
			return chain;
		}
		n = rhs_val;
	}
	return chain? chain: n;
}

static Node *equality(Parser *ps) {
	Node *n = relational (ps);
	for (;;) {
		Token *t = ps->tk;
		if (eat (ps, "==")) {
			n = new_binary (ps, ND_EQ, n, relational (ps), t);
		} else if (eat (ps, "!=")) {
			n = new_binary (ps, ND_NE, n, relational (ps), t);
		} else {
			return n;
		}
	}
}

static Node *logand(Parser *ps) {
	Node *n = equality (ps);
	while (is_punct (ps, "&&")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_LOGAND, n, equality (ps), t);
	}
	return n;
}

static Node *logxor(Parser *ps) {
	Node *n = logand (ps);
	while (is_punct (ps, "^^")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_LOGXOR, n, logand (ps), t);
	}
	return n;
}

static Node *logor(Parser *ps) {
	Node *n = logxor (ps);
	while (is_punct (ps, "||")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_LOGOR, n, logxor (ps), t);
	}
	return n;
}

static Node *assign(Parser *ps) {
	Node *n = logor (ps);
	Token *t = ps->tk;
	static const struct { const char *op; NodeKind k; } comp[] = {
		{ "+=", ND_ADD }, { "-=", ND_SUB }, { "*=", ND_MUL },
		{ "/=", ND_DIV }, { "%=", ND_MOD }, { "&=", ND_AND },
		{ "|=", ND_OR }, { "^=", ND_XOR }, { "<<=", ND_SHL },
		{ ">>=", ND_SHR }, { NULL, 0 }
	};
	if (eat (ps, "=")) {
		return new_assign (ps, n, assign (ps), t);
	}
	for (int i = 0; comp[i].op; i++) {
		if (is_punct (ps, comp[i].op)) {
			ps->tk = ps->tk->next;
			if (!is_lvalue (n)) {
				error_tok (ps->cc, t, "not an assignable expression");
			}
			Node *rhs = assign (ps);
			Node *place, *setup = lval_addr_temp (ps, n, &place, t);
			Node *res = new_assign (ps, place, new_binary (ps, comp[i].k, place, rhs, t), t);
			return setup? new_binary (ps, ND_COMMA, setup, res, t): res;
		}
	}
	return n;
}

static Node *expr(Parser *ps) {
	return assign (ps);
}

static Node *comma_expr(Parser *ps) {
	Node *n = expr (ps);
	while (is_punct (ps, ",")) {
		Token *t = ps->tk;
		ps->tk = ps->tk->next;
		n = new_binary (ps, ND_COMMA, n, expr (ps), t);
	}
	return n;
}

/* ------------------------------------------------------------ statements */

static Node *new_expr_stmt(Node *e, Token *t) {
	Node *n = new_node (ND_EXPR_STMT, t);
	n->lhs = e;
	return n;
}

static Node *new_goto(char *label, Token *t) {
	Node *n = new_node (ND_GOTO, t);
	n->label = label;
	return n;
}

static Node *new_labelstmt(char *label, Token *t) {
	Node *n = new_node (ND_LABEL, t);
	n->label = label;
	return n;
}

static void label_use(Parser *ps, char *name, Token *t, bool define) {
	for (LabelRef *l = ps->fn_labels; l; l = l->next) {
		if (!strcmp (l->name, name)) {
			if (define) {
				l->defined = true;
			}
			return;
		}
	}
	LabelRef *l = xcalloc (ps->cc, 1, sizeof(LabelRef));
	l->name = name;
	l->tok = t;
	l->defined = define;
	l->next = ps->fn_labels;
	ps->fn_labels = l;
}

/* implicit Print/PutChars statements */
static Node *print_stmt(Parser *ps) {
	Token *t = ps->tk;
	bool ischar = t->kind == TK_CHR;
	Node *fmt = NULL;
	Node head = {0};
	Node *cur = &head;
	int nargs = 0;
	if (ischar) {
		if (t->len == 0) {
			/* '' expr : PutChars(expr) */
			ps->tk = ps->tk->next;
			Node *e = rvalize (expr (ps));
			expect (ps, ";");
			cur->next = e;
			return new_expr_stmt (call_named (ps, "PutChars", head.next, 1, t), t);
		}
		ps->tk = ps->tk->next;
		expect (ps, ";");
		cur->next = new_num (t->ival, t);
		return new_expr_stmt (call_named (ps, "PutChars", head.next, 1, t), t);
	}
	/* string statement */
	Node *s = primary (ps); /* handles adjacent concat */
	if (s->str_len == 0 && !is_punct (ps, ";") && !is_punct (ps, ",")) {
		/* "" fmt,args : variable format string */
		fmt = rvalize (expr (ps));
	} else {
		fmt = s;
	}
	cur->next = fmt;
	cur = fmt;
	nargs = 1;
	while (eat (ps, ",")) {
		Node *a = rvalize (expr (ps));
		cur->next = a;
		cur = a;
		nargs++;
	}
	expect (ps, ";");
	return new_expr_stmt (call_named (ps, "Print", head.next, nargs, t), t);
}

/* variable declaration (local) starting at a type token */
static Node *local_decl(Parser *ps) {
	Token *t = ps->tk;
	Token *hint = NULL, *func_hint = NULL, *align_hint = NULL;
	collect_hints (ps, t, &hint, &func_hint, &align_hint);
	reject_func_hint (ps, func_hint);
	Type *base = builtin_type (ps->tk->str);
	if (!base) {
		base = find_class (ps, ps->tk->str);
	}
	ps->tk = ps->tk->next;
	Node head = {0};
	Node *cur = &head;
	bool first = true;
	while (!is_punct (ps, ";")) {
		if (!first) {
			expect (ps, ",");
		}
		first = false;
		Type *ty = base;
		while (eat (ps, "*")) {
			ty = ptr_to (ps->cc, ty);
		}
		/* reg/noreg/no_warn qualifiers: skip */
		while (is_kw (ps, "reg") || is_kw (ps, "noreg")) {
			bool was_reg = is_kw (ps, "reg");
			ps->tk = ps->tk->next;
			/* optional register name after 'reg' */
			if (was_reg && ps->tk->kind == TK_ID && ps->tk->next->kind == TK_ID) {
				ps->tk = ps->tk->next;
			}
		}
		/* function pointer declarator: (*name)(params) */
		if (is_punct (ps, "(")) {
			ps->tk = ps->tk->next;
			expect (ps, "*");
			if (ps->tk->kind != TK_ID) {
				error_tok (ps->cc, ps->tk, "expected name");
			}
			char *name = ps->tk->str;
			ps->tk = ps->tk->next;
			expect (ps, ")");
			expect (ps, "(");
			/* skip param list: types only matter for docs */
			int depth = 1;
			while (depth > 0 && ps->tk->kind != TK_EOF) {
				if (is_punct (ps, "(")) depth++;
				if (is_punct (ps, ")")) depth--;
				ps->tk = ps->tk->next;
			}
			Type *fnty = new_type (ps->cc, TY_FUNC, 8, 8);
			fnty->base = ty;
			Obj *var = new_local (ps, name,
				hinted_type (ps, ptr_to (ps->cc, fnty), hint));
			var->align = hint_alignment (ps, var->ty, align_hint);
			if (eat (ps, "=")) {
				Node *rhs = expr (ps);
				Node *a = new_assign (ps, new_var_node (var, t), rhs, t);
				cur->next = new_expr_stmt (a, t);
				cur = cur->next;
			}
			continue;
		}
		if (ps->tk->kind != TK_ID) {
			error_tok (ps->cc, ps->tk, "expected variable name");
		}
		char *name = ps->tk->str;
		Token *nt = ps->tk;
		ps->tk = ps->tk->next;
		while (eat (ps, "[")) {
			Node *len = comma_expr (ps);
			expect (ps, "]");
			ty = array_of (ps->cc, ty, (int)eval_const (ps, len));
		}
		Obj *var = new_local (ps, name, hinted_type (ps, ty, hint));
		var->align = hint_alignment (ps, var->ty, align_hint);
		if (eat (ps, "=")) {
			if (is_punct (ps, "{")) {
				/* brace initializer for 1-D arrays */
				if (ty->kind != TY_ARRAY) {
					error_tok (ps->cc, ps->tk, "brace initializer needs an array");
				}
				ps->tk = ps->tk->next;
				int idx = 0;
				while (!is_punct (ps, "}")) {
					if (idx) {
						expect (ps, ",");
					}
					if (is_punct (ps, "}")) {
						break;
					}
					Node *v = expr (ps);
					Node *dst = new_node (ND_DEREF, nt);
					Node *addr = new_binary (ps, ND_ADD, new_var_node (var, nt), new_num (idx, nt), nt);
					dst->lhs = addr;
					dst->ty = ty->base;
					cur->next = new_expr_stmt (new_assign (ps, dst, v, nt), nt);
					cur = cur->next;
					idx++;
				}
				expect (ps, "}");
			} else {
				Node *rhs = expr (ps);
				if (ty->kind == TY_ARRAY && rhs->kind == ND_STR) {
					/* U8 buf[N] = "str": copy bytes incl. NUL */
					Node *a1 = new_var_node (var, nt);
					Node *args = rvalize (a1);
					args->next = rhs;
					rhs->next = new_num (rhs->str_len + 1, nt);
					cur->next = new_expr_stmt (call_named (ps, "MemCpy", args, 3, nt), nt);
					cur = cur->next;
				} else {
					Node *a = new_assign (ps, new_var_node (var, nt), rhs, nt);
					cur->next = new_expr_stmt (a, nt);
					cur = cur->next;
				}
			}
		}
	}
	expect (ps, ";");
	if (!head.next) {
		return new_node (ND_NOP, t);
	}
	if (!head.next->next) {
		return head.next;
	}
	Node *blk = new_node (ND_BLOCK, t);
	blk->body = head.next;
	return blk;
}

/* ------------------------------------------------------------- switch */

typedef struct SwCase SwCase;
struct SwCase {
	SwCase *next;
	int64_t lo, hi;
	bool is_default;
	char *label;       /* jump target (case body or group stub) */
	int group;         /* -1 = ungrouped, else group index */
};

typedef struct {
	SwCase *cases, *cases_tail;
	int64_t next_case_val;
	char *exit_label;
	int ngroups;
	int cur_group;         /* -1 outside start:/end: */
	char *group_porch[64]; /* label of porch start per group */
	char *group_end[64];
	Obj *grp_var;
	Node *grp_head, *grp_tail;   /* statement chain being built */
	SwCase *grp_first_case;      /* first case of current group */
	bool in_porch;               /* between start: and first case of group */
	Node *porch_dispatch_anchor; /* where to insert porch dispatch */
} SwCtx;

static void sw_append(SwCtx *sw, Node *n) {
	if (sw->grp_tail) {
		sw->grp_tail->next = n;
	} else {
		sw->grp_head = n;
	}
	sw->grp_tail = n;
	while (sw->grp_tail->next) {
		sw->grp_tail = sw->grp_tail->next;
	}
}

static Node *switch_stmt(Parser *ps, Token *t) {
	bool nobound = is_punct (ps, "[");
	Node *cond;
	if (nobound) {
		expect (ps, "[");
		cond = comma_expr (ps);
		expect (ps, "]");
	} else {
		expect (ps, "(");
		cond = comma_expr (ps);
		expect (ps, ")");
	}
	expect (ps, "{");

	SwCtx sw = {0};
	sw.exit_label = new_label (ps, "swend");
	sw.cur_group = -1;
	sw.next_case_val = 0;

	Obj *swval = new_temp (ps, ty_i64);
	Node *setup = new_expr_stmt (new_assign (ps, new_var_node (swval, t), rvalize (cond), t), t);

	char *save_break = ps->break_label;
	ps->break_label = sw.exit_label;

	/* First pass: parse body statements, recording case labels inline. */
	enter_scope (ps);
	while (!is_punct (ps, "}")) {
		Token *ct = ps->tk;
		if (is_kw (ps, "case")) {
			ps->tk = ps->tk->next;
			SwCase *c = xcalloc (ps->cc, 1, sizeof(SwCase));
			if (is_punct (ps, ":")) {
				c->lo = c->hi = sw.next_case_val;
			} else {
				c->lo = eval_const (ps, expr (ps));
				c->hi = c->lo;
				if (eat (ps, "...")) {
					c->hi = eval_const (ps, expr (ps));
				}
			}
			expect (ps, ":");
			sw.next_case_val = c->hi + 1;
			c->label = new_label (ps, "case");
			c->group = sw.cur_group;
			if (sw.cases_tail) {
				sw.cases_tail->next = c;
			} else {
				sw.cases = c;
			}
			sw.cases_tail = c;
			if (sw.cur_group >= 0 && sw.in_porch) {
				/* end of porch: dispatch to selected case */
				sw.in_porch = false;
				sw.grp_first_case = c;
				/* porch dispatch emitted in pass 2 (needs all group cases) */
				Node *anchor = new_node (ND_NOP, ct);
				anchor->label = xasprintf (ps->cc, "porch%d", sw.cur_group);
				sw_append (&sw, anchor);
				sw.porch_dispatch_anchor = anchor;
			}
			sw_append (&sw, new_labelstmt (c->label, ct));
			continue;
		}
		if (is_kw (ps, "default")) {
			ps->tk = ps->tk->next;
			expect (ps, ":");
			SwCase *c = xcalloc (ps->cc, 1, sizeof(SwCase));
			c->is_default = true;
			c->label = new_label (ps, "default");
			c->group = sw.cur_group;
			if (sw.cases_tail) {
				sw.cases_tail->next = c;
			} else {
				sw.cases = c;
			}
			sw.cases_tail = c;
			sw_append (&sw, new_labelstmt (c->label, ct));
			continue;
		}
		if (is_kw (ps, "start") && ps->tk->next->kind == TK_PUNCT && !strcmp (ps->tk->next->str, ":")) {
			ps->tk = ps->tk->next->next;
			if (sw.cur_group >= 0) {
				error_tok (ps->cc, ct, "nested start:/end: groups are not supported");
			}
			if (sw.ngroups >= 64) {
				error_tok (ps->cc, ct, "too many sub_switch groups");
			}
			sw.cur_group = sw.ngroups++;
			if (!sw.grp_var) {
				sw.grp_var = new_temp (ps, ty_i64);
			}
			sw.group_porch[sw.cur_group] = new_label (ps, "porch");
			sw.group_end[sw.cur_group] = new_label (ps, "gend");
			sw.in_porch = true;
			/* falling into the porch selects the first case of the group */
			sw_append (&sw, new_expr_stmt (new_assign (ps,
				new_var_node (sw.grp_var, ct), new_num (-1, ct), ct), ct));
			sw_append (&sw, new_labelstmt (sw.group_porch[sw.cur_group], ct));
			ps->break_label = sw.group_end[sw.cur_group];
			continue;
		}
		if (is_kw (ps, "end") && ps->tk->next->kind == TK_PUNCT && !strcmp (ps->tk->next->str, ":")) {
			Token *et = ps->tk;
			ps->tk = ps->tk->next->next;
			if (sw.cur_group < 0) {
				error_tok (ps->cc, et, "end: without start:");
			}
			sw_append (&sw, new_labelstmt (sw.group_end[sw.cur_group], et));
			sw.cur_group = -1;
			ps->break_label = sw.exit_label;
			continue;
		}
		Node *s = stmt (ps);
		sw_append (&sw, s);
	}
	expect (ps, "}");
	leave_scope (ps);
	ps->break_label = save_break;

	if (sw.cur_group >= 0) {
		error_tok (ps->cc, t, "start: without end: in switch");
	}

	/* Pass 2: build dispatch. */
	Node *blk = new_node (ND_BLOCK, t);
	Node head = {0};
	Node *cur = &head;
	cur->next = setup;
	cur = setup;

	char *default_label = NULL;
	for (SwCase *c = sw.cases; c; c = c->next) {
		if (c->is_default) {
			default_label = c->label;
		}
	}
	/* dispatch: if (v>=lo && v<=hi) goto target */
	int case_idx_in_group[64] = {0};
	for (SwCase *c = sw.cases; c; c = c->next) {
		if (c->is_default) {
			continue;
		}
		Node *test;
		Node *v = new_var_node (swval, t);
		if (c->lo == c->hi) {
			test = new_binary (ps, ND_EQ, v, new_num (c->lo, t), t);
		} else {
			Node *ge = new_binary (ps, ND_LE, new_num (c->lo, t), new_var_node (swval, t), t);
			Node *le = new_binary (ps, ND_LE, new_var_node (swval, t), new_num (c->hi, t), t);
			test = new_binary (ps, ND_LOGAND, ge, le, t);
		}
		Node *br = new_node (ND_IF, t);
		br->cond = test;
		if (c->group >= 0) {
			/* stub: select case in group, enter porch */
			int idx = case_idx_in_group[c->group]++;
			c->hi = idx; /* reuse: idx within group for porch dispatch */
			Node *stub = new_node (ND_BLOCK, t);
			Node *sel = new_expr_stmt (new_assign (ps,
				new_var_node (sw.grp_var, t), new_num (idx, t), t), t);
			sel->next = new_goto (sw.group_porch[c->group], t);
			stub->body = sel;
			br->then = stub;
		} else {
			br->then = new_goto (c->label, t);
		}
		cur->next = br;
		cur = br;
	}
	cur->next = new_goto (default_label? default_label: sw.exit_label, t);
	cur = cur->next;

	/* splice body; replace porch anchors with in-group dispatch */
	Node *body = sw.grp_head;
	for (Node *s = body, *prev = cur; s; prev = s, s = s->next) {
		if (s->kind == ND_NOP && s->label && !strncmp (s->label, "porch", 5)) {
			int g = atoi (s->label + 5);
			/* dispatch: grp_var == idx -> goto case label; -1 falls to first */
			Node dh = {0};
			Node *dc = &dh;
			for (SwCase *c = sw.cases; c; c = c->next) {
				if (c->group != g || c->is_default) {
					continue;
				}
				Node *br = new_node (ND_IF, t);
				br->cond = new_binary (ps, ND_EQ, new_var_node (sw.grp_var, t),
					new_num (c->hi, t), t); /* hi = idx in group */
				br->then = new_goto (c->label, t);
				dc->next = br;
				dc = br;
			}
			/* fall to first case in group (label follows anchor) */
			if (dh.next) {
				dc->next = s->next;
				prev->next = dh.next;
				s = dc;
			}
		}
	}
	cur->next = body;
	while (cur->next) {
		cur = cur->next;
	}
	cur->next = new_labelstmt (sw.exit_label, t);
	blk->body = head.next;
	return blk;
}

/* ------------------------------------------------------------- stmt */

static Node *stmt(Parser *ps) {
	Token *t = ps->tk;
	if (is_punct (ps, "{")) {
		return block_stmt (ps);
	}
	if (eat (ps, ";")) {
		return new_node (ND_NOP, t);
	}
	if (is_kw (ps, "if")) {
		ps->tk = ps->tk->next;
		expect (ps, "(");
		Node *n = new_node (ND_IF, t);
		n->cond = to_bool (ps, rvalize (comma_expr (ps)));
		expect (ps, ")");
		n->then = stmt (ps);
		if (is_kw (ps, "else")) {
			ps->tk = ps->tk->next;
			n->els = stmt (ps);
		}
		return n;
	}
	if (is_kw (ps, "while")) {
		ps->tk = ps->tk->next;
		expect (ps, "(");
		Node *n = new_node (ND_WHILE, t);
		n->cond = to_bool (ps, rvalize (comma_expr (ps)));
		expect (ps, ")");
		char *end = new_label (ps, "wend");
		char *save = ps->break_label;
		ps->break_label = end;
		n->then = stmt (ps);
		ps->break_label = save;
		Node *blk = new_node (ND_BLOCK, t);
		blk->body = n;
		n->next = new_labelstmt (end, t);
		return blk;
	}
	if (is_kw (ps, "do")) {
		ps->tk = ps->tk->next;
		Node *n = new_node (ND_DOWHILE, t);
		char *end = new_label (ps, "dend");
		char *save = ps->break_label;
		ps->break_label = end;
		n->then = stmt (ps);
		ps->break_label = save;
		if (!is_kw (ps, "while")) {
			error_tok (ps->cc, ps->tk, "expected 'while' after do body");
		}
		ps->tk = ps->tk->next;
		expect (ps, "(");
		n->cond = to_bool (ps, rvalize (comma_expr (ps)));
		expect (ps, ")");
		expect (ps, ";");
		Node *blk = new_node (ND_BLOCK, t);
		blk->body = n;
		n->next = new_labelstmt (end, t);
		return blk;
	}
	if (is_kw (ps, "for")) {
		ps->tk = ps->tk->next;
		expect (ps, "(");
		Node *n = new_node (ND_FOR, t);
		enter_scope (ps);
		if (!is_punct (ps, ";")) {
			if (is_type_start (ps, ps->tk) && ps->tk->next->kind == TK_ID) {
				n->init = local_decl (ps);
			} else {
				n->init = new_expr_stmt (comma_expr (ps), t);
				expect (ps, ";");
			}
		} else {
			expect (ps, ";");
		}
		if (!is_punct (ps, ";")) {
			n->cond = to_bool (ps, rvalize (comma_expr (ps)));
		}
		expect (ps, ";");
		if (!is_punct (ps, ")")) {
			n->inc = new_expr_stmt (comma_expr (ps), t);
		}
		expect (ps, ")");
		char *end = new_label (ps, "fend");
		char *save = ps->break_label;
		ps->break_label = end;
		n->then = stmt (ps);
		ps->break_label = save;
		leave_scope (ps);
		Node *blk = new_node (ND_BLOCK, t);
		blk->body = n;
		n->next = new_labelstmt (end, t);
		return blk;
	}
	if (is_kw (ps, "switch")) {
		ps->tk = ps->tk->next;
		return switch_stmt (ps, t);
	}
	if (is_kw (ps, "return")) {
		ps->tk = ps->tk->next;
		Node *n = new_node (ND_RETURN, t);
		if (!is_punct (ps, ";")) {
			Node *e = rvalize (comma_expr (ps));
			Type *rt = ps->cur_fn->ty->base;
			if (rt && rt->kind == TY_F64) {
				e = to_f64 (e);
			} else if (rt && rt->kind != TY_VOID && e->ty->kind == TY_F64) {
				e = to_int (e);
			}
			if (rt && rt->kind == TY_VOID) {
				/* U0 fn: evaluate for side effects, discard */
				n->lhs = NULL;
				Node *blk = new_node (ND_BLOCK, t);
				Node *es = new_expr_stmt (e, t);
				es->next = n;
				blk->body = es;
				expect (ps, ";");
				return blk;
			}
			n->lhs = e;
		}
		expect (ps, ";");
		return n;
	}
	if (is_kw (ps, "break")) {
		ps->tk = ps->tk->next;
		expect (ps, ";");
		if (!ps->break_label) {
			error_tok (ps->cc, t, "break outside of a loop or switch");
		}
		return new_goto (ps->break_label, t);
	}
	if (is_kw (ps, "continue")) {
		error_tok (ps->cc, t, "HolyC has no 'continue' statement; use goto (see doc/language.md)");
	}
	if (is_kw (ps, "goto")) {
		ps->tk = ps->tk->next;
		if (ps->tk->kind != TK_ID) {
			error_tok (ps->cc, ps->tk, "expected label after goto");
		}
		char *name = ps->tk->str;
		ps->tk = ps->tk->next;
		expect (ps, ";");
		label_use (ps, name, t, false);
		return new_goto (xasprintf (ps->cc, "u_%s", name), t);
	}
	if (is_kw (ps, "try")) {
		ps->tk = ps->tk->next;
		Node *n = new_node (ND_TRY, t);
		n->then = block_stmt (ps);
		if (!is_kw (ps, "catch")) {
			error_tok (ps->cc, ps->tk, "expected 'catch' after try block");
		}
		ps->tk = ps->tk->next;
		n->els = block_stmt (ps);
		return n;
	}
	if (is_kw (ps, "no_warn")) {
		while (!eat (ps, ";")) {
			if (ps->tk->kind == TK_EOF) {
				error_tok (ps->cc, t, "unterminated no_warn");
			}
			ps->tk = ps->tk->next;
		}
		return new_node (ND_NOP, t);
	}
	if (is_kw (ps, "asm")) {
		error_tok (ps->cc, t, "inline asm is not supported by aholyc (portable backends only)");
	}
	if (is_kw (ps, "lock")) {
		/* compile the block without lock semantics */
		ps->tk = ps->tk->next;
		return block_stmt (ps);
	}
	/* label? ident ':' (not '::') */
	if (t->kind == TK_ID && t->next && t->next->kind == TK_PUNCT &&
	    !strcmp (t->next->str, ":") && !is_type_start (ps, t)) {
		char *name = t->str;
		ps->tk = t->next->next;
		label_use (ps, name, t, true);
		return new_labelstmt (xasprintf (ps->cc, "u_%s", name), t);
	}
	/* declaration? */
	if (is_type_start (ps, t)) {
		Token *n1 = t->next;
		/* distinguish `I64 x;` from expression starting with cast-able name */
		if (n1->kind == TK_ID || (n1->kind == TK_PUNCT &&
		    (!strcmp (n1->str, "*") || !strcmp (n1->str, "("))) ) {
			/* class name followed by '(' would be odd; require ident/star */
			if (n1->kind == TK_ID || !strcmp (n1->str, "*") ||
			    (n1->kind == TK_PUNCT && !strcmp (n1->str, "(") &&
			     n1->next && n1->next->kind == TK_PUNCT && !strcmp (n1->next->str, "*"))) {
				return local_decl (ps);
			}
		}
	}
	/* implicit print statements */
	if (t->kind == TK_STR || t->kind == TK_CHR) {
		return print_stmt (ps);
	}
	Node *e = comma_expr (ps);
	expect (ps, ";");
	return new_expr_stmt (e, t);
}

static Node *block_stmt(Parser *ps) {
	Token *t = ps->tk;
	expect (ps, "{");
	enter_scope (ps);
	Node head = {0};
	Node *cur = &head;
	while (!is_punct (ps, "}")) {
		if (ps->tk->kind == TK_EOF) {
			error_tok (ps->cc, t, "unterminated block");
		}
		Node *s = stmt (ps);
		cur->next = s;
		while (cur->next) {
			cur = cur->next;
		}
	}
	expect (ps, "}");
	leave_scope (ps);
	Node *n = new_node (ND_BLOCK, t);
	n->body = head.next;
	return n;
}

/* --------------------------------------------------------- declarations */

static void check_labels(Parser *ps) {
	for (LabelRef *l = ps->fn_labels; l; l = l->next) {
		if (!l->defined) {
			error_tok (ps->cc, l->tok, "goto to undefined label '%s'", l->name);
		}
	}
	ps->fn_labels = NULL;
}

/* parse params: (type name=dft, ..., ...) — returns param chain */
static void parse_params(Parser *ps, Obj *fn) {
	expect (ps, "(");
	Obj head = {0};
	Obj *cur = &head;
	Node *defaults[256];
	int n = 0;
	bool first = true;
	while (!is_punct (ps, ")")) {
		if (!first) {
			expect (ps, ",");
		}
		first = false;
		if (eat (ps, "...")) {
			fn->is_variadic = true;
			break;
		}
		if (!is_type_start (ps, ps->tk)) {
			error_tok (ps->cc, ps->tk, "expected parameter type");
		}
		Token *hint = NULL;
		collect_bits_hint (ps, ps->tk, &hint);
		Type *ty = parse_typespec (ps);
		/* (U0) means no params */
		if (ty == ty_u0 && is_punct (ps, ")") && n == 0) {
			hinted_type (ps, ty, hint);
			break;
		}
		char *name = NULL;
		if (ps->tk->kind == TK_ID) {
			name = ps->tk->str;
			ps->tk = ps->tk->next;
		}
		while (eat (ps, "[")) {
			/* array param decays to pointer; size ignored */
			if (!is_punct (ps, "]")) {
				eval_const (ps, expr (ps));
			}
			expect (ps, "]");
			ty = ptr_to (ps->cc, ty);
		}
		if (ty->kind == TY_CLASS) {
			error_tok (ps->cc, ps->tk, "class values cannot be parameters; pass a pointer");
		}
		Obj *p = new_obj (ps, name? name: xasprintf (ps->cc, "arg%d", n),
			hinted_type (ps, ty, hint));
		defaults[n] = NULL;
		if (eat (ps, "=")) {
			if (eat (ps, "lastclass")) {
				defaults[n] = nd_lastclass;
			} else {
				defaults[n] = rvalize (expr (ps));
				if (ty->kind == TY_F64) {
					defaults[n] = to_f64 (defaults[n]);
				} else if (defaults[n]->ty->kind == TY_F64) {
					defaults[n] = to_int (defaults[n]);
				}
			}
		}
		n++;
		if (n >= 250) {
			error_tok (ps->cc, ps->tk, "too many parameters");
		}
		cur->next = p;
		cur = p;
	}
	expect (ps, ")");
	if (fn->is_variadic) {
		/* implicit argc/argv params */
		Obj *pargc = new_obj (ps, xstrdup (ps->cc, "argc"), ty_i64);
		Obj *pargv = new_obj (ps, xstrdup (ps->cc, "argv"),
			ptr_to (ps->cc, ty_i64));
		cur->next = pargc;
		pargc->next = pargv;
		cur = pargv;
	}
	for (Obj *p = head.next; p; p = p->next) {
		p->is_param = true;
	}
	fn->params = head.next;
	fn->nparams = n;
	fn->defaults = xmalloc (ps->cc, sizeof(Node *) * (n? n: 1));
	memcpy (fn->defaults, defaults, sizeof(Node *) * n);
}

static void add_func(Parser *ps, Obj *fn) {
	if (ps->funcs_tail) {
		ps->funcs_tail->next = fn;
	} else {
		ps->prog->funcs = fn;
	}
	ps->funcs_tail = fn;
}

static void parse_class(Parser *ps, bool is_union, int align_all) {
	ps->tk = ps->tk->next; /* class/union */
	if (ps->tk->kind != TK_ID) {
		error_tok (ps->cc, ps->tk, "expected class name");
	}
	char *name = ps->tk->str;
	ps->tk = ps->tk->next;
	Type *ty = find_class (ps, name);
	if (!ty) {
		ty = new_type (ps->cc, TY_CLASS, 0, 1);
		ty->name = name;
		ty->is_union = is_union;
		ClassEnt *c = xcalloc (ps->cc, 1, sizeof(ClassEnt));
		c->name = name;
		c->ty = ty;
		c->next = ps->classes;
		ps->classes = c;
	}
	if (eat (ps, ";")) {
		return; /* forward declaration */
	}
	if (eat (ps, ":")) {
		if (ps->tk->kind != TK_ID) {
			error_tok (ps->cc, ps->tk, "expected parent class name");
		}
		Type *parent = find_class (ps, ps->tk->str);
		if (!parent) {
			error_tok (ps->cc, ps->tk, "unknown parent class '%s'", ps->tk->str);
		}
		ty->parent = parent;
		ps->tk = ps->tk->next;
	}
	expect (ps, "{");
	/* TempleOS layout: members are packed back to back, no alignment or
	 * padding.  "$$ = expr;" moves the offset for the next member; the
	 * most negative offset grows the class like TempleOS neg_offset. */
	int off = ty->parent? ty->parent->size: 0;
	int align = ty->parent? ty->parent->align: 1;
	int layout_align = align;
	int neg = 0;
	int union_base = 0;
	bool aligned_layout = align_all;
	bool save_in_class = ps->in_class_body;
	ps->in_class_body = true;
	Member head = {0};
	Member *cur = &head;
	while (!is_punct (ps, "}")) {
		ps->class_dol_offset = is_union? union_base: off;
		if (eat (ps, ";")) {
			continue;
		}
		if (is_punct (ps, "$$")) {
			ps->tk = ps->tk->next;
			expect (ps, "=");
			int v = (int)eval_const (ps, expr (ps));
			expect (ps, ";");
			if (-v > neg) {
				neg = -v;
			}
			if (is_union) {
				union_base = v;
			} else {
				off = v;
			}
			continue;
		}
		if (!is_type_start (ps, ps->tk)) {
			error_tok (ps->cc, ps->tk, "expected member type");
		}
		Token *hint = NULL, *func_hint = NULL, *align_hint = NULL;
		collect_hints (ps, ps->tk, &hint, &func_hint, &align_hint);
		reject_func_hint (ps, func_hint);
		aligned_layout |= ps->align_hints && align_hint != NULL;
		Type *base = parse_typespec (ps);
		/* strip stars parsed by typespec: they apply to first declarator only
		 * in C; HolyC code in practice writes one declarator per star usage.
		 * parse_typespec consumed them, keep as-is for first; extra
		 * declarators share the starred type. */
		bool first = true;
		for (;;) {
			Type *mty = base;
			if (!first) {
				while (eat (ps, "*")) {
					mty = ptr_to (ps->cc, mty);
				}
			}
			first = false;
			if (ps->tk->kind != TK_ID) {
				error_tok (ps->cc, ps->tk, "expected member name");
			}
			char *mname = ps->tk->str;
			ps->tk = ps->tk->next;
			while (eat (ps, "[")) {
				Node *len = comma_expr (ps);
				expect (ps, "]");
				mty = array_of (ps->cc, mty, (int)eval_const (ps, len));
			}
			if (mty->kind == TY_CLASS && mty->size == 0) {
				error_tok (ps->cc, ps->tk, "member of incomplete class type");
			}
			Member *m = xcalloc (ps->cc, 1, sizeof(Member));
			m->name = mname;
			m->ty = hinted_type (ps, mty, hint);
			int natural = mty->align? mty->align: 1;
			int policy = ps->align_hints && align_hint?
				align_hint->hint_align: align_all;
			int a = policy < 0? natural: policy;
			int pos = is_union? union_base: off;
			if (policy) {
				pos = align_up (pos, a);
				if (a > layout_align) {
					layout_align = a;
				}
			}
			if (is_union) {
				m->offset = pos;
				if (pos + mty->size > off) {
					off = pos + mty->size;
				}
			} else {
				m->offset = pos;
				off = pos + mty->size;
			}
			if (natural > align) {
				align = natural;
			}
			cur->next = m;
			cur = m;
			ps->class_dol_offset = is_union? union_base: off;
			if (!eat (ps, ",")) {
				break;
			}
		}
		expect (ps, ";");
	}
	expect (ps, "}");
	eat (ps, ";");
	ps->in_class_body = save_in_class;
	ty->members = head.next;
	ty->align = aligned_layout? layout_align: align;
	ty->size = aligned_layout? align_up (off + neg, layout_align): off + neg;
}

/* function definition or declaration after type+name(  */
static void parse_func(Parser *ps, Type *ret, char *name, bool is_extern, bool is_public,
                       Token *inline_tok) {
	Obj *fn = find_func (ps, name);
	bool fresh = !fn;
	if (fresh) {
		fn = new_obj (ps, name, NULL);
		fn->is_func = true;
	}
	Type *fnty = new_type (ps->cc, TY_FUNC, 8, 8);
	fnty->base = ret;
	fn->ty = fnty;
	fn->is_extern = is_extern;
	if (inline_tok) {
		if (fn->hints && fn->hints != inline_tok->hints) {
			error_tok (ps->cc, inline_tok, "conflicting inline hint for function %s", name);
		}
		fn->hints = inline_tok->hints;
	}
	if (is_extern && ps->tk->file && !strcmp (ps->tk->file, "<prelude>")) {
		fn->from_prelude = true;
	}
	if (is_public) {
		fn->is_public = true;
	}
	enter_scope (ps);
	Obj *save_locals = ps->fn_locals;
	Obj *save_fn = ps->cur_fn;
	LabelRef *save_labels = ps->fn_labels;
	ps->fn_locals = NULL;
	ps->fn_labels = NULL;
	ps->cur_fn = fn;
	parse_params (ps, fn);
	if (fresh) {
		add_func (ps, fn);
	}
	if (eat (ps, ";")) {
		leave_scope (ps);
		ps->fn_locals = save_locals;
		ps->fn_labels = save_labels;
		ps->cur_fn = save_fn;
		return;
	}
	if (fn->body) {
		error_tok (ps->cc, ps->tk, "redefinition of function %s", name);
	}
	/* params visible in body scope */
	for (Obj *p = fn->params; p; p = p->next) {
		scope_push (ps, p->name, p);
	}
	fn->body = block_stmt (ps);
	check_labels (ps);
	fn->locals = ps->fn_locals;
	leave_scope (ps);
	ps->fn_locals = save_locals;
	ps->fn_labels = save_labels;
	ps->cur_fn = save_fn;
}

/* global variable declaration(s); initializers become startup stmts */
static Node *global_decl(Parser *ps, Type *base, bool is_extern, bool is_public,
                         Token *hint) {
	Node head = {0};
	Node *cur = &head;
	bool first = true;
	Token *t = ps->tk;
	while (!is_punct (ps, ";")) {
		if (!first) {
			expect (ps, ",");
		}
		first = false;
		Type *ty = base;
		if (!first) {
			/* stars per declarator after the first */
		}
		while (eat (ps, "*")) {
			ty = ptr_to (ps->cc, ty);
		}
		if (is_punct (ps, "(")) {
			/* global function pointer */
			ps->tk = ps->tk->next;
			expect (ps, "*");
			char *name = ps->tk->str;
			ps->tk = ps->tk->next;
			expect (ps, ")");
			expect (ps, "(");
			int depth = 1;
			while (depth > 0 && ps->tk->kind != TK_EOF) {
				if (is_punct (ps, "(")) depth++;
				if (is_punct (ps, ")")) depth--;
				ps->tk = ps->tk->next;
			}
			Type *fnty = new_type (ps->cc, TY_FUNC, 8, 8);
			fnty->base = ty;
			Obj *var = new_global (ps, name,
				hinted_type (ps, ptr_to (ps->cc, fnty), hint));
			var->is_extern = is_extern;
			var->is_public = is_public;
			if (eat (ps, "=")) {
				Node *rhs = expr (ps);
				cur->next = new_expr_stmt (new_assign (ps, new_var_node (var, t), rhs, t), t);
				cur = cur->next;
			}
			continue;
		}
		if (ps->tk->kind != TK_ID) {
			error_tok (ps->cc, ps->tk, "expected variable name");
		}
		char *name = ps->tk->str;
		Token *nt = ps->tk;
		ps->tk = ps->tk->next;
		while (eat (ps, "[")) {
			Node *len = comma_expr (ps);
			expect (ps, "]");
			ty = array_of (ps->cc, ty, (int)eval_const (ps, len));
		}
		Obj *var = new_global (ps, name, hinted_type (ps, ty, hint));
		var->is_extern = is_extern;
		var->is_public = is_public;
		if (is_extern && nt->file && !strcmp (nt->file, "<prelude>")) {
			var->from_prelude = true;
		}
		if (eat (ps, "=")) {
			if (is_punct (ps, "{")) {
				if (ty->kind != TY_ARRAY) {
					error_tok (ps->cc, ps->tk, "brace initializer needs an array");
				}
				ps->tk = ps->tk->next;
				int idx = 0;
				while (!is_punct (ps, "}")) {
					if (idx) {
						expect (ps, ",");
					}
					if (is_punct (ps, "}")) {
						break;
					}
					Node *v = expr (ps);
					Node *dst = new_node (ND_DEREF, nt);
					dst->lhs = new_binary (ps, ND_ADD, new_var_node (var, nt), new_num (idx, nt), nt);
					dst->ty = ty->base;
					cur->next = new_expr_stmt (new_assign (ps, dst, v, nt), nt);
					cur = cur->next;
					idx++;
				}
				expect (ps, "}");
			} else {
				Node *rhs = expr (ps);
				if (ty->kind == TY_ARRAY && rhs->kind == ND_STR) {
					Node *args = rvalize (new_var_node (var, nt));
					args->next = rhs;
					rhs->next = new_num (rhs->str_len + 1, nt);
					cur->next = new_expr_stmt (call_named (ps, "MemCpy", args, 3, nt), nt);
					cur = cur->next;
				} else {
					cur->next = new_expr_stmt (new_assign (ps, new_var_node (var, nt), rhs, nt), nt);
					cur = cur->next;
				}
			}
		}
	}
	expect (ps, ";");
	return head.next;
}

/* ------------------------------------------------------------- top level */

Program *parse(Aholyc *cc, Token *tok, bool align_hints) {
	Parser state = {
		.cc = cc, .tk = tok, .uid_counter = 1, .label_counter = 1,
		.align_hints = align_hints,
	};
	Parser *ps = &state;
	ps->prog = xcalloc (ps->cc, 1, sizeof(Program));
	enter_scope (ps); /* global scope */

	Obj *startup = new_obj (ps, xstrdup (ps->cc, "__hc_start"), NULL);
	startup->is_func = true;
	Type *fnty = new_type (ps->cc, TY_FUNC, 8, 8);
	/* Falling off global startup succeeds; an explicit top-level return
	 * becomes the hosted process exit status. */
	fnty->base = ty_i64;
	startup->ty = fnty;
	/* Like a variadic function, global-space startup receives a hidden
	 * count/vector pair.  CLI vector elements are pointer-sized I64 slots. */
	Obj *pargc = new_obj (ps, xstrdup (ps->cc, "argc"), ty_i64);
	Obj *pargv = new_obj (ps, xstrdup (ps->cc, "argv"),
		ptr_to (ps->cc, ty_i64));
	pargc->is_param = pargv->is_param = true;
	pargc->next = pargv;
	startup->params = pargc;
	startup->is_variadic = true;
	startup->defaults = xmalloc (ps->cc, sizeof(Node *));
	ps->prog->startup = startup;

	Node top_head = {0};
	Node *top_cur = &top_head;

	while (ps->tk->kind != TK_EOF) {
		Token *hint = NULL;
		Token *inline_tok = NULL;
		Token *align_tok = NULL;
		collect_hints (ps, ps->tk, &hint, &inline_tok, &align_tok);
		/* function attribute keywords; 'public' exports the symbol */
		bool is_public = false;
		while (is_kw (ps, "public") || is_kw (ps, "interrupt") || is_kw (ps, "haserrcode") ||
		       is_kw (ps, "argpop") || is_kw (ps, "noargpop")) {
			if (is_kw (ps, "public")) {
				is_public = true;
			}
			ps->tk = ps->tk->next;
			collect_hints (ps, ps->tk, &hint, &inline_tok, &align_tok);
		}
		bool is_extern = false;
		if (is_kw (ps, "extern") || is_kw (ps, "import") || is_kw (ps, "_extern") || is_kw (ps, "_import")) {
			is_extern = true;
			ps->tk = ps->tk->next;
			collect_hints (ps, ps->tk, &hint, &inline_tok, &align_tok);
			/* _extern SYMBOL alias form: skip the symbol token */
			if (ps->tk->kind == TK_ID && ps->tk->next->kind == TK_ID &&
			    !builtin_type (ps->tk->str) && !find_class (ps, ps->tk->str)) {
				ps->tk = ps->tk->next;
				collect_hints (ps, ps->tk, &hint, &inline_tok, &align_tok);
			}
		}
		if (is_kw (ps, "class")) {
			if (hint) {
				error_tok (ps->cc, hint, "@bits applies only to integer object declarations");
			}
			reject_func_hint (ps, inline_tok);
			parse_class (ps, false, align_tok && ps->align_hints? align_tok->hint_align: 0);
			continue;
		}
		if (is_kw (ps, "union")) {
			if (hint) {
				error_tok (ps->cc, hint, "@bits applies only to integer object declarations");
			}
			reject_func_hint (ps, inline_tok);
			parse_class (ps, true, align_tok && ps->align_hints? align_tok->hint_align: 0);
			continue;
		}
		if (is_type_start (ps, ps->tk)) {
			/* type [stars] ident '(' => function; else global var(s) */
			Token *save = ps->tk;
			Type *base = builtin_type (ps->tk->str);
			if (!base) {
				base = find_class (ps, ps->tk->str);
			}
			ps->tk = ps->tk->next;
			Type *ret = base;
			while (eat (ps, "*")) {
				ret = ptr_to (ps->cc, ret);
			}
			if (ps->tk->kind == TK_ID && ps->tk->next && ps->tk->next->kind == TK_PUNCT &&
			    !strcmp (ps->tk->next->str, "(")) {
				if (hint) {
					error_tok (ps->cc, hint, "@bits applies only to integer object declarations");
				}
				if (align_tok) {
					error_tok (ps->cc, align_tok, "@align does not apply to functions");
				}
				char *name = ps->tk->str;
				ps->tk = ps->tk->next;
				parse_func (ps, ret, name, is_extern, is_public, inline_tok);
				continue;
			}
			reject_func_hint (ps, inline_tok);
			if (align_tok) {
				error_tok (ps->cc, align_tok, "@align applies only to classes, fields, and local variables");
			}
			/* global variable(s): rewind to after base name, stars are
			 * per-declarator in global_decl */
			ps->tk = save->next;
			Obj *save_fn = ps->cur_fn;
			Obj *save_locals = ps->fn_locals;
			ps->cur_fn = startup;
			ps->fn_locals = startup->locals;
			Node *init = global_decl (ps, base, is_extern, is_public, hint);
			startup->locals = ps->fn_locals;
			ps->fn_locals = save_locals;
			ps->cur_fn = save_fn;
			if (init) {
				top_cur->next = init;
				while (top_cur->next) {
					top_cur = top_cur->next;
				}
			}
			continue;
		}
		if (is_extern) {
			error_tok (ps->cc, ps->tk, "expected declaration after extern");
		}
		if (hint) {
			error_tok (ps->cc, hint, "@bits applies only to integer object declarations");
		}
		reject_func_hint (ps, inline_tok);
		if (align_tok) {
			error_tok (ps->cc, align_tok, "@align applies only to classes, fields, and local variables");
		}
		/* top-level statement -> startup code */
		Obj *save_fn = ps->cur_fn;
		Obj *save_locals = ps->fn_locals;
		ps->cur_fn = startup;
		ps->fn_locals = startup->locals;
		Node *s = stmt (ps);
		startup->locals = ps->fn_locals;
		ps->fn_locals = save_locals;
		ps->cur_fn = save_fn;
		top_cur->next = s;
		while (top_cur->next) {
			top_cur = top_cur->next;
		}
	}
	check_labels (ps); /* top-level gotos */

	Node *body = new_node (ND_BLOCK, tok);
	body->body = top_head.next;
	startup->body = body;
	return ps->prog;
}
