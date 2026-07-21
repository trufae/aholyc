/* aholyc LLVM-IR backend: emits textual .ll and builds a native executable
 * with the external LLVM toolchain (clang, or llc + system cc). aholyc never
 * links against LLVM libraries — it only writes IR files.
 *
 * Model: every local is an alloca (LLVM's mem2reg cleans that up), every
 * scalar value is i64 or double, addresses are i64 (inttoptr at use).
 */
#include "aholyc.h"
#include <unistd.h>

typedef struct {
	bool dynamic;
	char *label;
} LlHandler;

typedef struct {
	Aholyc *cc;
	Program *prog;
	StrBuf *out;
	int ntmp, nlab, try_depth, nhandlers;
	LlHandler handlers[256];
	bool block_open, ret_f, ret_void, ctor_mode;
} LlGen;

static char *tmp_(LlGen *lg) {
	return xasprintf (lg->cc, "%%t%d", ++lg->ntmp);
}

static char *newlab(LlGen *lg, const char *hint) {
	return xasprintf (lg->cc, "B%s%d", hint, ++lg->nlab);
}

static void ensure_block(LlGen *lg) {
	if (!lg->block_open) {
		sb_printf (lg->out, "dead%d:\n", ++lg->nlab);
		lg->block_open = true;
	}
}

static void br_to(LlGen *lg, const char *lab) {
	ensure_block (lg);
	sb_printf (lg->out, "  br label %%%s\n", lab);
	lg->block_open = false;
}

static void place_label(LlGen *lg, const char *lab) {
	if (lg->block_open) {
		sb_printf (lg->out, "  br label %%%s\n", lab);
	}
	sb_printf (lg->out, "%s:\n", lab);
	lg->block_open = true;
}

static char *labname(LlGen *lg, const char *l) {
	char *s = xasprintf (lg->cc, "L%s", l);
	for (char *p = s; *p; p++) {
		if (*p == '.') {
			*p = '_';
		}
	}
	return s;
}

static bool is_agg(Type *ty) {
	return ty && (ty->kind == TY_CLASS || ty->kind == TY_ARRAY);
}

static bool is_fs_obj(Obj *v) {
	return v->is_extern && v->from_prelude && !strcmp (v->name, "Fs");
}

static bool value_unsig(Type *ty) {
	return ty->kind == TY_INT && ty->is_unsigned;
}

static bool is_f(Node *n) {
	return n->ty && n->ty->kind == TY_F64;
}

static char *objref(LlGen *lg, Obj *v) {
	if (v->is_extern || v->is_public) {
		return xasprintf (lg->cc, "@%s", v->name);
	}
	if (v->is_func) {
		if (lg->prog && v == lg->prog->startup) {
			return xstrdup (lg->cc, lg->ctor_mode? "@__hc_ctor_body": "@__hc_start");
		}
		return xasprintf (lg->cc, "@hc_%s", v->name);
	}
	if (v->is_global) {
		return xasprintf (lg->cc, "@g%d_%s", v->uid, v->name);
	}
	return xasprintf (lg->cc, "%%l%d_%s", v->uid, v->name);
}

/* storage width of a variable slot: params are full 64-bit */
static int store_size(Obj *v) {
	if (v->is_param) {
		return 8;
	}
	return v->ty->size? v->ty->size: 8;
}

static const char *ityp(int size) {
	switch (size) {
	case 1: return "i8";
	case 2: return "i16";
	case 4: return "i32";
	}
	return "i64";
}

/* Keep ordinary storage/ABI width, but expose the requested range at value
 * boundaries for LLVM optimizations.  Signedness comes from the HolyC type. */
static char *apply_bits_hint(LlGen *lg, char *val, Type *ty) {
	int bits = ty->bits;
	if (!bits || bits == 64) {
		return val;
	}
	ensure_block (lg);
	char *n = tmp_ (lg);
	sb_printf (lg->out, "  %s = trunc i64 %s to i%d\n", n, val, bits);
	char *w = tmp_ (lg);
	sb_printf (lg->out, "  %s = %s i%d %s to i64\n", w,
		ty->is_unsigned? "zext": "sext", bits, n);
	return w;
}

static int elem_size(Type *ptrty) {
	int s = ptrty->base? ptrty->base->size: 1;
	return s? s: 1;
}

static char *emit_val(LlGen *lg, Node *n);
static char *emit_addr(LlGen *lg, Node *n);
static void emit_stmt(LlGen *lg, Node *n);

static char *load_from(LlGen *lg, char *addr_i64, Type *ty, bool full_width) {
	ensure_block (lg);
	char *p = tmp_ (lg);
	sb_printf (lg->out, "  %s = inttoptr i64 %s to ptr\n", p, addr_i64);
	char *t = tmp_ (lg);
	if (ty->kind == TY_F64) {
		sb_printf (lg->out, "  %s = load double, ptr %s\n", t, p);
		return t;
	}
	int sz = full_width? 8: (ty->size? ty->size: 8);
	sb_printf (lg->out, "  %s = load %s, ptr %s\n", t, ityp (sz), p);
	if (sz == 8) {
		return t;
	}
	char *w = tmp_ (lg);
	sb_printf (lg->out, "  %s = %s %s %s to i64\n", w,
		ty->is_unsigned? "zext": "sext", ityp (sz), t);
	return w;
}

static void store_to(LlGen *lg, char *addr_i64, char *val, Type *ty, bool full_width) {
	ensure_block (lg);
	char *p = tmp_ (lg);
	sb_printf (lg->out, "  %s = inttoptr i64 %s to ptr\n", p, addr_i64);
	if (ty->kind == TY_F64) {
		sb_printf (lg->out, "  store double %s, ptr %s\n", val, p);
		return;
	}
	int sz = full_width? 8: (ty->size? ty->size: 8);
	if (sz == 8) {
		sb_printf (lg->out, "  store i64 %s, ptr %s\n", val, p);
		return;
	}
	char *t = tmp_ (lg);
	sb_printf (lg->out, "  %s = trunc i64 %s to %s\n", t, val, ityp (sz));
	sb_printf (lg->out, "  store %s %s, ptr %s\n", ityp (sz), t, p);
}

