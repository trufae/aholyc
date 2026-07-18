/* aholyc parser: HolyC grammar -> core AST.
 * Sugar (default args, implicit Print, switch, range comparisons, ++/--,
 * compound assignment) is lowered here so backends stay small.
 */
#include "aholyc.h"

/* ------------------------------------------------------------- type pool */

static Type ty_u0_ = { .kind = TY_VOID, .size = 0, .align = 1 };
static Type ty_i8_ = { .kind = TY_INT, .size = 1, .align = 1 };
static Type ty_u8_ = { .kind = TY_INT, .size = 1, .align = 1, .is_unsigned = true };
static Type ty_i16_ = { .kind = TY_INT, .size = 2, .align = 2 };
static Type ty_u16_ = { .kind = TY_INT, .size = 2, .align = 2, .is_unsigned = true };
static Type ty_i32_ = { .kind = TY_INT, .size = 4, .align = 4 };
static Type ty_u32_ = { .kind = TY_INT, .size = 4, .align = 4, .is_unsigned = true };
static Type ty_i64_ = { .kind = TY_INT, .size = 8, .align = 8 };
static Type ty_u64_ = { .kind = TY_INT, .size = 8, .align = 8, .is_unsigned = true };
static Type ty_f64_ = { .kind = TY_F64, .size = 8, .align = 8 };

Type *ty_u0 = &ty_u0_, *ty_i8 = &ty_i8_, *ty_u8 = &ty_u8_,
	*ty_i16 = &ty_i16_, *ty_u16 = &ty_u16_, *ty_i32 = &ty_i32_,
	*ty_u32 = &ty_u32_, *ty_i64 = &ty_i64_, *ty_u64 = &ty_u64_,
	*ty_f64 = &ty_f64_;

static Type *new_type(TypeKind k, int size, int align) {
	Type *t = xcalloc (1, sizeof(Type));
	t->kind = k;
	t->size = size;
	t->align = align;
	return t;
}

Type *ptr_to(Type *base) {
	Type *t = new_type (TY_PTR, 8, 8);
	t->base = base;
	return t;
}

Type *array_of(Type *base, int len) {
	Type *t = new_type (TY_ARRAY, base->size * len, base->align);
	t->base = base;
	t->array_len = len;
	return t;
}

bool is_integer(Type *ty) { return ty->kind == TY_INT; }
bool is_numeric(Type *ty) { return ty->kind == TY_INT || ty->kind == TY_F64; }
static bool is_ptrish(Type *ty) { return ty->kind == TY_PTR || ty->kind == TY_ARRAY; }

Member *find_member(Type *ty, char *name) {
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

static Token *tk;              /* cursor */
static Scope *scope;
static Obj *cur_fn;
static Obj *fn_locals;         /* locals of function being parsed */
static Program *prog;
static Obj *funcs_tail, *globals_tail;
static int uid_counter = 1;
static int label_counter = 1;
static char *break_label;      /* innermost break target (NULL outside) */

typedef struct ClassEnt ClassEnt;
struct ClassEnt { ClassEnt *next; char *name; Type *ty; };
static ClassEnt *classes;

/* '$$' inside a class/union body is the offset where the next member will
 * land (TempleOS class_dol_offset); outside it is the current code address. */
static bool in_class_body;
static int class_dol_offset;

typedef struct LabelRef LabelRef;
struct LabelRef { LabelRef *next; char *name; Token *tok; bool defined; };
static LabelRef *fn_labels;

/* ------------------------------------------------------------- helpers */

static void enter_scope(void) {
	Scope *s = xcalloc (1, sizeof(Scope));
	s->next = scope;
	scope = s;
}

static void leave_scope(void) {
	scope = scope->next;
}

static Obj *find_var(const char *name) {
	for (Scope *s = scope; s; s = s->next) {
		for (VarScope *v = s->vars; v; v = v->next) {
			if (!strcmp (v->name, name)) {
				return v->var;
			}
		}
	}
	return NULL;
}

static Obj *find_func(const char *name) {
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (!strcmp (f->name, name)) {
			return f;
		}
	}
	return NULL;
}

static Type *find_class(const char *name) {
	for (ClassEnt *c = classes; c; c = c->next) {
		if (!strcmp (c->name, name)) {
			return c->ty;
		}
	}
	return NULL;
}

static void scope_push(char *name, Obj *var) {
	VarScope *v = xcalloc (1, sizeof(VarScope));
	v->name = name;
	v->var = var;
	v->next = scope->vars;
	scope->vars = v;
}

static Obj *new_obj(char *name, Type *ty) {
	Obj *o = xcalloc (1, sizeof(Obj));
	o->name = name;
	o->ty = ty;
	o->uid = uid_counter++;
	return o;
}

static Obj *new_local(char *name, Type *ty) {
	Obj *o = new_obj (name, ty);
	o->next = fn_locals;
	fn_locals = o;
	scope_push (name, o);
	return o;
}

static Obj *new_temp(Type *ty) {
	char *name = xasprintf ("tmp%d", uid_counter);
	Obj *o = new_obj (name, ty);
	o->next = fn_locals;
	fn_locals = o;
	/* not in scope: invisible to source code */
	return o;
}

static Obj *new_global(char *name, Type *ty) {
	Obj *o = new_obj (name, ty);
	o->is_global = true;
	o->is_static_dur = true;
	if (globals_tail) {
		globals_tail->next = o;
	} else {
		prog->globals = o;
	}
	globals_tail = o;
	scope_push (name, o);
	return o;
}

static char *new_label(const char *hint) {
	return xasprintf (".%s%d", hint, label_counter++);
}

/* token cursor */
static bool is_punct(const char *s) {
	return tk->kind == TK_PUNCT && !strcmp (tk->str, s);
}

static bool is_kw(const char *s) {
	return tk->kind == TK_ID && !strcmp (tk->str, s);
}

static bool eat(const char *s) {
	if ((tk->kind == TK_PUNCT || tk->kind == TK_ID) && tk->str && !strcmp (tk->str, s)) {
		tk = tk->next;
		return true;
	}
	return false;
}

static void expect(const char *s) {
	if (!eat (s)) {
		error_tok (tk, "expected '%s'", s);
	}
}

/* ------------------------------------------------------------ AST nodes */