static char *fnum_lit(LlGen *lg, double d) {
	union { double d; uint64_t u; } u;
	u.d = d;
	return xasprintf (lg->cc, "0x%016llX", (unsigned long long)u.u);
}

static char *bool_of(LlGen *lg, char *v, bool isf) {
	ensure_block (lg);
	char *c = tmp_ (lg);
	if (isf) {
		sb_printf (lg->out, "  %s = fcmp one double %s, 0.0\n", c, v);
	} else {
		sb_printf (lg->out, "  %s = icmp ne i64 %s, 0\n", c, v);
	}
	return c;
}

static char *zext_i64(LlGen *lg, char *i1) {
	char *t = tmp_ (lg);
	sb_printf (lg->out, "  %s = zext i1 %s to i64\n", t, i1);
	return t;
}

/* address of a variable as i64 operand */
static char *var_addr(LlGen *lg, Obj *v) {
	if (v->is_global || v->is_extern) {
		return xasprintf (lg->cc, "ptrtoint (ptr %s to i64)", objref (lg, v));
	}
	ensure_block (lg);
	char *t = tmp_ (lg);
	sb_printf (lg->out, "  %s = ptrtoint ptr %s to i64\n", t, objref (lg, v));
	return t;
}

static char *emit_addr(LlGen *lg, Node *n) {
	switch (n->kind) {
	case ND_VAR:
		return var_addr (lg, n->var);
	case ND_DEREF:
		return emit_val (lg, n->lhs);
	case ND_MEMBER: {
		char *b = emit_addr (lg, n->lhs);
		if (n->member_ref->offset == 0) {
			return b;
		}
		ensure_block (lg);
		char *t = tmp_ (lg);
		sb_printf (lg->out, "  %s = add i64 %s, %d\n", t, b, n->member_ref->offset);
		return t;
	}
	default:
		error (lg->cc, "LLVM backend: not an lvalue (node kind %d)", n->kind);
		return NULL;
	}
}

/* runtime bit API emitted as LLVM intrinsics / inline IR so it compiles
 * to single instructions (popcnt, tzcnt, bts, lock bts, ...). The rmw op
 * for the mutating forms; NULL means plain Bt (load only). */
static const char *bit_rmw_op(const char *nm) {
	nm += nm[0] == 'L';
	if (!strcmp (nm, "Bts")) {
		return "or";
	}
	if (!strcmp (nm, "Btr")) {
		return "and";
	}
	if (!strcmp (nm, "Btc")) {
		return "xor";
	}
	return NULL;
}

static char *emit_bit_intrin(LlGen *lg, Node *n) {
	const char *nm = n->func->name;
	Node *a = n->args;
	if (!strcmp (nm, "BCnt") || !strcmp (nm, "Bsf") || !strcmp (nm, "Bsr")) {
		char *v = emit_val (lg, a);
		ensure_block (lg);
		char *t = tmp_ (lg);
		if (!strcmp (nm, "BCnt")) {
			sb_printf (lg->out, "  %s = call i64 @llvm.ctpop.i64(i64 %s)\n", t, v);
			return t;
		}
		bool fwd = !strcmp (nm, "Bsf");
		sb_printf (lg->out, "  %s = call i64 @llvm.%s.i64(i64 %s, i1 false)\n", t,
			fwd? "cttz": "ctlz", v);
		char *pos = t;
		if (!fwd) {
			pos = tmp_ (lg);
			sb_printf (lg->out, "  %s = sub i64 63, %s\n", pos, t);
		}
		char *c = tmp_ (lg);
		sb_printf (lg->out, "  %s = icmp eq i64 %s, 0\n", c, v);
		char *r = tmp_ (lg);
		sb_printf (lg->out, "  %s = select i1 %s, i64 -1, i64 %s\n", r, c, pos);
		return r;
	}
	/* Bt/Btc/Btr/Bts/LBtc/LBtr/LBts(bit_field, bit): x86 BT addressing,
	 * byte p[bit>>3] bit (bit&7), signed so negative offsets work */
	char *p = emit_val (lg, a);
	char *bit = emit_val (lg, a->next);
	ensure_block (lg);
	char *off = tmp_ (lg);
	sb_printf (lg->out, "  %s = ashr i64 %s, 3\n", off, bit);
	char *ba = tmp_ (lg);
	sb_printf (lg->out, "  %s = add i64 %s, %s\n", ba, p, off);
	char *ptr = tmp_ (lg);
	sb_printf (lg->out, "  %s = inttoptr i64 %s to ptr\n", ptr, ba);
	char *sh = tmp_ (lg);
	sb_printf (lg->out, "  %s = and i64 %s, 7\n", sh, bit);
	const char *op = bit_rmw_op (nm);
	char *old = tmp_ (lg);
	if (!op) {
		sb_printf (lg->out, "  %s = load i8, ptr %s\n", old, ptr);
	} else {
		char *m = tmp_ (lg);
		sb_printf (lg->out, "  %s = shl i64 1, %s\n", m, sh);
		if (!strcmp (op, "and")) {
			char *inv = tmp_ (lg);
			sb_printf (lg->out, "  %s = xor i64 %s, -1\n", inv, m);
			m = inv;
		}
		char *m8 = tmp_ (lg);
		sb_printf (lg->out, "  %s = trunc i64 %s to i8\n", m8, m);
		if (nm[0] == 'L') {
			sb_printf (lg->out, "  %s = atomicrmw %s ptr %s, i8 %s seq_cst\n",
				old, op, ptr, m8);
		} else {
			sb_printf (lg->out, "  %s = load i8, ptr %s\n", old, ptr);
			char *nw = tmp_ (lg);
			sb_printf (lg->out, "  %s = %s i8 %s, %s\n", nw, op, old, m8);
			sb_printf (lg->out, "  store i8 %s, ptr %s\n", nw, ptr);
		}
	}
	char *w = tmp_ (lg);
	sb_printf (lg->out, "  %s = zext i8 %s to i64\n", w, old);
	char *sv = tmp_ (lg);
	sb_printf (lg->out, "  %s = lshr i64 %s, %s\n", sv, w, sh);
	char *r = tmp_ (lg);
	sb_printf (lg->out, "  %s = and i64 %s, 1\n", r, sv);
	return r;
}

static bool is_bit_intrin(Obj *fn) {
	static const char *const names[] = {
		"Bsf", "Bsr", "BCnt", "Bt", "Btc", "Btr", "Bts",
		"LBtc", "LBtr", "LBts", NULL
	};
	if (!fn || !fn->is_extern || !fn->from_prelude) {
		return false;
	}
	for (int i = 0; names[i]; i++) {
		if (!strcmp (fn->name, names[i])) {
			return true;
		}
	}
	return false;
}

static char *emit_call(LlGen *lg, Node *n) {
	Obj *fn = n->func;
	if (is_bit_intrin (fn)) {
		return emit_bit_intrin (lg, n);
	}
	char *args[300];
	bool argf[300];
	int nargs = 0;
	Node *a = n->args;
	int i = 0;
	/* fixed args */
	for (; a && (fn? i < n->nfixed: true); a = a->next, i++) {
		args[nargs] = emit_val (lg, a);
		argf[nargs] = is_f (a);
		nargs++;
	}
	/* variadic extras -> [k x i64] alloca */
	char *extras_ptr = NULL;
	int nextras = 0;
	if (fn && fn->is_variadic) {
		Node *e = a;
		char *slots[256];
		for (; e; e = e->next) {
			char *v = emit_val (lg, e);
			if (is_f (e)) {
				ensure_block (lg);
				char *b = tmp_ (lg);
				sb_printf (lg->out, "  %s = bitcast double %s to i64\n", b, v);
				v = b;
			}
			slots[nextras++] = v;
		}
		ensure_block (lg);
		char *arr = tmp_ (lg);
		sb_printf (lg->out, "  %s = alloca [%d x i64], align 8\n", arr,
			nextras? nextras: 1);
		for (int k = 0; k < nextras; k++) {
			char *gep = tmp_ (lg);
			sb_printf (lg->out, "  %s = getelementptr [%d x i64], ptr %s, i64 0, i64 %d\n",
				gep, nextras? nextras: 1, arr, k);
			sb_printf (lg->out, "  store i64 %s, ptr %s\n", slots[k], gep);
		}
		extras_ptr = tmp_ (lg);
		sb_printf (lg->out, "  %s = ptrtoint ptr %s to i64\n", extras_ptr, arr);
	}
	ensure_block (lg);
	/* return kind */
	bool retf = n->ty && n->ty->kind == TY_F64;
	bool retv = n->ty && n->ty->kind == TY_VOID;
	char *res = retv? NULL: tmp_ (lg);
	if (res) {
		sb_printf (lg->out, "  %s = ", res);
	} else {
		sb_printf (lg->out, "  ");
	}
	const char *rty = retf? "double": retv? "void": "i64";
	sb_printf (lg->out, "call %s %s(", rty, objref (lg, fn));
	for (int k = 0; k < nargs; k++) {
		sb_printf (lg->out, "%s%s %s", k? ", ": "", argf[k]? "double": "i64", args[k]);
	}
	if (fn && fn->is_variadic) {
		sb_printf (lg->out, "%si64 %d, i64 %s", nargs? ", ": "", nextras,
			extras_ptr? extras_ptr: "0");
	}
	sb_printf (lg->out, ")\n");
	if (retv) {
		return xstrdup (lg->cc, "0");
	}
	return res;
}

/* indirect calls need the callee converted before the call instruction,
 * so they get their own routine */
static char *emit_indirect_call(LlGen *lg, Node *n) {
	char *callee = emit_val (lg, n->lhs);
	char *args[300];
	bool argf[300];
	int nargs = 0;
	for (Node *a = n->args; a; a = a->next) {
		args[nargs] = emit_val (lg, a);
		argf[nargs] = is_f (a);
		nargs++;
	}
	ensure_block (lg);
	char *fp = tmp_ (lg);
	sb_printf (lg->out, "  %s = inttoptr i64 %s to ptr\n", fp, callee);
	bool retf = n->ty && n->ty->kind == TY_F64;
	bool retv = n->ty && n->ty->kind == TY_VOID;
	char *res = retv? NULL: tmp_ (lg);
	if (res) {
		sb_printf (lg->out, "  %s = ", res);
	} else {
		sb_printf (lg->out, "  ");
	}
	sb_printf (lg->out, "call %s %s(", retf? "double": retv? "void": "i64", fp);
	for (int k = 0; k < nargs; k++) {
		sb_printf (lg->out, "%s%s %s", k? ", ": "", argf[k]? "double": "i64", args[k]);
	}
	sb_printf (lg->out, ")\n");
	return res? res: xstrdup (lg->cc, "0");
}