static Node *new_node(NodeKind kind, Token *tok) {
	Node *n = xcalloc (1, sizeof(Node));
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
static Type *value_type(Type *ty) {
	if (ty->kind == TY_INT) {
		return ty->is_unsigned? ty_u64: ty_i64;
	}
	if (ty->kind == TY_ARRAY) {
		return ptr_to (ty->base);
	}
	return ty;
}

/* decay arrays, keep class values as-is */
static Node *rvalize(Node *n) {
	if (n->ty && n->ty->kind == TY_ARRAY) {
		Node *a = new_node (ND_ADDR, n->tok);
		a->lhs = n;
		a->ty = ptr_to (n->ty->base);
		return a;
	}
	return n;
}

static Node *new_binary(NodeKind kind, Node *lhs, Node *rhs, Token *tok);

/* convert to boolean context i64 */
static Node *to_bool(Node *n) {
	if (n->ty->kind == TY_F64) {
		return new_binary (ND_NE, n, new_fnum (0.0, n->tok), n->tok);
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

static Node *new_binary(NodeKind kind, Node *lhs, Node *rhs, Token *tok) {
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
			n->ty = (value_type (lhs->ty)->is_unsigned ||
			         value_type (rhs->ty)->is_unsigned)? ty_u64: ty_i64;
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
		n->ty = (value_type (lhs->ty)->is_unsigned ||
		         value_type (rhs->ty)->is_unsigned)? ty_u64: ty_i64;
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
		lhs = to_bool (lhs);
		rhs = to_bool (rhs);
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

static Node *new_unary(NodeKind kind, Node *lhs, Token *tok) {
	Node *n = new_node (kind, tok);
	n->lhs = lhs;
	switch (kind) {
	case ND_NEG:
		n->ty = lhs->ty->kind == TY_F64? ty_f64: ty_i64;
		break;
	case ND_NOT:
		n->lhs = to_bool (rvalize (lhs));
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

static Node *new_assign(Node *lhs, Node *rhs, Token *tok) {
	if (!is_lvalue (lhs)) {
		error_tok (tok, "not an assignable expression");
	}
	if (lhs->ty->kind == TY_ARRAY) {
		error_tok (tok, "cannot assign to an array");
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
	n->ty = value_type (lhs->ty);
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

static bool is_type_start(Token *t) {
	if (t->kind != TK_ID) {
		return false;
	}
	return builtin_type (t->str) || find_class (t->str);
}

/* parse base type + leading stars */
static Type *parse_typespec(void) {
	Type *ty = builtin_type (tk->str);
	if (!ty) {
		ty = find_class (tk->str);
	}
	if (!ty) {
		error_tok (tk, "unknown type '%s'", tk->str);
	}
	tk = tk->next;
	while (is_punct ("*")) {
		tk = tk->next;
		ty = ptr_to (ty);
	}
	return ty;
}

/* --------------------------------------------------------- const eval */

static int64_t eval_const(Node *n) {
	switch (n->kind) {
	case ND_NUM: return n->ival;
	case ND_FNUM: return (int64_t)n->fval;
	case ND_NEG: return -eval_const (n->lhs);
	case ND_BITNOT: return ~eval_const (n->lhs);
	case ND_NOT: return !eval_const (n->lhs);
	case ND_CAST: return eval_const (n->lhs);
	case ND_ADD: return eval_const (n->lhs) + eval_const (n->rhs);
	case ND_SUB: return eval_const (n->lhs) - eval_const (n->rhs);
	case ND_MUL: return eval_const (n->lhs) * eval_const (n->rhs);
	case ND_DIV: {
		int64_t d = eval_const (n->rhs);
		if (!d) error_tok (n->tok, "division by zero in constant");
		return eval_const (n->lhs) / d;
	}
	case ND_MOD: {
		int64_t d = eval_const (n->rhs);
		if (!d) error_tok (n->tok, "division by zero in constant");
		return eval_const (n->lhs) % d;
	}
	case ND_AND: return eval_const (n->lhs) & eval_const (n->rhs);
	case ND_OR: return eval_const (n->lhs) | eval_const (n->rhs);
	case ND_XOR: return eval_const (n->lhs) ^ eval_const (n->rhs);
	case ND_SHL: return eval_const (n->lhs) << (eval_const (n->rhs) & 63);
	case ND_SHR: {
		Type *t = value_type (n->lhs->ty);
		if (t->is_unsigned) {
			return (int64_t)((uint64_t)eval_const (n->lhs) >> (eval_const (n->rhs) & 63));
		}
		return eval_const (n->lhs) >> (eval_const (n->rhs) & 63);
	}
	case ND_EQ: return eval_const (n->lhs) == eval_const (n->rhs);
	case ND_NE: return eval_const (n->lhs) != eval_const (n->rhs);
	case ND_LT: return eval_const (n->lhs) < eval_const (n->rhs);
	case ND_LE: return eval_const (n->lhs) <= eval_const (n->rhs);
	default:
		error_tok (n->tok, "not a constant expression");
		return 0;
	}
}

/* ---------------------------------------------------------- expressions */

static Node *expr(void);        /* assignment level */
static Node *comma_expr(void);
static Node *unary(void);
static Node *stmt(void);
static Node *block_stmt(void);

static Node *new_str_node(char *data, int len, Token *tok) {
	Node *n = new_node (ND_STR, tok);
	StrLit *s = xcalloc (1, sizeof(StrLit));
	s->data = data;
	s->len = len;
	s->id = prog->nstrings++;
	s->next = prog->strings;
	prog->strings = s;
	n->str = data;
	n->str_len = len;
	n->str_id = s->id;
	n->ty = ptr_to (ty_u8);
	return n;
}

static Node *make_call(Obj *fn, Node *args, int nargs, Token *tok);

/* sentinel default for `=lastclass` params, resolved per call site */
static Node nd_lastclass;

/* HolyC name of a type with pointer/array levels stripped (for lastclass) */
static char *holyc_type_name(Type *ty) {
	while (ty->kind == TY_PTR || ty->kind == TY_ARRAY) {
		ty = ty->base;
	}
	switch (ty->kind) {
	case TY_CLASS: return ty->name;
	case TY_F64: return "F64";
	case TY_VOID: return "U0";
	case TY_INT: {
		static char *names[2][4] = {
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
static Node *call_named(const char *name, Node *args, int nargs, Token *tok) {
	Obj *fn = find_func (name);
	if (!fn) {
		error_tok (tok, "runtime function '%s' is not declared (missing prelude?)", name);
	}
	return make_call (fn, args, nargs, tok);
}

/* Fill default arguments, verify count, insert conversions. args is the
 * chain of provided args, NULL nodes mark holes from `f(,x)`. */
static Node *make_call(Obj *fn, Node *args, int nargs, Token *tok) {
	Node *n = new_node (ND_CALL, tok);
	n->func = fn;
	n->ty = value_type (fn->ty->base? fn->ty->base: ty_i64);
	/* collect into array for easy manipulation */
	Node *argv[256];
	int i, argc = 0;
	for (Node *a = args; a; a = a->next) {
		if (argc >= 256) {
			error_tok (tok, "too many arguments");
		}
		argv[argc++] = a;
	}
	(void)nargs;
	if (!fn->is_variadic && argc > fn->nparams) {
		error_tok (tok, "too many arguments to %s() (takes %d)", fn->name, fn->nparams);
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
				error_tok (tok, "missing argument %d in call to %s() and no default", i + 1, fn->name);
			}
			a = fn->defaults[i];
			if (a == &nd_lastclass) {
				if (!prev_ty) {
					error_tok (tok, "lastclass argument %d in call to %s() has no previous argument", i + 1, fn->name);
				}
				char *nm = holyc_type_name (prev_ty);
				a = new_str_node (xstrdup (nm), strlen (nm), tok);
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
			error_tok (tok, "empty variadic argument");
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
		Node *c = xmalloc (sizeof(Node));
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
static Node *make_indirect_call(Node *callee, Node *args, Token *tok) {
	Node *n = new_node (ND_CALL, tok);
	n->lhs = callee;
	Type *fnty = NULL;
	if (callee->ty->kind == TY_PTR && callee->ty->base && callee->ty->base->kind == TY_FUNC) {
		fnty = callee->ty->base;
	}
	n->ty = fnty && fnty->base? value_type (fnty->base): ty_i64;
	for (Node *a = args; a; a = a->next) {
		if (a->kind == ND_NOP) {
			error_tok (tok, "default arguments require a direct call");
		}
	}
	n->args = args;
	int cnt = 0;
	for (Node *a = args; a; a = a->next) cnt++;
	n->nfixed = cnt;
	return n;
}

static Node *parse_args(void) {
	/* returns chain; holes become ND_NOP nodes */
	Node head = {0};
	Node *cur = &head;
	bool first = true;
	while (!is_punct (")")) {
		if (!first) {
			expect (",");
		}
		first = false;
		if (is_punct (",") || is_punct (")")) {
			Node *hole = new_node (ND_NOP, tk);
			hole->ty = ty_i64;
			cur->next = hole;
			cur = hole;
			continue;
		}
		Node *a = rvalize (expr ());
		cur->next = a;
		cur = a;
	}
	expect (")");
	return head.next;
}

static Node *primary(void) {
	Token *t = tk;
	if (eat ("(")) {
		Node *n = comma_expr ();
		expect (")");
		return n;
	}
	if (t->kind == TK_NUM) {
		tk = tk->next;
		return new_num (t->ival, t);
	}
	if (t->kind == TK_CHR) {
		tk = tk->next;
		return new_num (t->ival, t);
	}
	if (t->kind == TK_FNUM) {
		tk = tk->next;
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
		char *buf = xmalloc (len + 1);
		int off = 0;
		for (Token *s = t; s != q; s = s->next) {
			memcpy (buf + off, s->str, s->len);
			off += s->len;
		}
		buf[len] = 0;
		tk = q;
		return new_str_node (buf, len, t);
	}
	if (is_kw ("sizeof")) {
		tk = tk->next;
		bool paren = eat ("(");
		Node *n;
		if (paren && is_type_start (tk)) {
			Type *ty = parse_typespec ();
			n = new_num (ty->size, t);
		} else {
			Node *e = paren? comma_expr (): unary ();
			n = new_num (e->ty->size, t);
		}
		if (paren) {
			expect (")");
		}
		return n;
	}
	if (is_kw ("offset")) {
		tk = tk->next;
		expect ("(");
		Type *cls = is_type_start (tk)? parse_typespec (): NULL;
		if (!cls || cls->kind != TY_CLASS) {
			error_tok (t, "offset(Class.member) expects a class name");
		}
		expect (".");
		if (tk->kind != TK_ID) {
			error_tok (tk, "expected member name");
		}
		Member *m = find_member (cls, tk->str);
		if (!m) {
			error_tok (tk, "no member '%s' in class %s", tk->str, cls->name);
		}
		tk = tk->next;
		expect (")");
		return new_num (m->offset, t);
	}
	if (is_punct ("$$")) {
		tk = tk->next;
		if (in_class_body) {
			return new_num (class_dol_offset, t);
		}
		/* current address in the generated code (TempleOS RIP) */
		Obj *fn = find_func ("__hc_rip");
		if (!fn) {
			error_tok (t, "'$$' needs the runtime prelude");
		}
		return make_call (fn, NULL, 0, t);
	}
	if (t->kind == TK_ID) {
		Obj *var = find_var (t->str);
		if (var) {
			tk = tk->next;
			return new_var_node (var, t);
		}
		Obj *fn = find_func (t->str);
		if (fn) {
			tk = tk->next;
			if (eat ("(")) {
				Node *args = parse_args ();
				return make_call (fn, args, 0, t);
			}
			/* paren-less call: Dir; Ret = F; etc. */
			return make_call (fn, NULL, 0, t);
		}
		error_tok (t, "undefined symbol '%s'", t->str);
	}
	error_tok (t, "expected an expression");
	return NULL;
}

/* lower `lval OP= x` and ++/-- via pointer temp when lval is complex */
static Node *lval_addr_temp(Node *lval, Node **out_deref, Token *t) {
	if (lval->kind == ND_VAR) {
		*out_deref = lval;
		return NULL; /* no setup needed */
	}
	Obj *tmp = new_temp (ptr_to (lval->ty));
	Node *addr = new_unary (ND_ADDR, lval, t);
	addr->ty = ptr_to (lval->ty);
	Node *setup = new_assign (new_var_node (tmp, t), addr, t);
	Node *deref = new_unary (ND_DEREF, new_var_node (tmp, t), t);
	deref->ty = lval->ty;
	*out_deref = deref;
	return setup;
}

static Node *incdec(Node *lval, int delta, bool post, Token *t) {
	if (!is_lvalue (lval)) {
		error_tok (t, "++/-- needs an lvalue");
	}
	Node *place, *setup = lval_addr_temp (lval, &place, t);
	Node *one = new_num (delta, t);
	Node *val;
	if (post) {
		/* (old = place, place = old + 1, old) */
		Obj *old = new_temp (value_type (place->ty));
		Node *save = new_assign (new_var_node (old, t), place, t);
		Node *upd = new_assign (place, new_binary (ND_ADD, new_var_node (old, t), one, t), t);
		val = new_binary (ND_COMMA, save, new_binary (ND_COMMA, upd, new_var_node (old, t), t), t);
	} else {
		val = new_assign (place, new_binary (ND_ADD, place, one, t), t);
	}
	if (setup) {
		val = new_binary (ND_COMMA, setup, val, t);
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
static Node *subint_access(Node *base, Token *t) {
	Type *view = subint_view_type (tk->str);
	if (!view) {
		error_tok (tk, "no member '%s' in an integer", tk->str);
	}
	if (view->size >= base->ty->size) {
		error_tok (tk, "sub-int view '%s' needs a wider int than %s",
			tk->str, base->ty->size == 1? "a byte":
			base->ty->size == 2? "U16": "U32");
	}
	if (!is_lvalue (base)) {
		error_tok (t, "sub-int access needs an addressable value");
	}
	/* narrow params live sign-extended in a full 64-bit slot; a store
	 * through a view would leave the slot badly extended */
	if (base->kind == ND_VAR && base->var->is_param && base->ty->size < 8) {
		error_tok (t, "sub-int access on a narrow parameter; copy it to a local");
	}
	Type *arr = array_of (view, base->ty->size / view->size);
	Node *a = new_unary (ND_ADDR, base, t);
	a->ty = ptr_to (base->ty);
	Node *d = new_unary (ND_DEREF, new_cast (a, ptr_to (arr)), t);
	d->ty = arr;
	tk = tk->next;
	return d;
}

static Node *postfix(void) {
	Node *n = primary ();
	for (;;) {
		Token *t = tk;
		if (is_punct ("(")) {
			/* postfix cast or indirect call */
			if (is_type_start (tk->next)) {
				tk = tk->next;
				Type *ty = parse_typespec ();
				expect (")");
				n = new_cast (rvalize (n), ty);
				continue;
			}
			tk = tk->next;
			Node *args = parse_args ();
			n = make_indirect_call (rvalize (n), args, t);
			continue;
		}
		if (eat ("[")) {
			Node *idx = comma_expr ();
			expect ("]");
			Node *sum = new_binary (ND_ADD, n, idx, t);
			if (!is_ptrish (sum->ty) && sum->ty->kind != TY_PTR) {
				error_tok (t, "subscript on a non-pointer");
			}
			Node *d = new_unary (ND_DEREF, sum, t);
			if (sum->ty->kind != TY_PTR || !sum->ty->base) {
				error_tok (t, "cannot index this expression");
			}
			d->ty = sum->ty->base;
			n = d;
			continue;
		}
		if (is_punct (".") || is_punct ("->")) {
			bool arrow = is_punct ("->");
			tk = tk->next;
			if (tk->kind != TK_ID) {
				error_tok (tk, "expected member name");
			}
			Node *base = n;
			if (arrow) {
				base = rvalize (n);
				if (base->ty->kind != TY_PTR || !base->ty->base) {
					error_tok (t, "'->' on a non-pointer");
				}
				Node *d = new_unary (ND_DEREF, base, t);
				d->ty = base->ty->base;
				base = d;
			}
			if (base->ty->kind == TY_INT) {
				n = subint_access (base, t);
				continue;
			}
			if (base->ty->kind != TY_CLASS) {
				error_tok (t, "member access on a non-class value");
			}
			Member *m = find_member (base->ty, tk->str);
			if (!m) {
				error_tok (tk, "no member '%s' in class %s", tk->str,
					base->ty->name? base->ty->name: "?");
			}
			Node *mn = new_node (ND_MEMBER, t);
			mn->lhs = base;
			mn->member_ref = m;
			mn->ty = m->ty;
			tk = tk->next;
			n = mn;
			continue;
		}
		if (is_punct ("++") || is_punct ("--")) {
			int d = is_punct ("++")? 1: -1;
			tk = tk->next;
			n = incdec (n, d, true, t);
			continue;
		}
		break;
	}
	return n;
}

static Node *unary(void) {
	Token *t = tk;
	if (eat ("+")) {
		return unary ();
	}
	if (eat ("-")) {
		Node *n = rvalize (unary ());
		if (n->kind == ND_NUM) {
			n->ival = -n->ival;
			return n;
		}
		if (n->kind == ND_FNUM) {
			n->fval = -n->fval;
			return n;
		}
		return new_unary (ND_NEG, n, t);
	}
	if (eat ("!")) {
		return new_unary (ND_NOT, unary (), t);
	}
	if (eat ("~")) {
		return new_unary (ND_BITNOT, unary (), t);
	}
	if (eat ("*")) {
		Node *n = rvalize (unary ());
		if (n->ty->kind != TY_PTR || !n->ty->base) {
			error_tok (t, "dereference of a non-pointer");
		}
		Node *d = new_unary (ND_DEREF, n, t);
		d->ty = n->ty->base;
		return d;
	}
	if (eat ("&")) {
		/* &FuncName -> function pointer */
		if (tk->kind == TK_ID && !find_var (tk->str)) {
			Obj *fn = find_func (tk->str);
			if (fn) {
				Node *n = new_node (ND_FUNCNAME, t);
				n->func = fn;
				n->ty = ptr_to (fn->ty);
				tk = tk->next;
				return n;
			}
		}
		Node *n = unary ();
		if (!is_lvalue (n)) {
			error_tok (t, "'&' needs an lvalue");
		}
		Node *a = new_unary (ND_ADDR, n, t);
		a->ty = ptr_to (n->ty);
		return a;
	}
	if (is_punct ("++") || is_punct ("--")) {
		int d = is_punct ("++")? 1: -1;
		tk = tk->next;
		return incdec (unary (), d, false, t);
	}
	return postfix ();
}

/* HolyC precedence, tightest first:
 *   ` << >>  |  * / %  |  &  |  ^  |  |  |  + -  |  < > <= >= (chained)
 *   |  == !=  |  &&  |  ^^  |  ||  |  assignment
 */
static Node *powshift(void) {
	Node *n = unary ();
	for (;;) {
		Token *t = tk;
		if (eat ("`")) {
			n = new_binary (ND_POW, n, unary (), t);
		} else if (eat ("<<")) {
			n = new_binary (ND_SHL, n, unary (), t);
		} else if (eat (">>")) {
			n = new_binary (ND_SHR, n, unary (), t);
		} else {
			return n;
		}
	}
}

static Node *mul(void) {
	Node *n = powshift ();
	for (;;) {
		Token *t = tk;
		if (eat ("*")) {
			n = new_binary (ND_MUL, n, powshift (), t);
		} else if (eat ("/")) {
			n = new_binary (ND_DIV, n, powshift (), t);
		} else if (eat ("%")) {
			n = new_binary (ND_MOD, n, powshift (), t);
		} else {
			return n;
		}
	}
}

static Node *bitand_(void) {
	Node *n = mul ();
	while (is_punct ("&")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_AND, n, mul (), t);
	}
	return n;
}

static Node *bitxor_(void) {
	Node *n = bitand_ ();
	while (is_punct ("^")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_XOR, n, bitand_ (), t);
	}
	return n;
}

static Node *bitor_(void) {
	Node *n = bitxor_ ();
	while (is_punct ("|")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_OR, n, bitxor_ (), t);
	}
	return n;
}

static Node *addsub(void) {
	Node *n = bitor_ ();
	for (;;) {
		Token *t = tk;
		if (eat ("+")) {
			n = new_binary (ND_ADD, n, bitor_ (), t);
		} else if (eat ("-")) {
			n = new_binary (ND_SUB, n, bitor_ (), t);
		} else {
			return n;
		}
	}
}

/* relational with HolyC chaining: a<b<c => (a < (t=b)) && (t < c) */
static Node *relational(void) {
	Node *n = addsub ();
	Node *chain = NULL;
	for (;;) {
		Token *t = tk;
		NodeKind k;
		bool swap = false;
		if (is_punct ("<")) k = ND_LT;
		else if (is_punct ("<=")) k = ND_LE;
		else if (is_punct (">")) { k = ND_LT; swap = true; }
		else if (is_punct (">=")) { k = ND_LE; swap = true; }
		else break;
		tk = tk->next;
		Node *rhs = rvalize (addsub ());
		/* peek: is another relational op coming? */
		bool more = is_punct ("<") || is_punct ("<=") || is_punct (">") || is_punct (">=");
		Node *rhs_val = rhs;
		if (more) {
			Obj *tmp = new_temp (value_type (rhs->ty));
			rhs = new_assign (new_var_node (tmp, t), rhs, t);
			rhs_val = new_var_node (tmp, t);
		}
		Node *cmp = swap? new_binary (k, rhs, rvalize (n), t)
		                : new_binary (k, rvalize (n), rhs, t);
		chain = chain? new_binary (ND_LOGAND, chain, cmp, t): cmp;
		if (!more) {
			return chain;
		}
		n = rhs_val;
	}
	return chain? chain: n;
}

static Node *equality(void) {
	Node *n = relational ();
	for (;;) {
		Token *t = tk;
		if (eat ("==")) {
			n = new_binary (ND_EQ, n, relational (), t);
		} else if (eat ("!=")) {
			n = new_binary (ND_NE, n, relational (), t);
		} else {
			return n;
		}
	}
}

static Node *logand(void) {
	Node *n = equality ();
	while (is_punct ("&&")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_LOGAND, n, equality (), t);
	}
	return n;
}

static Node *logxor(void) {
	Node *n = logand ();
	while (is_punct ("^^")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_LOGXOR, n, logand (), t);
	}
	return n;
}

static Node *logor(void) {
	Node *n = logxor ();
	while (is_punct ("||")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_LOGOR, n, logxor (), t);
	}
	return n;
}

static Node *assign(void) {
	Node *n = logor ();
	Token *t = tk;
	static const struct { const char *op; NodeKind k; } comp[] = {
		{ "+=", ND_ADD }, { "-=", ND_SUB }, { "*=", ND_MUL },
		{ "/=", ND_DIV }, { "%=", ND_MOD }, { "&=", ND_AND },
		{ "|=", ND_OR }, { "^=", ND_XOR }, { "<<=", ND_SHL },
		{ ">>=", ND_SHR }, { NULL, 0 }
	};
	if (eat ("=")) {
		return new_assign (n, assign (), t);
	}
	for (int i = 0; comp[i].op; i++) {
		if (is_punct (comp[i].op)) {
			tk = tk->next;
			if (!is_lvalue (n)) {
				error_tok (t, "not an assignable expression");
			}
			Node *rhs = assign ();
			Node *place, *setup = lval_addr_temp (n, &place, t);
			Node *res = new_assign (place, new_binary (comp[i].k, place, rhs, t), t);
			return setup? new_binary (ND_COMMA, setup, res, t): res;
		}
	}
	return n;
}

static Node *expr(void) {
	return assign ();
}

static Node *comma_expr(void) {
	Node *n = expr ();
	while (is_punct (",")) {
		Token *t = tk;
		tk = tk->next;
		n = new_binary (ND_COMMA, n, expr (), t);
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

static void label_use(char *name, Token *t, bool define) {
	for (LabelRef *l = fn_labels; l; l = l->next) {
		if (!strcmp (l->name, name)) {
			if (define) {
				l->defined = true;
			}
			return;
		}
	}
	LabelRef *l = xcalloc (1, sizeof(LabelRef));
	l->name = name;
	l->tok = t;
	l->defined = define;
	l->next = fn_labels;
	fn_labels = l;
}

/* implicit Print/PutChars statements */
static Node *print_stmt(void) {
	Token *t = tk;
	bool ischar = t->kind == TK_CHR;
	Node *fmt = NULL;
	Node head = {0};
	Node *cur = &head;
	int nargs = 0;
	if (ischar) {
		if (t->len == 0) {
			/* '' expr : PutChars(expr) */
			tk = tk->next;
			Node *e = rvalize (expr ());
			expect (";");
			cur->next = e;
			return new_expr_stmt (call_named ("PutChars", head.next, 1, t), t);
		}
		tk = tk->next;
		expect (";");
		cur->next = new_num (t->ival, t);
		return new_expr_stmt (call_named ("PutChars", head.next, 1, t), t);
	}
	/* string statement */
	Node *s = primary (); /* handles adjacent concat */
	if (s->str_len == 0 && !is_punct (";") && !is_punct (",")) {
		/* "" fmt,args : variable format string */
		fmt = rvalize (expr ());
	} else {
		fmt = s;
	}
	cur->next = fmt;
	cur = fmt;
	nargs = 1;
	while (eat (",")) {
		Node *a = rvalize (expr ());
		cur->next = a;
		cur = a;
		nargs++;
	}
	expect (";");
	return new_expr_stmt (call_named ("Print", head.next, nargs, t), t);
}

/* variable declaration (local) starting at a type token */
static Node *local_decl(void) {
	Token *t = tk;
	Type *base = builtin_type (tk->str);
	if (!base) {
		base = find_class (tk->str);
	}
	tk = tk->next;
	Node head = {0};
	Node *cur = &head;
	bool first = true;
	while (!is_punct (";")) {
		if (!first) {
			expect (",");
		}
		first = false;
		Type *ty = base;
		while (eat ("*")) {
			ty = ptr_to (ty);
		}
		/* reg/noreg/no_warn qualifiers: skip */
		while (is_kw ("reg") || is_kw ("noreg")) {
			bool was_reg = is_kw ("reg");
			tk = tk->next;
			/* optional register name after 'reg' */
			if (was_reg && tk->kind == TK_ID && tk->next->kind == TK_ID) {
				tk = tk->next;
			}
		}
		/* function pointer declarator: (*name)(params) */
		if (is_punct ("(")) {
			tk = tk->next;
			expect ("*");
			if (tk->kind != TK_ID) {
				error_tok (tk, "expected name");
			}
			char *name = tk->str;
			tk = tk->next;
			expect (")");
			expect ("(");
			/* skip param list: types only matter for docs */
			int depth = 1;
			while (depth > 0 && tk->kind != TK_EOF) {
				if (is_punct ("(")) depth++;
				if (is_punct (")")) depth--;
				tk = tk->next;
			}
			Type *fnty = new_type (TY_FUNC, 8, 8);
			fnty->base = ty;
			Obj *var = new_local (name, ptr_to (fnty));
			if (eat ("=")) {
				Node *rhs = expr ();
				Node *a = new_assign (new_var_node (var, t), rhs, t);
				cur->next = new_expr_stmt (a, t);
				cur = cur->next;
			}
			continue;
		}
		if (tk->kind != TK_ID) {
			error_tok (tk, "expected variable name");
		}
		char *name = tk->str;
		Token *nt = tk;
		tk = tk->next;
		while (eat ("[")) {
			Node *len = comma_expr ();
			expect ("]");
			ty = array_of (ty, (int)eval_const (len));
		}
		Obj *var = new_local (name, ty);
		if (eat ("=")) {
			if (is_punct ("{")) {
				/* brace initializer for 1-D arrays */
				if (ty->kind != TY_ARRAY) {
					error_tok (tk, "brace initializer needs an array");
				}
				tk = tk->next;
				int idx = 0;
				while (!is_punct ("}")) {
					if (idx) {
						expect (",");
					}
					if (is_punct ("}")) {
						break;
					}
					Node *v = expr ();
					Node *dst = new_node (ND_DEREF, nt);
					Node *addr = new_binary (ND_ADD, new_var_node (var, nt), new_num (idx, nt), nt);
					dst->lhs = addr;
					dst->ty = ty->base;
					cur->next = new_expr_stmt (new_assign (dst, v, nt), nt);
					cur = cur->next;
					idx++;
				}
				expect ("}");
			} else {
				Node *rhs = expr ();
				if (ty->kind == TY_ARRAY && rhs->kind == ND_STR) {
					/* U8 buf[N] = "str": copy bytes incl. NUL */
					Node *a1 = new_var_node (var, nt);
					Node *args = rvalize (a1);
					args->next = rhs;
					rhs->next = new_num (rhs->str_len + 1, nt);
					cur->next = new_expr_stmt (call_named ("MemCpy", args, 3, nt), nt);
					cur = cur->next;
				} else {
					Node *a = new_assign (new_var_node (var, nt), rhs, nt);
					cur->next = new_expr_stmt (a, nt);
					cur = cur->next;
				}
			}
		}
	}
	expect (";");
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

static Node *switch_stmt(Token *t) {
	bool nobound = is_punct ("[");
	Node *cond;
	if (nobound) {
		expect ("[");
		cond = comma_expr ();
		expect ("]");
	} else {
		expect ("(");
		cond = comma_expr ();
		expect (")");
	}
	expect ("{");

	SwCtx sw = {0};
	sw.exit_label = new_label ("swend");
	sw.cur_group = -1;
	sw.next_case_val = 0;

	Obj *swval = new_temp (ty_i64);
	Node *setup = new_expr_stmt (new_assign (new_var_node (swval, t), rvalize (cond), t), t);

	char *save_break = break_label;
	break_label = sw.exit_label;

	/* First pass: parse body statements, recording case labels inline. */
	enter_scope ();
	while (!is_punct ("}")) {
		Token *ct = tk;
		if (is_kw ("case")) {
			tk = tk->next;
			SwCase *c = xcalloc (1, sizeof(SwCase));
			if (is_punct (":")) {
				c->lo = c->hi = sw.next_case_val;
			} else {
				c->lo = eval_const (expr ());
				c->hi = c->lo;
				if (eat ("...")) {
					c->hi = eval_const (expr ());
				}
			}
			expect (":");
			sw.next_case_val = c->hi + 1;
			c->label = new_label ("case");
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
				anchor->label = xasprintf ("porch%d", sw.cur_group);
				sw_append (&sw, anchor);
				sw.porch_dispatch_anchor = anchor;
			}
			sw_append (&sw, new_labelstmt (c->label, ct));
			continue;
		}
		if (is_kw ("default")) {
			tk = tk->next;
			expect (":");
			SwCase *c = xcalloc (1, sizeof(SwCase));
			c->is_default = true;
			c->label = new_label ("default");
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
		if (is_kw ("start") && tk->next->kind == TK_PUNCT && !strcmp (tk->next->str, ":")) {
			tk = tk->next->next;
			if (sw.cur_group >= 0) {
				error_tok (ct, "nested start:/end: groups are not supported");
			}
			if (sw.ngroups >= 64) {
				error_tok (ct, "too many sub_switch groups");
			}
			sw.cur_group = sw.ngroups++;
			if (!sw.grp_var) {
				sw.grp_var = new_temp (ty_i64);
			}
			sw.group_porch[sw.cur_group] = new_label ("porch");
			sw.group_end[sw.cur_group] = new_label ("gend");
			sw.in_porch = true;
			/* falling into the porch selects the first case of the group */
			sw_append (&sw, new_expr_stmt (new_assign (
				new_var_node (sw.grp_var, ct), new_num (-1, ct), ct), ct));
			sw_append (&sw, new_labelstmt (sw.group_porch[sw.cur_group], ct));
			break_label = sw.group_end[sw.cur_group];
			continue;
		}
		if (is_kw ("end") && tk->next->kind == TK_PUNCT && !strcmp (tk->next->str, ":")) {
			Token *et = tk;
			tk = tk->next->next;
			if (sw.cur_group < 0) {
				error_tok (et, "end: without start:");
			}
			sw_append (&sw, new_labelstmt (sw.group_end[sw.cur_group], et));
			sw.cur_group = -1;
			break_label = sw.exit_label;
			continue;
		}
		Node *s = stmt ();
		sw_append (&sw, s);
	}
	expect ("}");
	leave_scope ();
	break_label = save_break;

	if (sw.cur_group >= 0) {
		error_tok (t, "start: without end: in switch");
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
			test = new_binary (ND_EQ, v, new_num (c->lo, t), t);
		} else {
			Node *ge = new_binary (ND_LE, new_num (c->lo, t), new_var_node (swval, t), t);
			Node *le = new_binary (ND_LE, new_var_node (swval, t), new_num (c->hi, t), t);
			test = new_binary (ND_LOGAND, ge, le, t);
		}
		Node *br = new_node (ND_IF, t);
		br->cond = test;
		if (c->group >= 0) {
			/* stub: select case in group, enter porch */
			int idx = case_idx_in_group[c->group]++;
			c->hi = idx; /* reuse: idx within group for porch dispatch */
			Node *stub = new_node (ND_BLOCK, t);
			Node *sel = new_expr_stmt (new_assign (
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
				br->cond = new_binary (ND_EQ, new_var_node (sw.grp_var, t),
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

static Node *stmt(void) {
	Token *t = tk;
	if (is_punct ("{")) {
		return block_stmt ();
	}
	if (eat (";")) {
		return new_node (ND_NOP, t);
	}
	if (is_kw ("if")) {
		tk = tk->next;
		expect ("(");
		Node *n = new_node (ND_IF, t);
		n->cond = to_bool (rvalize (comma_expr ()));
		expect (")");
		n->then = stmt ();
		if (is_kw ("else")) {
			tk = tk->next;
			n->els = stmt ();
		}
		return n;
	}
	if (is_kw ("while")) {
		tk = tk->next;
		expect ("(");
		Node *n = new_node (ND_WHILE, t);
		n->cond = to_bool (rvalize (comma_expr ()));
		expect (")");
		char *end = new_label ("wend");
		char *save = break_label;
		break_label = end;
		n->then = stmt ();
		break_label = save;
		Node *blk = new_node (ND_BLOCK, t);
		blk->body = n;
		n->next = new_labelstmt (end, t);
		return blk;
	}
	if (is_kw ("do")) {
		tk = tk->next;
		Node *n = new_node (ND_DOWHILE, t);
		char *end = new_label ("dend");
		char *save = break_label;
		break_label = end;
		n->then = stmt ();
		break_label = save;
		if (!is_kw ("while")) {
			error_tok (tk, "expected 'while' after do body");
		}
		tk = tk->next;
		expect ("(");
		n->cond = to_bool (rvalize (comma_expr ()));
		expect (")");
		expect (";");
		Node *blk = new_node (ND_BLOCK, t);
		blk->body = n;
		n->next = new_labelstmt (end, t);
		return blk;
	}
	if (is_kw ("for")) {
		tk = tk->next;
		expect ("(");
		Node *n = new_node (ND_FOR, t);
		enter_scope ();
		if (!is_punct (";")) {
			if (is_type_start (tk) && tk->next->kind == TK_ID) {
				n->init = local_decl ();
			} else {
				n->init = new_expr_stmt (comma_expr (), t);
				expect (";");
			}
		} else {
			expect (";");
		}
		if (!is_punct (";")) {
			n->cond = to_bool (rvalize (comma_expr ()));
		}
		expect (";");
		if (!is_punct (")")) {
			n->inc = new_expr_stmt (comma_expr (), t);
		}
		expect (")");
		char *end = new_label ("fend");
		char *save = break_label;
		break_label = end;
		n->then = stmt ();
		break_label = save;
		leave_scope ();
		Node *blk = new_node (ND_BLOCK, t);
		blk->body = n;
		n->next = new_labelstmt (end, t);
		return blk;
	}
	if (is_kw ("switch")) {
		tk = tk->next;
		return switch_stmt (t);
	}
	if (is_kw ("return")) {
		tk = tk->next;
		Node *n = new_node (ND_RETURN, t);
		if (!is_punct (";")) {
			Node *e = rvalize (comma_expr ());
			Type *rt = cur_fn->ty->base;
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
				expect (";");
				return blk;
			}
			n->lhs = e;
		}
		expect (";");
		return n;
	}
	if (is_kw ("break")) {
		tk = tk->next;
		expect (";");
		if (!break_label) {
			error_tok (t, "break outside of a loop or switch");
		}
		return new_goto (break_label, t);
	}
	if (is_kw ("continue")) {
		error_tok (t, "HolyC has no 'continue' statement; use goto (see doc/language.md)");
	}
	if (is_kw ("goto")) {
		tk = tk->next;
		if (tk->kind != TK_ID) {
			error_tok (tk, "expected label after goto");
		}
		char *name = tk->str;
		tk = tk->next;
		expect (";");
		label_use (name, t, false);
		return new_goto (xasprintf ("u_%s", name), t);
	}
	if (is_kw ("try")) {
		tk = tk->next;
		Node *n = new_node (ND_TRY, t);
		n->then = block_stmt ();
		if (!is_kw ("catch")) {
			error_tok (tk, "expected 'catch' after try block");
		}
		tk = tk->next;
		n->els = block_stmt ();
		return n;
	}
	if (is_kw ("no_warn")) {
		while (!eat (";")) {
			if (tk->kind == TK_EOF) {
				error_tok (t, "unterminated no_warn");
			}
			tk = tk->next;
		}
		return new_node (ND_NOP, t);
	}
	if (is_kw ("asm")) {
		error_tok (t, "inline asm is not supported by aholyc (portable backends only)");
	}
	if (is_kw ("lock")) {
		/* compile the block without lock semantics */
		tk = tk->next;
		return block_stmt ();
	}
	/* label? ident ':' (not '::') */
	if (t->kind == TK_ID && t->next && t->next->kind == TK_PUNCT &&
	    !strcmp (t->next->str, ":") && !is_type_start (t)) {
		char *name = t->str;
		tk = t->next->next;
		label_use (name, t, true);
		return new_labelstmt (xasprintf ("u_%s", name), t);
	}
	/* declaration? */
	if (is_type_start (t)) {
		Token *n1 = t->next;
		/* distinguish `I64 x;` from expression starting with cast-able name */
		if (n1->kind == TK_ID || (n1->kind == TK_PUNCT &&
		    (!strcmp (n1->str, "*") || !strcmp (n1->str, "("))) ) {
			/* class name followed by '(' would be odd; require ident/star */
			if (n1->kind == TK_ID || !strcmp (n1->str, "*") ||
			    (n1->kind == TK_PUNCT && !strcmp (n1->str, "(") &&
			     n1->next && n1->next->kind == TK_PUNCT && !strcmp (n1->next->str, "*"))) {
				return local_decl ();
			}
		}
	}
	/* implicit print statements */
	if (t->kind == TK_STR || t->kind == TK_CHR) {
		return print_stmt ();
	}
	Node *e = comma_expr ();
	expect (";");
	return new_expr_stmt (e, t);
}

static Node *block_stmt(void) {
	Token *t = tk;
	expect ("{");
	enter_scope ();
	Node head = {0};
	Node *cur = &head;
	while (!is_punct ("}")) {
		if (tk->kind == TK_EOF) {
			error_tok (t, "unterminated block");
		}
		Node *s = stmt ();
		cur->next = s;
		while (cur->next) {
			cur = cur->next;
		}
	}
	expect ("}");
	leave_scope ();
	Node *n = new_node (ND_BLOCK, t);
	n->body = head.next;
	return n;
}

/* --------------------------------------------------------- declarations */

static void check_labels(void) {
	for (LabelRef *l = fn_labels; l; l = l->next) {
		if (!l->defined) {
			error_tok (l->tok, "goto to undefined label '%s'", l->name);
		}
	}
	fn_labels = NULL;
}

/* parse params: (type name=dft, ..., ...) — returns param chain */
static void parse_params(Obj *fn) {
	expect ("(");
	Obj head = {0};
	Obj *cur = &head;
	Node *defaults[256];
	int n = 0;
	bool first = true;
	while (!is_punct (")")) {
		if (!first) {
			expect (",");
		}
		first = false;
		if (eat ("...")) {
			fn->is_variadic = true;
			break;
		}
		if (!is_type_start (tk)) {
			error_tok (tk, "expected parameter type");
		}
		Type *ty = parse_typespec ();
		/* (U0) means no params */
		if (ty == ty_u0 && is_punct (")") && n == 0) {
			break;
		}
		char *name = NULL;
		if (tk->kind == TK_ID) {
			name = tk->str;
			tk = tk->next;
		}
		while (eat ("[")) {
			/* array param decays to pointer; size ignored */
			if (!is_punct ("]")) {
				eval_const (expr ());
			}
			expect ("]");
			ty = ptr_to (ty);
		}
		if (ty->kind == TY_CLASS) {
			error_tok (tk, "class values cannot be parameters; pass a pointer");
		}
		Obj *p = new_obj (name? name: xasprintf ("arg%d", n), ty);
		defaults[n] = NULL;
		if (eat ("=")) {
			if (eat ("lastclass")) {
				defaults[n] = &nd_lastclass;
			} else {
				defaults[n] = rvalize (expr ());
				if (ty->kind == TY_F64) {
					defaults[n] = to_f64 (defaults[n]);
				} else if (defaults[n]->ty->kind == TY_F64) {
					defaults[n] = to_int (defaults[n]);
				}
			}
		}
		n++;
		if (n >= 250) {
			error_tok (tk, "too many parameters");
		}
		cur->next = p;
		cur = p;
	}
	expect (")");
	if (fn->is_variadic) {
		/* implicit argc/argv params */
		Obj *pargc = new_obj (xstrdup ("argc"), ty_i64);
		Obj *pargv = new_obj (xstrdup ("argv"), ptr_to (ty_i64));
		cur->next = pargc;
		pargc->next = pargv;
		cur = pargv;
	}
	for (Obj *p = head.next; p; p = p->next) {
		p->is_param = true;
	}
	fn->params = head.next;
	fn->nparams = n;
	fn->defaults = xmalloc (sizeof(Node *) * (n? n: 1));
	memcpy (fn->defaults, defaults, sizeof(Node *) * n);
}

static void add_func(Obj *fn) {
	if (funcs_tail) {
		funcs_tail->next = fn;
	} else {
		prog->funcs = fn;
	}
	funcs_tail = fn;
}

static void parse_class(bool is_union) {
	tk = tk->next; /* class/union */
	if (tk->kind != TK_ID) {
		error_tok (tk, "expected class name");
	}
	char *name = tk->str;
	tk = tk->next;
	Type *ty = find_class (name);
	if (!ty) {
		ty = new_type (TY_CLASS, 0, 1);
		ty->name = name;
		ty->is_union = is_union;
		ClassEnt *c = xcalloc (1, sizeof(ClassEnt));
		c->name = name;
		c->ty = ty;
		c->next = classes;
		classes = c;
	}
	if (eat (";")) {
		return; /* forward declaration */
	}
	if (eat (":")) {
		if (tk->kind != TK_ID) {
			error_tok (tk, "expected parent class name");
		}
		Type *parent = find_class (tk->str);
		if (!parent) {
			error_tok (tk, "unknown parent class '%s'", tk->str);
		}
		ty->parent = parent;
		tk = tk->next;
	}
	expect ("{");
	/* TempleOS layout: members are packed back to back, no alignment or
	 * padding.  "$$ = expr;" moves the offset for the next member; the
	 * most negative offset grows the class like TempleOS neg_offset. */
	int off = ty->parent? ty->parent->size: 0;
	int align = ty->parent? ty->parent->align: 1;
	int neg = 0;
	int union_base = 0;
	bool save_in_class = in_class_body;
	in_class_body = true;
	Member head = {0};
	Member *cur = &head;
	while (!is_punct ("}")) {
		class_dol_offset = is_union? union_base: off;
		if (eat (";")) {
			continue;
		}
		if (is_punct ("$$")) {
			tk = tk->next;
			expect ("=");
			int v = (int)eval_const (expr ());
			expect (";");
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
		if (!is_type_start (tk)) {
			error_tok (tk, "expected member type");
		}
		Type *base = parse_typespec ();
		/* strip stars parsed by typespec: they apply to first declarator only
		 * in C; HolyC code in practice writes one declarator per star usage.
		 * parse_typespec consumed them, keep as-is for first; extra
		 * declarators share the starred type. */
		bool first = true;
		for (;;) {
			Type *mty = base;
			if (!first) {
				while (eat ("*")) {
					mty = ptr_to (mty);
				}
			}
			first = false;
			if (tk->kind != TK_ID) {
				error_tok (tk, "expected member name");
			}
			char *mname = tk->str;
			tk = tk->next;
			while (eat ("[")) {
				Node *len = comma_expr ();
				expect ("]");
				mty = array_of (mty, (int)eval_const (len));
			}
			if (mty->kind == TY_CLASS && mty->size == 0) {
				error_tok (tk, "member of incomplete class type");
			}
			Member *m = xcalloc (1, sizeof(Member));
			m->name = mname;
			m->ty = mty;
			int a = mty->align? mty->align: 1;
			if (is_union) {
				m->offset = union_base;
				if (union_base + mty->size > off) {
					off = union_base + mty->size;
				}
			} else {
				m->offset = off;
				off += mty->size;
			}
			if (a > align) {
				align = a;
			}
			cur->next = m;
			cur = m;
			class_dol_offset = is_union? union_base: off;
			if (!eat (",")) {
				break;
			}
		}
		expect (";");
	}
	expect ("}");
	eat (";");
	in_class_body = save_in_class;
	ty->members = head.next;
	ty->align = align;
	ty->size = off + neg;
}

/* function definition or declaration after type+name(  */
static void parse_func(Type *ret, char *name, bool is_extern, bool is_public) {
	Obj *fn = find_func (name);
	bool fresh = !fn;
	if (fresh) {
		fn = new_obj (name, NULL);
		fn->is_func = true;
	}
	Type *fnty = new_type (TY_FUNC, 8, 8);
	fnty->base = ret;
	fn->ty = fnty;
	fn->is_extern = is_extern;
	if (is_extern && tk->file && !strcmp (tk->file, "<prelude>")) {
		fn->from_prelude = true;
	}
	if (is_public) {
		fn->is_public = true;
	}
	enter_scope ();
	Obj *save_locals = fn_locals;
	Obj *save_fn = cur_fn;
	LabelRef *save_labels = fn_labels;
	fn_locals = NULL;
	fn_labels = NULL;
	cur_fn = fn;
	parse_params (fn);
	if (fresh) {
		add_func (fn);
	}
	if (eat (";")) {
		leave_scope ();
		fn_locals = save_locals;
		fn_labels = save_labels;
		cur_fn = save_fn;
		return;
	}
	if (fn->body) {
		error_tok (tk, "redefinition of function %s", name);
	}
	/* params visible in body scope */
	for (Obj *p = fn->params; p; p = p->next) {
		scope_push (p->name, p);
	}
	fn->body = block_stmt ();
	check_labels ();
	fn->locals = fn_locals;
	leave_scope ();
	fn_locals = save_locals;
	fn_labels = save_labels;
	cur_fn = save_fn;
}

/* global variable declaration(s); initializers become startup stmts */
static Node *global_decl(Type *base, bool is_extern, bool is_public) {
	Node head = {0};
	Node *cur = &head;
	bool first = true;
	Token *t = tk;
	while (!is_punct (";")) {
		if (!first) {
			expect (",");
		}
		first = false;
		Type *ty = base;
		if (!first) {
			/* stars per declarator after the first */
		}
		while (eat ("*")) {
			ty = ptr_to (ty);
		}
		if (is_punct ("(")) {
			/* global function pointer */
			tk = tk->next;
			expect ("*");
			char *name = tk->str;
			tk = tk->next;
			expect (")");
			expect ("(");
			int depth = 1;
			while (depth > 0 && tk->kind != TK_EOF) {
				if (is_punct ("(")) depth++;
				if (is_punct (")")) depth--;
				tk = tk->next;
			}
			Type *fnty = new_type (TY_FUNC, 8, 8);
			fnty->base = ty;
			Obj *var = new_global (name, ptr_to (fnty));
			var->is_extern = is_extern;
			var->is_public = is_public;
			if (eat ("=")) {
				Node *rhs = expr ();
				cur->next = new_expr_stmt (new_assign (new_var_node (var, t), rhs, t), t);
				cur = cur->next;
			}
			continue;
		}
		if (tk->kind != TK_ID) {
			error_tok (tk, "expected variable name");
		}
		char *name = tk->str;
		Token *nt = tk;
		tk = tk->next;
		while (eat ("[")) {
			Node *len = comma_expr ();
			expect ("]");
			ty = array_of (ty, (int)eval_const (len));
		}
		Obj *var = new_global (name, ty);
		var->is_extern = is_extern;
		var->is_public = is_public;
		if (is_extern && nt->file && !strcmp (nt->file, "<prelude>")) {
			var->from_prelude = true;
		}
		if (eat ("=")) {
			if (is_punct ("{")) {
				if (ty->kind != TY_ARRAY) {
					error_tok (tk, "brace initializer needs an array");
				}
				tk = tk->next;
				int idx = 0;
				while (!is_punct ("}")) {
					if (idx) {
						expect (",");
					}
					if (is_punct ("}")) {
						break;
					}
					Node *v = expr ();
					Node *dst = new_node (ND_DEREF, nt);
					dst->lhs = new_binary (ND_ADD, new_var_node (var, nt), new_num (idx, nt), nt);
					dst->ty = ty->base;
					cur->next = new_expr_stmt (new_assign (dst, v, nt), nt);
					cur = cur->next;
					idx++;
				}
				expect ("}");
			} else {
				Node *rhs = expr ();
				if (ty->kind == TY_ARRAY && rhs->kind == ND_STR) {
					Node *args = rvalize (new_var_node (var, nt));
					args->next = rhs;
					rhs->next = new_num (rhs->str_len + 1, nt);
					cur->next = new_expr_stmt (call_named ("MemCpy", args, 3, nt), nt);
					cur = cur->next;
				} else {
					cur->next = new_expr_stmt (new_assign (new_var_node (var, nt), rhs, nt), nt);
					cur = cur->next;
				}
			}
		}
	}
	expect (";");
	return head.next;
}

/* ------------------------------------------------------------- top level */

Program *parse(Token *tok) {
	/* reset state: #exe blocks compile a nested program before the
	 * outer parse runs, so parse() must be re-entrant */
	prog = xcalloc (1, sizeof(Program));
	tk = tok;
	scope = NULL;
	classes = NULL;
	funcs_tail = globals_tail = NULL;
	cur_fn = NULL;
	fn_locals = NULL;
	fn_labels = NULL;
	break_label = NULL;
	enter_scope (); /* global scope */

	Obj *startup = new_obj (xstrdup ("__hc_start"), NULL);
	startup->is_func = true;
	Type *fnty = new_type (TY_FUNC, 8, 8);
	fnty->base = ty_u0;
	startup->ty = fnty;
	startup->defaults = xmalloc (sizeof(Node *));
	prog->startup = startup;

	Node top_head = {0};
	Node *top_cur = &top_head;

	while (tk->kind != TK_EOF) {
		/* function attribute keywords; 'public' exports the symbol */
		bool is_public = false;
		while (is_kw ("public") || is_kw ("interrupt") || is_kw ("haserrcode") ||
		       is_kw ("argpop") || is_kw ("noargpop")) {
			if (is_kw ("public")) {
				is_public = true;
			}
			tk = tk->next;
		}
		bool is_extern = false;
		if (is_kw ("extern") || is_kw ("import") || is_kw ("_extern") || is_kw ("_import")) {
			is_extern = true;
			tk = tk->next;
			/* _extern SYMBOL alias form: skip the symbol token */
			if (tk->kind == TK_ID && tk->next->kind == TK_ID &&
			    !builtin_type (tk->str) && !find_class (tk->str)) {
				tk = tk->next;
			}
		}
		if (is_kw ("class")) {
			parse_class (false);
			continue;
		}
		if (is_kw ("union")) {
			parse_class (true);
			continue;
		}
		if (is_type_start (tk)) {
			/* type [stars] ident '(' => function; else global var(s) */
			Token *save = tk;
			Type *base = builtin_type (tk->str);
			if (!base) {
				base = find_class (tk->str);
			}
			tk = tk->next;
			Type *ret = base;
			while (eat ("*")) {
				ret = ptr_to (ret);
			}
			if (tk->kind == TK_ID && tk->next && tk->next->kind == TK_PUNCT &&
			    !strcmp (tk->next->str, "(")) {
				char *name = tk->str;
				tk = tk->next;
				parse_func (ret, name, is_extern, is_public);
				continue;
			}
			/* global variable(s): rewind to after base name, stars are
			 * per-declarator in global_decl */
			tk = save->next;
			Obj *save_fn = cur_fn;
			Obj *save_locals = fn_locals;
			cur_fn = startup;
			fn_locals = startup->locals;
			Node *init = global_decl (base, is_extern, is_public);
			startup->locals = fn_locals;
			fn_locals = save_locals;
			cur_fn = save_fn;
			if (init) {
				top_cur->next = init;
				while (top_cur->next) {
					top_cur = top_cur->next;
				}
			}
			continue;
		}
		if (is_extern) {
			error_tok (tk, "expected declaration after extern");
		}
		/* top-level statement -> startup code */
		Obj *save_fn = cur_fn;
		Obj *save_locals = fn_locals;
		cur_fn = startup;
		fn_locals = startup->locals;
		Node *s = stmt ();
		startup->locals = fn_locals;
		fn_locals = save_locals;
		cur_fn = save_fn;
		top_cur->next = s;
		while (top_cur->next) {
			top_cur = top_cur->next;
		}
	}
	check_labels (); /* top-level gotos */

	Node *body = new_node (ND_BLOCK, tok);
	body->body = top_head.next;
	startup->body = body;
	return prog;
}