static char *emit_binop(LlGen *lg, Node *n) {
	bool ff = n->ty->kind == TY_F64;
	bool unsig = n->ty->kind == TY_INT && n->ty->is_unsigned;
	/* pointer arithmetic scaling */
	if (n->kind == ND_ADD || n->kind == ND_SUB) {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = lt && (lt->kind == TY_PTR || lt->kind == TY_ARRAY);
		bool rp = rt && (rt->kind == TY_PTR || rt->kind == TY_ARRAY);
		if (lp && rp && n->kind == ND_SUB) {
			char *a = emit_val (lg, n->lhs);
			char *b = emit_val (lg, n->rhs);
			ensure_block (lg);
			char *d = tmp_ (lg);
			sb_printf (lg->out, "  %s = sub i64 %s, %s\n", d, a, b);
			char *q = tmp_ (lg);
			sb_printf (lg->out, "  %s = sdiv i64 %s, %d\n", q, d, elem_size (lt));
			return q;
		}
		if (lp) {
			char *a = emit_val (lg, n->lhs);
			char *b = emit_val (lg, n->rhs);
			ensure_block (lg);
			char *s = tmp_ (lg);
			sb_printf (lg->out, "  %s = mul i64 %s, %d\n", s, b, elem_size (lt));
			char *r = tmp_ (lg);
			sb_printf (lg->out, "  %s = %s i64 %s, %s\n", r,
				n->kind == ND_ADD? "add": "sub", a, s);
			return r;
		}
	}
	char *a = emit_val (lg, n->lhs);
	char *b = emit_val (lg, n->rhs);
	ensure_block (lg);
	const char *op = NULL;
	switch (n->kind) {
	case ND_ADD: op = ff? "fadd": "add"; break;
	case ND_SUB: op = ff? "fsub": "sub"; break;
	case ND_MUL: op = ff? "fmul": "mul"; break;
	case ND_DIV: op = ff? "fdiv": unsig? "udiv": "sdiv"; break;
	case ND_MOD: op = unsig? "urem": "srem"; break;
	case ND_AND: op = "and"; break;
	case ND_OR: op = "or"; break;
	case ND_XOR: op = "xor"; break;
	case ND_SHL: op = "shl"; break;
	case ND_SHR: op = unsig? "lshr": "ashr"; break;
	default: error (lg->cc, "llvm: bad binop"); break;
	}
	char *t = tmp_ (lg);
	sb_printf (lg->out, "  %s = %s %s %s, %s\n", t, op, ff? "double": "i64", a, b);
	return t;
}

static char *emit_cmp(LlGen *lg, Node *n) {
	bool ff = n->lhs->ty->kind == TY_F64;
	bool unsig = !ff && (value_unsig (n->lhs->ty) || value_unsig (n->rhs->ty));
	char *a = emit_val (lg, n->lhs);
	char *b = emit_val (lg, n->rhs);
	ensure_block (lg);
	const char *cc;
	switch (n->kind) {
	case ND_EQ: cc = ff? "oeq": "eq"; break;
	case ND_NE: cc = ff? "une": "ne"; break;
	case ND_LT: cc = ff? "olt": unsig? "ult": "slt"; break;
	default: cc = ff? "ole": unsig? "ule": "sle"; break;
	}
	char *c = tmp_ (lg);
	sb_printf (lg->out, "  %s = %s %s %s %s, %s\n", c, ff? "fcmp": "icmp", cc,
		ff? "double": "i64", a, b);
	return zext_i64 (lg, c);
}

/* short-circuit && / || via a result slot */
static char *emit_shortcircuit(LlGen *lg, Node *n) {
	ensure_block (lg);
	char *slot = tmp_ (lg);
	sb_printf (lg->out, "  %s = alloca i64, align 8\n", slot);
	char *rhsl = newlab (lg, "sc_rhs");
	char *skipl = newlab (lg, "sc_skip");
	char *endl = newlab (lg, "sc_end");
	char *a = emit_val (lg, n->lhs);
	char *ca = bool_of (lg, a, false); /* operands already i64 (to_bool'ed) */
	if (n->kind == ND_LOGAND) {
		sb_printf (lg->out, "  br i1 %s, label %%%s, label %%%s\n", ca, rhsl, skipl);
	} else {
		sb_printf (lg->out, "  br i1 %s, label %%%s, label %%%s\n", ca, skipl, rhsl);
	}
	lg->block_open = false;
	place_label (lg, rhsl);
	char *b = emit_val (lg, n->rhs);
	char *cb = bool_of (lg, b, false);
	char *zb = zext_i64 (lg, cb);
	sb_printf (lg->out, "  store i64 %s, ptr %s\n", zb, slot);
	br_to (lg, endl);
	place_label (lg, skipl);
	sb_printf (lg->out, "  store i64 %d, ptr %s\n", n->kind == ND_LOGAND? 0: 1, slot);
	br_to (lg, endl);
	place_label (lg, endl);
	char *r = tmp_ (lg);
	sb_printf (lg->out, "  %s = load i64, ptr %s\n", r, slot);
	return r;
}

static char *emit_val(LlGen *lg, Node *n) {
	switch (n->kind) {
	case ND_NUM:
		return xasprintf (lg->cc, "%lld", (long long)n->ival);
	case ND_FNUM:
		return fnum_lit (lg, n->fval);
	case ND_STR:
		return xasprintf (lg->cc, "ptrtoint (ptr @hcs%d to i64)", n->str_id);
	case ND_VAR: {
		Obj *v = n->var;
		if (is_fs_obj (v)) {
			ensure_block (lg);
			char *p = tmp_ (lg);
			sb_printf (lg->out, "  %s = call ptr @__hc_fs()\n", p);
			char *t = tmp_ (lg);
			sb_printf (lg->out, "  %s = ptrtoint ptr %s to i64\n", t, p);
			return t;
		}
		if (is_agg (v->ty)) {
			return var_addr (lg, v);
		}
		ensure_block (lg);
		if (v->is_global || v->is_extern) {
			char *addr = var_addr (lg, v);
			char *val = load_from (lg, addr, v->ty, v->is_param);
			return apply_bits_hint (lg, val, v->ty);
		}
		char *t = tmp_ (lg);
		if (v->ty->kind == TY_F64) {
			sb_printf (lg->out, "  %s = load double, ptr %s\n", t, objref (lg, v));
			return t;
		}
		int sz = store_size (v);
		sb_printf (lg->out, "  %s = load %s, ptr %s\n", t, ityp (sz), objref (lg, v));
		if (sz == 8) {
			return apply_bits_hint (lg, t, v->ty);
		}
		char *w = tmp_ (lg);
		sb_printf (lg->out, "  %s = %s %s %s to i64\n", w,
			v->ty->is_unsigned? "zext": "sext", ityp (sz), t);
		return apply_bits_hint (lg, w, v->ty);
	}
	case ND_FUNCNAME:
		return xasprintf (lg->cc, "ptrtoint (ptr %s to i64)", objref (lg, n->func));
	case ND_DEREF:
		if (is_agg (n->ty)) {
			return emit_val (lg, n->lhs);
		}
		return apply_bits_hint (lg, load_from (lg, emit_val (lg, n->lhs), n->ty, false), n->ty);
	case ND_MEMBER:
		if (is_agg (n->ty)) {
			return emit_addr (lg, n);
		}
		return apply_bits_hint (lg, load_from (lg, emit_addr (lg, n), n->ty, false), n->ty);
	case ND_ADDR:
		return emit_addr (lg, n->lhs);
	case ND_ASSIGN: {
		Node *l = n->lhs;
		char *rv = emit_val (lg, n->rhs);
		if (l->ty && l->ty->kind == TY_CLASS) {
			char *la = emit_addr (lg, l);
			ensure_block (lg);
			char *lp = tmp_ (lg), *rp = tmp_ (lg);
			sb_printf (lg->out, "  %s = inttoptr i64 %s to ptr\n", lp, la);
			sb_printf (lg->out, "  %s = inttoptr i64 %s to ptr\n", rp, rv);
			sb_printf (lg->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %d, i1 false)\n",
				lp, rp, l->ty->size);
			return la;
		}
		rv = apply_bits_hint (lg, rv, l->ty);
		if (l->kind == ND_VAR && !l->var->is_global && !l->var->is_extern) {
			Obj *v = l->var;
			ensure_block (lg);
			if (v->ty->kind == TY_F64) {
				sb_printf (lg->out, "  store double %s, ptr %s\n", rv, objref (lg, v));
				return rv;
			}
			int sz = store_size (v);
			if (sz == 8 && v->is_param && v->ty->size && v->ty->size < 8) {
				/* param slot is 64-bit but declared narrower: truncate */
				char *t = tmp_ (lg);
				sb_printf (lg->out, "  %s = trunc i64 %s to %s\n", t, rv, ityp (v->ty->size));
				char *w = tmp_ (lg);
				sb_printf (lg->out, "  %s = %s %s %s to i64\n", w,
					v->ty->is_unsigned? "zext": "sext", ityp (v->ty->size), t);
				sb_printf (lg->out, "  store i64 %s, ptr %s\n", w, objref (lg, v));
				return rv;
			}
			if (sz == 8) {
				sb_printf (lg->out, "  store i64 %s, ptr %s\n", rv, objref (lg, v));
				return rv;
			}
			char *t = tmp_ (lg);
			sb_printf (lg->out, "  %s = trunc i64 %s to %s\n", t, rv, ityp (sz));
			sb_printf (lg->out, "  store %s %s, ptr %s\n", ityp (sz), t, objref (lg, v));
			return rv;
		}
		store_to (lg, emit_addr (lg, l), rv, l->ty, l->kind == ND_VAR && l->var->is_param);
		return rv;
	}
	case ND_CAST: {
		Type *to = n->ty, *from = n->lhs->ty;
		char *v = emit_val (lg, n->lhs);
		if (to->kind == TY_F64 && from->kind != TY_F64) {
			ensure_block (lg);
			char *t = tmp_ (lg);
			sb_printf (lg->out, "  %s = %s i64 %s to double\n", t,
				value_unsig (from)? "uitofp": "sitofp", v);
			return t;
		}
		if (to->kind != TY_F64 && from->kind == TY_F64) {
			ensure_block (lg);
			char *t = tmp_ (lg);
			sb_printf (lg->out, "  %s = fptosi double %s to i64\n", t, v);
			v = t;
		}
		if (to->kind == TY_INT && to->size < 8) {
			ensure_block (lg);
			char *t = tmp_ (lg);
			sb_printf (lg->out, "  %s = trunc i64 %s to %s\n", t, v, ityp (to->size));
			char *w = tmp_ (lg);
			sb_printf (lg->out, "  %s = %s %s %s to i64\n", w,
				to->is_unsigned? "zext": "sext", ityp (to->size), t);
			return w;
		}
		return v;
	}
	case ND_ADD: case ND_SUB: case ND_MUL: case ND_DIV: case ND_MOD:
	case ND_AND: case ND_OR: case ND_XOR: case ND_SHL: case ND_SHR:
		return emit_binop (lg, n);
	case ND_POW: {
		char *a = emit_val (lg, n->lhs);
		char *b = emit_val (lg, n->rhs);
		ensure_block (lg);
		char *t = tmp_ (lg);
		sb_printf (lg->out, "  %s = call double @__hc_pow(double %s, double %s)\n", t, a, b);
		return t;
	}
	case ND_EQ: case ND_NE: case ND_LT: case ND_LE:
		return emit_cmp (lg, n);
	case ND_LOGAND:
	case ND_LOGOR:
		return emit_shortcircuit (lg, n);
	case ND_LOGXOR: {
		char *a = emit_val (lg, n->lhs);
		char *b = emit_val (lg, n->rhs);
		char *ca = bool_of (lg, a, false);
		char *cb = bool_of (lg, b, false);
		ensure_block (lg);
		char *x = tmp_ (lg);
		sb_printf (lg->out, "  %s = xor i1 %s, %s\n", x, ca, cb);
		return zext_i64 (lg, x);
	}
	case ND_NOT: {
		char *v = emit_val (lg, n->lhs);
		ensure_block (lg);
		char *c = tmp_ (lg);
		sb_printf (lg->out, "  %s = icmp eq i64 %s, 0\n", c, v);
		return zext_i64 (lg, c);
	}
	case ND_BITNOT: {
		char *v = emit_val (lg, n->lhs);
		ensure_block (lg);
		char *t = tmp_ (lg);
		sb_printf (lg->out, "  %s = xor i64 %s, -1\n", t, v);
		return t;
	}
	case ND_NEG: {
		char *v = emit_val (lg, n->lhs);
		ensure_block (lg);
		char *t = tmp_ (lg);
		if (is_f (n)) {
			sb_printf (lg->out, "  %s = fneg double %s\n", t, v);
		} else {
			sb_printf (lg->out, "  %s = sub i64 0, %s\n", t, v);
		}
		return t;
	}
	case ND_COMMA:
		emit_val (lg, n->lhs);
		return emit_val (lg, n->rhs);
	case ND_CALL:
		if (n->func) {
			return emit_call (lg, n);
		}
		return emit_indirect_call (lg, n);
	case ND_NOP:
		return xstrdup (lg->cc, "0");
	default:
		error (lg->cc, "LLVM backend: unexpected node kind %d in expression", n->kind);
		return NULL;
	}
}

static void emit_cond_br(LlGen *lg, Node *cond, const char *tl, const char *fl) {
	char *v = emit_val (lg, cond);
	char *c = bool_of (lg, v, is_f (cond));
	sb_printf (lg->out, "  br i1 %s, label %%%s, label %%%s\n", c, tl, fl);
	lg->block_open = false;
}

static LlHandler *current_handler(LlGen *lg) {
	return lg->nhandlers? &lg->handlers[lg->nhandlers - 1]: NULL;
}

static void push_handler(LlGen *lg, bool dynamic, char *label) {
	if (lg->nhandlers >= (int)(sizeof(lg->handlers) / sizeof(lg->handlers[0]))) {
		error (lg->cc, "LLVM backend: try nesting too deep");
	}
	lg->handlers[lg->nhandlers++] = (LlHandler){ .dynamic = dynamic, .label = label };
}

static bool emit_local_throw(LlGen *lg, Node *call) {
	LlHandler *h = current_handler (lg);
	if (!h || h->dynamic) {
		return false;
	}
	char *v = call->args? emit_val (lg, call->args): xstrdup (lg->cc, "0");
	ensure_block (lg);
	char *fs = tmp_ (lg);
	sb_printf (lg->out, "  %s = call ptr @__hc_fs()\n", fs);
	sb_printf (lg->out, "  store i64 %s, ptr %s\n", v, fs);
	char *cep = tmp_ (lg);
	sb_printf (lg->out, "  %s = getelementptr i64, ptr %s, i64 1\n", cep, fs);
	sb_printf (lg->out, "  store i64 0, ptr %s\n", cep);
	br_to (lg, h->label);
	return true;
}

/* Finish a catch by either branching to an outer lexical handler or using
 * the runtime throw when the nearest outer handler crosses a call frame. */
static void emit_catch_end(LlGen *lg, const char *end) {
	ensure_block (lg);
	char *fs = tmp_ (lg);
	sb_printf (lg->out, "  %s = call ptr @__hc_fs()\n", fs);
	char *cep = tmp_ (lg);
	sb_printf (lg->out, "  %s = getelementptr i64, ptr %s, i64 1\n", cep, fs);
	char *ce = tmp_ (lg);
	sb_printf (lg->out, "  %s = load i64, ptr %s\n", ce, cep);
	char *uncaught = tmp_ (lg);
	sb_printf (lg->out, "  %s = icmp eq i64 %s, 0\n", uncaught, ce);
	LlHandler *outer = current_handler (lg);
	if (outer && !outer->dynamic) {
		sb_printf (lg->out, "  br i1 %s, label %%%s, label %%%s\n",
			uncaught, outer->label, end);
		lg->block_open = false;
		place_label (lg, end);
		return;
	}
	char *rethrow = newlab (lg, "rethrow");
	sb_printf (lg->out, "  br i1 %s, label %%%s, label %%%s\n", uncaught, rethrow, end);
	lg->block_open = false;
	place_label (lg, rethrow);
	char *ev = tmp_ (lg);
	sb_printf (lg->out, "  %s = load i64, ptr %s\n", ev, fs);
	sb_printf (lg->out, "  call void @throw(i64 %s)\n", ev);
	br_to (lg, end);
	place_label (lg, end);
}

static void emit_stmt(LlGen *lg, Node *n) {
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT:
		if (is_throw_call (n->lhs) && emit_local_throw (lg, n->lhs)) {
			break;
		}
		emit_val (lg, n->lhs);
		break;
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (lg, s);
		}
		break;
	case ND_IF: {
		char *tl = newlab (lg, "then"), *el = newlab (lg, "else"), *dl = newlab (lg, "endif");
		ensure_block (lg);
		emit_cond_br (lg, n->cond, tl, n->els? el: dl);
		place_label (lg, tl);
		emit_stmt (lg, n->then);
		br_to (lg, dl);
		if (n->els) {
			place_label (lg, el);
			emit_stmt (lg, n->els);
			br_to (lg, dl);
		}
		place_label (lg, dl);
		break;
	}
	case ND_WHILE: {
		char *hl = newlab (lg, "whead"), *bl = newlab (lg, "wbody"), *el = newlab (lg, "wend");
		br_to (lg, hl);
		place_label (lg, hl);
		emit_cond_br (lg, n->cond, bl, el);
		place_label (lg, bl);
		emit_stmt (lg, n->then);
		br_to (lg, hl);
		place_label (lg, el);
		break;
	}
	case ND_DOWHILE: {
		char *bl = newlab (lg, "dbody"), *hl = newlab (lg, "dcond"), *el = newlab (lg, "dend");
		br_to (lg, bl);
		place_label (lg, bl);
		emit_stmt (lg, n->then);
		br_to (lg, hl);
		place_label (lg, hl);
		emit_cond_br (lg, n->cond, bl, el);
		place_label (lg, el);
		break;
	}
	case ND_FOR: {
		char *hl = newlab (lg, "fhead"), *bl = newlab (lg, "fbody"), *el = newlab (lg, "fend");
		if (n->init) {
			emit_stmt (lg, n->init);
		}
		br_to (lg, hl);
		place_label (lg, hl);
		if (n->cond) {
			emit_cond_br (lg, n->cond, bl, el);
		} else {
			br_to (lg, bl);
		}
		place_label (lg, bl);
		emit_stmt (lg, n->then);
		if (n->inc) {
			emit_stmt (lg, n->inc);
		}
		br_to (lg, hl);
		place_label (lg, el);
		break;
	}
	case ND_RETURN: {
		ensure_block (lg);
		for (int i = 0; i < lg->try_depth; i++) {
			sb_printf (lg->out, "  call void @__hc_try_pop()\n");
		}
		if (lg->ret_void) {
			sb_printf (lg->out, "  ret void\n");
		} else if (n->lhs) {
			char *v = emit_val (lg, n->lhs);
			ensure_block (lg);
			sb_printf (lg->out, "  ret %s %s\n", lg->ret_f? "double": "i64", v);
		} else {
			sb_printf (lg->out, "  ret %s %s\n", lg->ret_f? "double": "i64",
				lg->ret_f? "0.0": "0");
		}
		lg->block_open = false;
		break;
	}
	case ND_GOTO: {
		char *l = labname (lg, n->label);
		br_to (lg, l);
		break;
	}
	case ND_LABEL: {
		char *l = labname (lg, n->label);
		place_label (lg, l);
		break;
	}
	case ND_TRY: {
		if (n->try_mode == TRY_NONE) {
			emit_stmt (lg, n->then);
			break;
		}
		if (n->try_mode == TRY_LOCAL) {
			char *cl = newlab (lg, "catch"), *el = newlab (lg, "tryend");
			push_handler (lg, false, cl);
			emit_stmt (lg, n->then);
			lg->nhandlers--;
			br_to (lg, el);
			place_label (lg, cl);
			emit_stmt (lg, n->els);
			emit_catch_end (lg, el);
			break;
		}
		ensure_block (lg);
		char *jb = tmp_ (lg);
		sb_printf (lg->out, "  %s = call ptr @__hc_try_push()\n", jb);
		char *r = tmp_ (lg);
		sb_printf (lg->out, "  %s = call i32 @_setjmp(ptr %s) returns_twice\n", r, jb);
		char *c = tmp_ (lg);
		sb_printf (lg->out, "  %s = icmp eq i32 %s, 0\n", c, r);
		char *tl = newlab (lg, "try"), *cl = newlab (lg, "catch"), *el = newlab (lg, "tryend");
		sb_printf (lg->out, "  br i1 %s, label %%%s, label %%%s\n", c, tl, cl);
		lg->block_open = false;
		place_label (lg, tl);
		lg->try_depth++;
		push_handler (lg, true, cl);
		emit_stmt (lg, n->then);
		lg->nhandlers--;
		lg->try_depth--;
		ensure_block (lg);
		sb_printf (lg->out, "  call void @__hc_try_pop()\n");
		br_to (lg, el);
		place_label (lg, cl);
		emit_stmt (lg, n->els);
		emit_catch_end (lg, el);
		break;
	}
	default:
		emit_val (lg, n);
		break;
	}
}

static void emit_str_escaped(LlGen *lg, StrLit *s) {
	sb_printf (lg->out, "@hcs%d = internal constant [%d x i8] c\"", s->id, s->len + 1);
	for (int i = 0; i < s->len; i++) {
		unsigned char c = (unsigned char)s->data[i];
		if (c >= 32 && c < 127 && c != '"' && c != '\\') {
			sb_putc (lg->out, c);
		} else {
			sb_printf (lg->out, "\\%02X", c);
		}
	}
	sb_printf (lg->out, "\\00\"\n");
}

static void emit_func(LlGen *lg, Obj *fn) {
	Type *ret = fn->ty->base;
	lg->ret_f = ret->kind == TY_F64;
	lg->ret_void = ret->kind == TY_VOID;
	lg->ntmp = 0;
	lg->nlab = 0;
	lg->try_depth = 0;
	lg->nhandlers = 0;
	bool is_start = fn == lg->prog->startup;
	bool exported = fn->is_public || (is_start && !lg->ctor_mode);
	sb_printf (lg->out, "define %s %s %s(", exported? "": "internal",
		lg->ret_f? "double": lg->ret_void? "void": "i64", objref (lg, fn));
	int np = 0;
	for (Obj *p = fn->params; p; p = p->next, np++) {
		sb_printf (lg->out, "%s%s %%a%d", np? ", ": "",
			p->ty->kind == TY_F64? "double": "i64", np);
	}
	sb_printf (lg->out, ")%s {\nentry:\n",
		fn->hints & HINT_INLINE? " alwaysinline":
		fn->hints & HINT_NOINLINE? " noinline": "");
	lg->block_open = true;
	/* param slots */
	np = 0;
	for (Obj *p = fn->params; p; p = p->next, np++) {
		if (p->ty->kind == TY_F64) {
			sb_printf (lg->out, "  %s = alloca double, align 8\n", objref (lg, p));
			sb_printf (lg->out, "  store double %%a%d, ptr %s\n", np, objref (lg, p));
		} else {
			sb_printf (lg->out, "  %s = alloca i64, align 8\n", objref (lg, p));
			sb_printf (lg->out, "  store i64 %%a%d, ptr %s\n", np, objref (lg, p));
		}
	}
	/* locals */
	for (Obj *v = fn->locals; v; v = v->next) {
		int al = v->align? v->align: 1;
		if (is_agg (v->ty)) {
			int sz = v->ty->size? v->ty->size: 8;
			sb_printf (lg->out, "  %s = alloca [%d x i8], align %d\n", objref (lg, v), sz, al);
			sb_printf (lg->out, "  call void @llvm.memset.p0.i64(ptr %s, i8 0, i64 %d, i1 false)\n",
				objref (lg, v), sz);
		} else if (v->ty->kind == TY_F64) {
			sb_printf (lg->out, "  %s = alloca double, align %d\n", objref (lg, v), al);
			sb_printf (lg->out, "  store double 0.0, ptr %s\n", objref (lg, v));
		} else {
			int sz = store_size (v);
			sb_printf (lg->out, "  %s = alloca %s, align %d\n", objref (lg, v), ityp (sz), al);
			sb_printf (lg->out, "  store %s 0, ptr %s\n", ityp (sz), objref (lg, v));
		}
	}
	emit_stmt (lg, fn->body);
	if (lg->block_open) {
		if (lg->ret_void) {
			sb_printf (lg->out, "  ret void\n");
		} else {
			sb_printf (lg->out, "  ret %s %s\n", lg->ret_f? "double": "i64",
				lg->ret_f? "0.0": "0");
		}
	}
	sb_printf (lg->out, "}\n\n");
}

static void ll_emit(Aholyc *cc, Program *prog, StrBuf *out,
		bool object_mode, bool ctor_mode) {
	(void)object_mode;
	analyze_exceptions (prog);
	LlGen gen = { .cc = cc, .prog = prog, .out = out, .ctor_mode = ctor_mode };
	LlGen *lg = &gen;
	sb_printf (lg->out, "; generated by aholyc (HolyC -> LLVM IR)\n\n");
	/* strings */
	for (StrLit *s = prog->strings; s; s = s->next) {
		emit_str_escaped (lg, s);
	}
	/* globals */
	for (Obj *g = prog->globals; g; g = g->next) {
		if (g->is_extern) {
			sb_printf (lg->out, "@%s = external %sglobal i64\n", g->name,
				is_fs_obj (g)? "thread_local ": "");
			continue;
		}
		const char *lnk = g->is_public? "": "internal ";
		if (is_agg (g->ty)) {
			int sz = g->ty->size? g->ty->size: 8;
			sb_printf (lg->out, "%s = %sglobal [%d x i8] zeroinitializer, align 8\n",
				objref (lg, g), lnk, sz);
		} else if (g->ty->kind == TY_F64) {
			sb_printf (lg->out, "%s = %sglobal double 0.0\n", objref (lg, g), lnk);
		} else {
			sb_printf (lg->out, "%s = %sglobal %s 0\n", objref (lg, g), lnk,
				ityp (g->ty->size? g->ty->size: 8));
		}
	}
	sb_printf (lg->out, "\n");
	/* extern function declares */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (!f->is_extern && f->body) {
			continue;
		}
		if (!f->is_extern && !f->body) {
			continue; /* declared but never defined: skip */
		}
		Type *ret = f->ty->base;
		sb_printf (lg->out, "declare %s @%s(",
			ret->kind == TY_F64? "double": ret->kind == TY_VOID? "void": "i64",
			f->name);
		int np = 0;
		for (Obj *p = f->params; p; p = p->next, np++) {
			sb_printf (lg->out, "%s%s", np? ", ": "",
				p->ty->kind == TY_F64? "double": "i64");
		}
		sb_printf (lg->out, ")%s\n",
			f->hints & HINT_INLINE? " alwaysinline":
			f->hints & HINT_NOINLINE? " noinline": "");
	}
	sb_printf (lg->out, "declare ptr @__hc_try_push()\n");
	sb_printf (lg->out, "declare void @__hc_try_pop()\n");
	sb_printf (lg->out, "declare ptr @__hc_fs()\n");
	sb_printf (lg->out, "declare i32 @_setjmp(ptr) returns_twice\n");
	sb_printf (lg->out, "declare double @__hc_pow(double, double)\n");
	sb_printf (lg->out, "declare i64 @llvm.ctpop.i64(i64)\n");
	sb_printf (lg->out, "declare i64 @llvm.cttz.i64(i64, i1)\n");
	sb_printf (lg->out, "declare i64 @llvm.ctlz.i64(i64, i1)\n");
	sb_printf (lg->out, "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n");
	sb_printf (lg->out, "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n");
	if (lg->ctor_mode) {
		sb_printf (lg->out, "declare void @__hc_register_start(ptr)\n");
	}
	sb_printf (lg->out, "\n");
	/* user functions */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (lg, f);
	}
	emit_func (lg, prog->startup);
	if (lg->ctor_mode) {
		sb_printf (lg->out, "define internal void @__hc_ctor() {\n"
			"entry:\n"
			"  call void @__hc_register_start(ptr @__hc_ctor_body)\n"
			"  ret void\n"
			"}\n\n");
		/* register the object's top-level code for program start */
		sb_printf (lg->out, "@llvm.global_ctors = appending global "
			"[1 x { i32, ptr, ptr }] "
			"[{ i32, ptr, ptr } { i32 65535, ptr @__hc_ctor, ptr null }]\n");
	}
}

static int ll_build_obj(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt) {
	if (have_cmd (cc, "clang")) {
		char *argv[] = {
			"clang", (char *)opt, "-w", "-c",
			"-o", (char *)outpath, (char *)artifact, NULL
		};
		return run_cmd (cc, argv);
	}
	if (have_cmd (cc, "llc")) {
		char *argv[] = {
			"llc", "-O2", "-filetype=obj", (char *)artifact,
			"-o", (char *)outpath, NULL
		};
		return run_cmd (cc, argv);
	}
	error (cc, "LLVM backend needs 'clang' or 'llc' in PATH for -c");
	return 1;
}

static int ll_build(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt) {
	/* materialize the runtime C source next to the artifact */
	char *rtpath = xasprintf (cc, "%s.rt.c", artifact);
	write_file (cc, rtpath, aholyc_i_rt_c_src,
		strlen (aholyc_i_rt_c_src));
	int r;
	if (have_cmd (cc, "clang")) {
		const char *inputs[] = { artifact, rtpath };
		r = run_cc (cc, "clang", opt, outpath, inputs, 2, false, true);
	} else if (have_cmd (cc, "llc")) {
		char *spath = xasprintf (cc, "%s.s", artifact);
		char *largv[] = { "llc", "-O2", (char *)artifact, "-o", spath, NULL };
		r = run_cmd (cc, largv);
		if (r == 0) {
			const char *ccbin = getenv ("CC");
			const char *inputs[] = { spath, rtpath };
			r = run_cc (cc, ccbin, opt, outpath, inputs, 2, false, false);
		}
		if (!cc->keep) {
			unlink (spath);
		}
	} else {
		error (cc, "LLVM backend needs 'clang' or 'llc' in PATH "
			"(install the LLVM toolchain, or use -b c)");
		r = 1;
	}
	if (!cc->keep) {
		unlink (rtpath);
	}
	return r;
}

const Backend aholyc_i_backend_ll = {
	.name = "llvm",
	.ext = ".ll",
	.descr = "LLVM-IR text, built to native with clang/llc (no LLVM libs linked)",
	.emit = ll_emit,
	.build = ll_build,
	.build_obj = ll_build_obj,
};
