/* aholyc LLVM-IR backend: emits textual .ll and builds a native executable
 * with the external LLVM toolchain (clang, or llc + system cc). aholyc never
 * links against LLVM libraries — it only writes IR files.
 *
 * Model: every local is an alloca (LLVM's mem2reg cleans that up), every
 * scalar value is i64 or double, addresses are i64 (inttoptr at use).
 */
#include "aholyc.h"
#include <unistd.h>

static FILE *o;
static Program *cur_prog;
static int ntmp, nlab;
static bool blk_open;       /* current basic block accepts instructions */
static int try_depth;
static bool cur_retf, cur_retv;

static char *tmp_(void) {
	return xasprintf ("%%t%d", ++ntmp);
}

static char *newlab(const char *hint) {
	return xasprintf ("B%s%d", hint, ++nlab);
}

static void ensure_block(void) {
	if (!blk_open) {
		fprintf (o, "dead%d:\n", ++nlab);
		blk_open = true;
	}
}

static void br_to(const char *lab) {
	ensure_block ();
	fprintf (o, "  br label %%%s\n", lab);
	blk_open = false;
}

static void place_label(const char *lab) {
	if (blk_open) {
		fprintf (o, "  br label %%%s\n", lab);
	}
	fprintf (o, "%s:\n", lab);
	blk_open = true;
}

static char *labname(const char *l) {
	char *s = xasprintf ("L%s", l);
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

static char *objref(Obj *v) {
	if (v->is_extern || v->is_public) {
		return xasprintf ("@%s", v->name);
	}
	if (v->is_func) {
		if (cur_prog && v == cur_prog->startup) {
			return xstrdup (aholyc_ctor_mode? "@__hc_ctor_body": "@__hc_start");
		}
		return xasprintf ("@hc_%s", v->name);
	}
	if (v->is_global) {
		return xasprintf ("@g%d_%s", v->uid, v->name);
	}
	return xasprintf ("%%l%d_%s", v->uid, v->name);
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
static char *apply_bits_hint(char *val, Type *ty) {
	int bits = ty->bits;
	if (!bits || bits == 64) {
		return val;
	}
	ensure_block ();
	char *n = tmp_ ();
	fprintf (o, "  %s = trunc i64 %s to i%d\n", n, val, bits);
	char *w = tmp_ ();
	fprintf (o, "  %s = %s i%d %s to i64\n", w,
		ty->is_unsigned? "zext": "sext", bits, n);
	return w;
}

static int elem_size(Type *ptrty) {
	int s = ptrty->base? ptrty->base->size: 1;
	return s? s: 1;
}

static char *emit_val(Node *n);
static char *emit_addr(Node *n);
static void emit_stmt(Node *n);

static char *load_from(char *addr_i64, Type *ty, bool full_width) {
	ensure_block ();
	char *p = tmp_ ();
	fprintf (o, "  %s = inttoptr i64 %s to ptr\n", p, addr_i64);
	char *t = tmp_ ();
	if (ty->kind == TY_F64) {
		fprintf (o, "  %s = load double, ptr %s\n", t, p);
		return t;
	}
	int sz = full_width? 8: (ty->size? ty->size: 8);
	fprintf (o, "  %s = load %s, ptr %s\n", t, ityp (sz), p);
	if (sz == 8) {
		return t;
	}
	char *w = tmp_ ();
	fprintf (o, "  %s = %s %s %s to i64\n", w,
		ty->is_unsigned? "zext": "sext", ityp (sz), t);
	return w;
}

static void store_to(char *addr_i64, char *val, Type *ty, bool full_width) {
	ensure_block ();
	char *p = tmp_ ();
	fprintf (o, "  %s = inttoptr i64 %s to ptr\n", p, addr_i64);
	if (ty->kind == TY_F64) {
		fprintf (o, "  store double %s, ptr %s\n", val, p);
		return;
	}
	int sz = full_width? 8: (ty->size? ty->size: 8);
	if (sz == 8) {
		fprintf (o, "  store i64 %s, ptr %s\n", val, p);
		return;
	}
	char *t = tmp_ ();
	fprintf (o, "  %s = trunc i64 %s to %s\n", t, val, ityp (sz));
	fprintf (o, "  store %s %s, ptr %s\n", ityp (sz), t, p);
}

static char *fnum_lit(double d) {
	union { double d; uint64_t u; } u;
	u.d = d;
	return xasprintf ("0x%016llX", (unsigned long long)u.u);
}

static char *bool_of(char *v, bool isf) {
	ensure_block ();
	char *c = tmp_ ();
	if (isf) {
		fprintf (o, "  %s = fcmp one double %s, 0.0\n", c, v);
	} else {
		fprintf (o, "  %s = icmp ne i64 %s, 0\n", c, v);
	}
	return c;
}

static char *zext_i64(char *i1) {
	char *t = tmp_ ();
	fprintf (o, "  %s = zext i1 %s to i64\n", t, i1);
	return t;
}

/* address of a variable as i64 operand */
static char *var_addr(Obj *v) {
	if (v->is_global || v->is_extern) {
		return xasprintf ("ptrtoint (ptr %s to i64)", objref (v));
	}
	ensure_block ();
	char *t = tmp_ ();
	fprintf (o, "  %s = ptrtoint ptr %s to i64\n", t, objref (v));
	return t;
}

static char *emit_addr(Node *n) {
	switch (n->kind) {
	case ND_VAR:
		return var_addr (n->var);
	case ND_DEREF:
		return emit_val (n->lhs);
	case ND_MEMBER: {
		char *b = emit_addr (n->lhs);
		if (n->member_ref->offset == 0) {
			return b;
		}
		ensure_block ();
		char *t = tmp_ ();
		fprintf (o, "  %s = add i64 %s, %d\n", t, b, n->member_ref->offset);
		return t;
	}
	default:
		error ("LLVM backend: not an lvalue (node kind %d)", n->kind);
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

static char *emit_bit_intrin(Node *n) {
	const char *nm = n->func->name;
	Node *a = n->args;
	if (!strcmp (nm, "BCnt") || !strcmp (nm, "Bsf") || !strcmp (nm, "Bsr")) {
		char *v = emit_val (a);
		ensure_block ();
		char *t = tmp_ ();
		if (!strcmp (nm, "BCnt")) {
			fprintf (o, "  %s = call i64 @llvm.ctpop.i64(i64 %s)\n", t, v);
			return t;
		}
		bool fwd = !strcmp (nm, "Bsf");
		fprintf (o, "  %s = call i64 @llvm.%s.i64(i64 %s, i1 false)\n", t,
			fwd? "cttz": "ctlz", v);
		char *pos = t;
		if (!fwd) {
			pos = tmp_ ();
			fprintf (o, "  %s = sub i64 63, %s\n", pos, t);
		}
		char *c = tmp_ ();
		fprintf (o, "  %s = icmp eq i64 %s, 0\n", c, v);
		char *r = tmp_ ();
		fprintf (o, "  %s = select i1 %s, i64 -1, i64 %s\n", r, c, pos);
		return r;
	}
	/* Bt/Btc/Btr/Bts/LBtc/LBtr/LBts(bit_field, bit): x86 BT addressing,
	 * byte p[bit>>3] bit (bit&7), signed so negative offsets work */
	char *p = emit_val (a);
	char *bit = emit_val (a->next);
	ensure_block ();
	char *off = tmp_ ();
	fprintf (o, "  %s = ashr i64 %s, 3\n", off, bit);
	char *ba = tmp_ ();
	fprintf (o, "  %s = add i64 %s, %s\n", ba, p, off);
	char *ptr = tmp_ ();
	fprintf (o, "  %s = inttoptr i64 %s to ptr\n", ptr, ba);
	char *sh = tmp_ ();
	fprintf (o, "  %s = and i64 %s, 7\n", sh, bit);
	const char *op = bit_rmw_op (nm);
	char *old = tmp_ ();
	if (!op) {
		fprintf (o, "  %s = load i8, ptr %s\n", old, ptr);
	} else {
		char *m = tmp_ ();
		fprintf (o, "  %s = shl i64 1, %s\n", m, sh);
		if (!strcmp (op, "and")) {
			char *inv = tmp_ ();
			fprintf (o, "  %s = xor i64 %s, -1\n", inv, m);
			m = inv;
		}
		char *m8 = tmp_ ();
		fprintf (o, "  %s = trunc i64 %s to i8\n", m8, m);
		if (nm[0] == 'L') {
			fprintf (o, "  %s = atomicrmw %s ptr %s, i8 %s seq_cst\n",
				old, op, ptr, m8);
		} else {
			fprintf (o, "  %s = load i8, ptr %s\n", old, ptr);
			char *nw = tmp_ ();
			fprintf (o, "  %s = %s i8 %s, %s\n", nw, op, old, m8);
			fprintf (o, "  store i8 %s, ptr %s\n", nw, ptr);
		}
	}
	char *w = tmp_ ();
	fprintf (o, "  %s = zext i8 %s to i64\n", w, old);
	char *sv = tmp_ ();
	fprintf (o, "  %s = lshr i64 %s, %s\n", sv, w, sh);
	char *r = tmp_ ();
	fprintf (o, "  %s = and i64 %s, 1\n", r, sv);
	return r;
}

static bool is_bit_intrin(Obj *fn) {
	static const char *names[] = {
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

static char *emit_call(Node *n) {
	Obj *fn = n->func;
	if (is_bit_intrin (fn)) {
		return emit_bit_intrin (n);
	}
	char *args[300];
	bool argf[300];
	int nargs = 0;
	Node *a = n->args;
	int i = 0;
	/* fixed args */
	for (; a && (fn? i < n->nfixed: true); a = a->next, i++) {
		args[nargs] = emit_val (a);
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
			char *v = emit_val (e);
			if (is_f (e)) {
				ensure_block ();
				char *b = tmp_ ();
				fprintf (o, "  %s = bitcast double %s to i64\n", b, v);
				v = b;
			}
			slots[nextras++] = v;
		}
		ensure_block ();
		char *arr = tmp_ ();
		fprintf (o, "  %s = alloca [%d x i64], align 8\n", arr,
			nextras? nextras: 1);
		for (int k = 0; k < nextras; k++) {
			char *gep = tmp_ ();
			fprintf (o, "  %s = getelementptr [%d x i64], ptr %s, i64 0, i64 %d\n",
				gep, nextras? nextras: 1, arr, k);
			fprintf (o, "  store i64 %s, ptr %s\n", slots[k], gep);
		}
		extras_ptr = tmp_ ();
		fprintf (o, "  %s = ptrtoint ptr %s to i64\n", extras_ptr, arr);
	}
	ensure_block ();
	/* return kind */
	bool retf = n->ty && n->ty->kind == TY_F64;
	bool retv = n->ty && n->ty->kind == TY_VOID;
	char *res = retv? NULL: tmp_ ();
	if (res) {
		fprintf (o, "  %s = ", res);
	} else {
		fprintf (o, "  ");
	}
	const char *rty = retf? "double": retv? "void": "i64";
	fprintf (o, "call %s %s(", rty, objref (fn));
	for (int k = 0; k < nargs; k++) {
		fprintf (o, "%s%s %s", k? ", ": "", argf[k]? "double": "i64", args[k]);
	}
	if (fn && fn->is_variadic) {
		fprintf (o, "%si64 %d, i64 %s", nargs? ", ": "", nextras,
			extras_ptr? extras_ptr: "0");
	}
	fprintf (o, ")\n");
	if (retv) {
		return xstrdup ("0");
	}
	return res;
}

/* indirect calls need the callee converted before the call instruction,
 * so they get their own routine */
static char *emit_indirect_call(Node *n) {
	char *callee = emit_val (n->lhs);
	char *args[300];
	bool argf[300];
	int nargs = 0;
	for (Node *a = n->args; a; a = a->next) {
		args[nargs] = emit_val (a);
		argf[nargs] = is_f (a);
		nargs++;
	}
	ensure_block ();
	char *fp = tmp_ ();
	fprintf (o, "  %s = inttoptr i64 %s to ptr\n", fp, callee);
	bool retf = n->ty && n->ty->kind == TY_F64;
	bool retv = n->ty && n->ty->kind == TY_VOID;
	char *res = retv? NULL: tmp_ ();
	if (res) {
		fprintf (o, "  %s = ", res);
	} else {
		fprintf (o, "  ");
	}
	fprintf (o, "call %s %s(", retf? "double": retv? "void": "i64", fp);
	for (int k = 0; k < nargs; k++) {
		fprintf (o, "%s%s %s", k? ", ": "", argf[k]? "double": "i64", args[k]);
	}
	fprintf (o, ")\n");
	return res? res: xstrdup ("0");
}

static char *emit_binop(Node *n) {
	bool ff = n->ty->kind == TY_F64;
	bool unsig = n->ty->kind == TY_INT && n->ty->is_unsigned;
	/* pointer arithmetic scaling */
	if (n->kind == ND_ADD || n->kind == ND_SUB) {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = lt && (lt->kind == TY_PTR || lt->kind == TY_ARRAY);
		bool rp = rt && (rt->kind == TY_PTR || rt->kind == TY_ARRAY);
		if (lp && rp && n->kind == ND_SUB) {
			char *a = emit_val (n->lhs);
			char *b = emit_val (n->rhs);
			ensure_block ();
			char *d = tmp_ ();
			fprintf (o, "  %s = sub i64 %s, %s\n", d, a, b);
			char *q = tmp_ ();
			fprintf (o, "  %s = sdiv i64 %s, %d\n", q, d, elem_size (lt));
			return q;
		}
		if (lp) {
			char *a = emit_val (n->lhs);
			char *b = emit_val (n->rhs);
			ensure_block ();
			char *s = tmp_ ();
			fprintf (o, "  %s = mul i64 %s, %d\n", s, b, elem_size (lt));
			char *r = tmp_ ();
			fprintf (o, "  %s = %s i64 %s, %s\n", r,
				n->kind == ND_ADD? "add": "sub", a, s);
			return r;
		}
	}
	char *a = emit_val (n->lhs);
	char *b = emit_val (n->rhs);
	ensure_block ();
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
	default: error ("llvm: bad binop"); break;
	}
	char *t = tmp_ ();
	fprintf (o, "  %s = %s %s %s, %s\n", t, op, ff? "double": "i64", a, b);
	return t;
}

static char *emit_cmp(Node *n) {
	bool ff = n->lhs->ty->kind == TY_F64;
	bool unsig = !ff && (value_unsig (n->lhs->ty) || value_unsig (n->rhs->ty));
	char *a = emit_val (n->lhs);
	char *b = emit_val (n->rhs);
	ensure_block ();
	const char *cc;
	switch (n->kind) {
	case ND_EQ: cc = ff? "oeq": "eq"; break;
	case ND_NE: cc = ff? "une": "ne"; break;
	case ND_LT: cc = ff? "olt": unsig? "ult": "slt"; break;
	default: cc = ff? "ole": unsig? "ule": "sle"; break;
	}
	char *c = tmp_ ();
	fprintf (o, "  %s = %s %s %s %s, %s\n", c, ff? "fcmp": "icmp", cc,
		ff? "double": "i64", a, b);
	return zext_i64 (c);
}

/* short-circuit && / || via a result slot */
static char *emit_shortcircuit(Node *n) {
	ensure_block ();
	char *slot = tmp_ ();
	fprintf (o, "  %s = alloca i64, align 8\n", slot);
	char *rhsl = newlab ("sc_rhs");
	char *skipl = newlab ("sc_skip");
	char *endl = newlab ("sc_end");
	char *a = emit_val (n->lhs);
	char *ca = bool_of (a, false); /* operands already i64 (to_bool'ed) */
	if (n->kind == ND_LOGAND) {
		fprintf (o, "  br i1 %s, label %%%s, label %%%s\n", ca, rhsl, skipl);
	} else {
		fprintf (o, "  br i1 %s, label %%%s, label %%%s\n", ca, skipl, rhsl);
	}
	blk_open = false;
	place_label (rhsl);
	char *b = emit_val (n->rhs);
	char *cb = bool_of (b, false);
	char *zb = zext_i64 (cb);
	fprintf (o, "  store i64 %s, ptr %s\n", zb, slot);
	br_to (endl);
	place_label (skipl);
	fprintf (o, "  store i64 %d, ptr %s\n", n->kind == ND_LOGAND? 0: 1, slot);
	br_to (endl);
	place_label (endl);
	char *r = tmp_ ();
	fprintf (o, "  %s = load i64, ptr %s\n", r, slot);
	return r;
}

static char *emit_val(Node *n) {
	switch (n->kind) {
	case ND_NUM:
		return xasprintf ("%lld", (long long)n->ival);
	case ND_FNUM:
		return fnum_lit (n->fval);
	case ND_STR:
		return xasprintf ("ptrtoint (ptr @hcs%d to i64)", n->str_id);
	case ND_VAR: {
		Obj *v = n->var;
		if (is_fs_obj (v)) {
			ensure_block ();
			char *p = tmp_ ();
			fprintf (o, "  %s = call ptr @__hc_fs()\n", p);
			char *t = tmp_ ();
			fprintf (o, "  %s = ptrtoint ptr %s to i64\n", t, p);
			return t;
		}
		if (is_agg (v->ty)) {
			return var_addr (v);
		}
		ensure_block ();
		if (v->is_global || v->is_extern) {
			char *addr = var_addr (v);
			char *val = load_from (addr, v->ty, v->is_param);
			return apply_bits_hint (val, v->ty);
		}
		char *t = tmp_ ();
		if (v->ty->kind == TY_F64) {
			fprintf (o, "  %s = load double, ptr %s\n", t, objref (v));
			return t;
		}
		int sz = store_size (v);
		fprintf (o, "  %s = load %s, ptr %s\n", t, ityp (sz), objref (v));
		if (sz == 8) {
			return apply_bits_hint (t, v->ty);
		}
		char *w = tmp_ ();
		fprintf (o, "  %s = %s %s %s to i64\n", w,
			v->ty->is_unsigned? "zext": "sext", ityp (sz), t);
		return apply_bits_hint (w, v->ty);
	}
	case ND_FUNCNAME:
		return xasprintf ("ptrtoint (ptr %s to i64)", objref (n->func));
	case ND_DEREF:
		if (is_agg (n->ty)) {
			return emit_val (n->lhs);
		}
		return apply_bits_hint (load_from (emit_val (n->lhs), n->ty, false), n->ty);
	case ND_MEMBER:
		if (is_agg (n->ty)) {
			return emit_addr (n);
		}
		return apply_bits_hint (load_from (emit_addr (n), n->ty, false), n->ty);
	case ND_ADDR:
		return emit_addr (n->lhs);
	case ND_ASSIGN: {
		Node *l = n->lhs;
		char *rv = emit_val (n->rhs);
		if (l->ty && l->ty->kind == TY_CLASS) {
			char *la = emit_addr (l);
			ensure_block ();
			char *lp = tmp_ (), *rp = tmp_ ();
			fprintf (o, "  %s = inttoptr i64 %s to ptr\n", lp, la);
			fprintf (o, "  %s = inttoptr i64 %s to ptr\n", rp, rv);
			fprintf (o, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %d, i1 false)\n",
				lp, rp, l->ty->size);
			return la;
		}
		rv = apply_bits_hint (rv, l->ty);
		if (l->kind == ND_VAR && !l->var->is_global && !l->var->is_extern) {
			Obj *v = l->var;
			ensure_block ();
			if (v->ty->kind == TY_F64) {
				fprintf (o, "  store double %s, ptr %s\n", rv, objref (v));
				return rv;
			}
			int sz = store_size (v);
			if (sz == 8 && v->is_param && v->ty->size && v->ty->size < 8) {
				/* param slot is 64-bit but declared narrower: truncate */
				char *t = tmp_ ();
				fprintf (o, "  %s = trunc i64 %s to %s\n", t, rv, ityp (v->ty->size));
				char *w = tmp_ ();
				fprintf (o, "  %s = %s %s %s to i64\n", w,
					v->ty->is_unsigned? "zext": "sext", ityp (v->ty->size), t);
				fprintf (o, "  store i64 %s, ptr %s\n", w, objref (v));
				return rv;
			}
			if (sz == 8) {
				fprintf (o, "  store i64 %s, ptr %s\n", rv, objref (v));
				return rv;
			}
			char *t = tmp_ ();
			fprintf (o, "  %s = trunc i64 %s to %s\n", t, rv, ityp (sz));
			fprintf (o, "  store %s %s, ptr %s\n", ityp (sz), t, objref (v));
			return rv;
		}
		store_to (emit_addr (l), rv, l->ty, l->kind == ND_VAR && l->var->is_param);
		return rv;
	}
	case ND_CAST: {
		Type *to = n->ty, *from = n->lhs->ty;
		char *v = emit_val (n->lhs);
		if (to->kind == TY_F64 && from->kind != TY_F64) {
			ensure_block ();
			char *t = tmp_ ();
			fprintf (o, "  %s = %s i64 %s to double\n", t,
				value_unsig (from)? "uitofp": "sitofp", v);
			return t;
		}
		if (to->kind != TY_F64 && from->kind == TY_F64) {
			ensure_block ();
			char *t = tmp_ ();
			fprintf (o, "  %s = fptosi double %s to i64\n", t, v);
			v = t;
			from = ty_i64;
		}
		if (to->kind == TY_INT && to->size < 8) {
			ensure_block ();
			char *t = tmp_ ();
			fprintf (o, "  %s = trunc i64 %s to %s\n", t, v, ityp (to->size));
			char *w = tmp_ ();
			fprintf (o, "  %s = %s %s %s to i64\n", w,
				to->is_unsigned? "zext": "sext", ityp (to->size), t);
			return w;
		}
		return v;
	}
	case ND_ADD: case ND_SUB: case ND_MUL: case ND_DIV: case ND_MOD:
	case ND_AND: case ND_OR: case ND_XOR: case ND_SHL: case ND_SHR:
		return emit_binop (n);
	case ND_POW: {
		char *a = emit_val (n->lhs);
		char *b = emit_val (n->rhs);
		ensure_block ();
		char *t = tmp_ ();
		fprintf (o, "  %s = call double @__hc_pow(double %s, double %s)\n", t, a, b);
		return t;
	}
	case ND_EQ: case ND_NE: case ND_LT: case ND_LE:
		return emit_cmp (n);
	case ND_LOGAND:
	case ND_LOGOR:
		return emit_shortcircuit (n);
	case ND_LOGXOR: {
		char *a = emit_val (n->lhs);
		char *b = emit_val (n->rhs);
		char *ca = bool_of (a, false);
		char *cb = bool_of (b, false);
		ensure_block ();
		char *x = tmp_ ();
		fprintf (o, "  %s = xor i1 %s, %s\n", x, ca, cb);
		return zext_i64 (x);
	}
	case ND_NOT: {
		char *v = emit_val (n->lhs);
		ensure_block ();
		char *c = tmp_ ();
		fprintf (o, "  %s = icmp eq i64 %s, 0\n", c, v);
		return zext_i64 (c);
	}
	case ND_BITNOT: {
		char *v = emit_val (n->lhs);
		ensure_block ();
		char *t = tmp_ ();
		fprintf (o, "  %s = xor i64 %s, -1\n", t, v);
		return t;
	}
	case ND_NEG: {
		char *v = emit_val (n->lhs);
		ensure_block ();
		char *t = tmp_ ();
		if (is_f (n)) {
			fprintf (o, "  %s = fneg double %s\n", t, v);
		} else {
			fprintf (o, "  %s = sub i64 0, %s\n", t, v);
		}
		return t;
	}
	case ND_COMMA:
		emit_val (n->lhs);
		return emit_val (n->rhs);
	case ND_CALL:
		if (n->func) {
			return emit_call (n);
		}
		return emit_indirect_call (n);
	case ND_NOP:
		return xstrdup ("0");
	default:
		error ("LLVM backend: unexpected node kind %d in expression", n->kind);
		return NULL;
	}
}

static void emit_cond_br(Node *cond, const char *tl, const char *fl) {
	char *v = emit_val (cond);
	char *c = bool_of (v, is_f (cond));
	fprintf (o, "  br i1 %s, label %%%s, label %%%s\n", c, tl, fl);
	blk_open = false;
}

static void emit_stmt(Node *n) {
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT:
		emit_val (n->lhs);
		break;
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (s);
		}
		break;
	case ND_IF: {
		char *tl = newlab ("then"), *el = newlab ("else"), *dl = newlab ("endif");
		ensure_block ();
		emit_cond_br (n->cond, tl, n->els? el: dl);
		place_label (tl);
		emit_stmt (n->then);
		br_to (dl);
		if (n->els) {
			place_label (el);
			emit_stmt (n->els);
			br_to (dl);
		}
		place_label (dl);
		break;
	}
	case ND_WHILE: {
		char *hl = newlab ("whead"), *bl = newlab ("wbody"), *el = newlab ("wend");
		br_to (hl);
		place_label (hl);
		emit_cond_br (n->cond, bl, el);
		place_label (bl);
		emit_stmt (n->then);
		br_to (hl);
		place_label (el);
		break;
	}
	case ND_DOWHILE: {
		char *bl = newlab ("dbody"), *hl = newlab ("dcond"), *el = newlab ("dend");
		br_to (bl);
		place_label (bl);
		emit_stmt (n->then);
		br_to (hl);
		place_label (hl);
		emit_cond_br (n->cond, bl, el);
		place_label (el);
		break;
	}
	case ND_FOR: {
		char *hl = newlab ("fhead"), *bl = newlab ("fbody"), *el = newlab ("fend");
		if (n->init) {
			emit_stmt (n->init);
		}
		br_to (hl);
		place_label (hl);
		if (n->cond) {
			emit_cond_br (n->cond, bl, el);
		} else {
			br_to (bl);
		}
		place_label (bl);
		emit_stmt (n->then);
		if (n->inc) {
			emit_stmt (n->inc);
		}
		br_to (hl);
		place_label (el);
		break;
	}
	case ND_RETURN: {
		ensure_block ();
		for (int i = 0; i < try_depth; i++) {
			fprintf (o, "  call void @__hc_try_pop()\n");
		}
		if (cur_retv) {
			fprintf (o, "  ret void\n");
		} else if (n->lhs) {
			char *v = emit_val (n->lhs);
			ensure_block ();
			fprintf (o, "  ret %s %s\n", cur_retf? "double": "i64", v);
		} else {
			fprintf (o, "  ret %s %s\n", cur_retf? "double": "i64",
				cur_retf? "0.0": "0");
		}
		blk_open = false;
		break;
	}
	case ND_GOTO: {
		char *l = labname (n->label);
		br_to (l);
		break;
	}
	case ND_LABEL: {
		char *l = labname (n->label);
		place_label (l);
		break;
	}
	case ND_TRY: {
		ensure_block ();
		char *jb = tmp_ ();
		fprintf (o, "  %s = call ptr @__hc_try_push()\n", jb);
		char *r = tmp_ ();
		fprintf (o, "  %s = call i32 @_setjmp(ptr %s) returns_twice\n", r, jb);
		char *c = tmp_ ();
		fprintf (o, "  %s = icmp eq i32 %s, 0\n", c, r);
		char *tl = newlab ("try"), *cl = newlab ("catch"), *el = newlab ("tryend");
		fprintf (o, "  br i1 %s, label %%%s, label %%%s\n", c, tl, cl);
		blk_open = false;
		place_label (tl);
		try_depth++;
		emit_stmt (n->then);
		try_depth--;
		ensure_block ();
		fprintf (o, "  call void @__hc_try_pop()\n");
		br_to (el);
		place_label (cl);
		emit_stmt (n->els);
		ensure_block ();
		/* if (!Fs->catch_except) throw(Fs->except_ch) */
		char *fsp = tmp_ ();
		fprintf (o, "  %s = call ptr @__hc_fs()\n", fsp);
		char *fs = tmp_ ();
		fprintf (o, "  %s = ptrtoint ptr %s to i64\n", fs, fsp);
		char *cea = tmp_ ();
		fprintf (o, "  %s = add i64 %s, 8\n", cea, fs);
		char *cep = tmp_ ();
		fprintf (o, "  %s = inttoptr i64 %s to ptr\n", cep, cea);
		char *ce = tmp_ ();
		fprintf (o, "  %s = load i64, ptr %s\n", ce, cep);
		char *cc = tmp_ ();
		fprintf (o, "  %s = icmp eq i64 %s, 0\n", cc, ce);
		char *rl = newlab ("rethrow");
		fprintf (o, "  br i1 %s, label %%%s, label %%%s\n", cc, rl, el);
		blk_open = false;
		place_label (rl);
		char *ep = tmp_ ();
		fprintf (o, "  %s = inttoptr i64 %s to ptr\n", ep, fs);
		char *ev = tmp_ ();
		fprintf (o, "  %s = load i64, ptr %s\n", ev, ep);
		fprintf (o, "  call void @throw(i64 %s)\n", ev);
		br_to (el);
		place_label (el);
		break;
	}
	default:
		emit_val (n);
		break;
	}
}

static void emit_str_escaped(StrLit *s) {
	fprintf (o, "@hcs%d = internal constant [%d x i8] c\"", s->id, s->len + 1);
	for (int i = 0; i < s->len; i++) {
		unsigned char c = (unsigned char)s->data[i];
		if (c >= 32 && c < 127 && c != '"' && c != '\\') {
			fputc (c, o);
		} else {
			fprintf (o, "\\%02X", c);
		}
	}
	fprintf (o, "\\00\"\n");
}

static void emit_func(Obj *fn) {
	Type *ret = fn->ty->base;
	cur_retf = ret->kind == TY_F64;
	cur_retv = ret->kind == TY_VOID;
	ntmp = 0;
	nlab = 0;
	try_depth = 0;
	bool is_start = fn == cur_prog->startup;
	bool exported = fn->is_public || (is_start && !aholyc_ctor_mode);
	fprintf (o, "define %s %s %s(", exported? "": "internal",
		cur_retf? "double": cur_retv? "void": "i64", objref (fn));
	int np = 0;
	for (Obj *p = fn->params; p; p = p->next, np++) {
		fprintf (o, "%s%s %%a%d", np? ", ": "",
			p->ty->kind == TY_F64? "double": "i64", np);
	}
	fprintf (o, ")%s {\nentry:\n",
		fn->hints & HINT_INLINE? " alwaysinline":
		fn->hints & HINT_NOINLINE? " noinline": "");
	blk_open = true;
	/* param slots */
	np = 0;
	for (Obj *p = fn->params; p; p = p->next, np++) {
		if (p->ty->kind == TY_F64) {
			fprintf (o, "  %s = alloca double, align 8\n", objref (p));
			fprintf (o, "  store double %%a%d, ptr %s\n", np, objref (p));
		} else {
			fprintf (o, "  %s = alloca i64, align 8\n", objref (p));
			fprintf (o, "  store i64 %%a%d, ptr %s\n", np, objref (p));
		}
	}
	/* locals */
	for (Obj *v = fn->locals; v; v = v->next) {
		if (is_agg (v->ty)) {
			int sz = v->ty->size? v->ty->size: 8;
			fprintf (o, "  %s = alloca [%d x i8], align 8\n", objref (v), sz);
			fprintf (o, "  call void @llvm.memset.p0.i64(ptr %s, i8 0, i64 %d, i1 false)\n",
				objref (v), sz);
		} else if (v->ty->kind == TY_F64) {
			fprintf (o, "  %s = alloca double, align 8\n", objref (v));
			fprintf (o, "  store double 0.0, ptr %s\n", objref (v));
		} else {
			int sz = store_size (v);
			fprintf (o, "  %s = alloca %s, align 8\n", objref (v), ityp (sz));
			fprintf (o, "  store %s 0, ptr %s\n", ityp (sz), objref (v));
		}
	}
	emit_stmt (fn->body);
	if (blk_open) {
		if (cur_retv) {
			fprintf (o, "  ret void\n");
		} else {
			fprintf (o, "  ret %s %s\n", cur_retf? "double": "i64",
				cur_retf? "0.0": "0");
		}
	}
	fprintf (o, "}\n\n");
}

static void ll_emit(Program *prog, FILE *out) {
	o = out;
	cur_prog = prog;
	fprintf (o, "; generated by aholyc (HolyC -> LLVM IR)\n\n");
	/* strings */
	for (StrLit *s = prog->strings; s; s = s->next) {
		emit_str_escaped (s);
	}
	/* globals */
	for (Obj *g = prog->globals; g; g = g->next) {
		if (g->is_extern) {
			fprintf (o, "@%s = external %sglobal i64\n", g->name,
				is_fs_obj (g)? "thread_local ": "");
			continue;
		}
		const char *lnk = g->is_public? "": "internal ";
		if (is_agg (g->ty)) {
			int sz = g->ty->size? g->ty->size: 8;
			fprintf (o, "%s = %sglobal [%d x i8] zeroinitializer, align 8\n",
				objref (g), lnk, sz);
		} else if (g->ty->kind == TY_F64) {
			fprintf (o, "%s = %sglobal double 0.0\n", objref (g), lnk);
		} else {
			fprintf (o, "%s = %sglobal %s 0\n", objref (g), lnk,
				ityp (g->ty->size? g->ty->size: 8));
		}
	}
	fprintf (o, "\n");
	/* extern function declares */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (!f->is_extern && f->body) {
			continue;
		}
		if (!f->is_extern && !f->body) {
			continue; /* declared but never defined: skip */
		}
		Type *ret = f->ty->base;
		fprintf (o, "declare %s @%s(",
			ret->kind == TY_F64? "double": ret->kind == TY_VOID? "void": "i64",
			f->name);
		int np = 0;
		for (Obj *p = f->params; p; p = p->next, np++) {
			fprintf (o, "%s%s", np? ", ": "",
				p->ty->kind == TY_F64? "double": "i64");
		}
		fprintf (o, ")%s\n",
			f->hints & HINT_INLINE? " alwaysinline":
			f->hints & HINT_NOINLINE? " noinline": "");
	}
	fprintf (o, "declare ptr @__hc_try_push()\n");
	fprintf (o, "declare void @__hc_try_pop()\n");
	fprintf (o, "declare ptr @__hc_fs()\n");
	fprintf (o, "declare i32 @_setjmp(ptr) returns_twice\n");
	fprintf (o, "declare double @__hc_pow(double, double)\n");
	fprintf (o, "declare i64 @llvm.ctpop.i64(i64)\n");
	fprintf (o, "declare i64 @llvm.cttz.i64(i64, i1)\n");
	fprintf (o, "declare i64 @llvm.ctlz.i64(i64, i1)\n");
	fprintf (o, "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n");
	fprintf (o, "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n");
	if (aholyc_ctor_mode) {
		fprintf (o, "declare void @__hc_register_start(ptr)\n");
	}
	fprintf (o, "\n");
	/* user functions */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (f);
	}
	emit_func (prog->startup);
	if (aholyc_ctor_mode) {
		fprintf (o, "define internal void @__hc_ctor() {\n"
			"entry:\n"
			"  call void @__hc_register_start(ptr @__hc_ctor_body)\n"
			"  ret void\n"
			"}\n\n");
		/* register the object's top-level code for program start */
		fprintf (o, "@llvm.global_ctors = appending global "
			"[1 x { i32, ptr, ptr }] "
			"[{ i32, ptr, ptr } { i32 65535, ptr @__hc_ctor, ptr null }]\n");
	}
}

static int ll_build_obj(const char *artifact, const char *outpath,
                        const char *opt, bool verbose, bool keep) {
	(void)keep;
	if (have_cmd ("clang")) {
		char *argv[] = {
			"clang", (char *)opt, "-w", "-c",
			"-o", (char *)outpath, (char *)artifact, NULL
		};
		return run_cmd (argv, verbose);
	}
	if (have_cmd ("llc")) {
		char *argv[] = {
			"llc", "-O2", "-filetype=obj", (char *)artifact,
			"-o", (char *)outpath, NULL
		};
		return run_cmd (argv, verbose);
	}
	error ("LLVM backend needs 'clang' or 'llc' in PATH for -c");
	return 1;
}

static int ll_build(const char *artifact, const char *outpath,
                    const char *opt, bool verbose, bool keep) {
	/* materialize the runtime C source next to the artifact */
	char *rtpath = xasprintf ("%s.rt.c", artifact);
	FILE *f = fopen (rtpath, "w");
	if (!f) {
		error ("cannot write %s", rtpath);
	}
	fputs (rt_c_src, f);
	fclose (f);
	int r;
	if (have_cmd ("clang")) {
		char *argv[96];
		int i = 0;
		argv[i++] = "clang";
		argv[i++] = (char *)opt;
		argv[i++] = "-w";
		argv[i++] = "-fno-strict-aliasing";
		argv[i++] = "-ffunction-sections";
		argv[i++] = "-fdata-sections";
#ifdef __APPLE__
		argv[i++] = "-Wl,-dead_strip";
#else
		argv[i++] = "-Wl,--gc-sections";
#endif
		argv[i++] = "-o";
		argv[i++] = (char *)outpath;
		argv[i++] = (char *)artifact;
		argv[i++] = rtpath;
		for (int k = 0; k < aholyc_nccflags; k++) {
			argv[i++] = aholyc_ccflags[k];
		}
		argv[i++] = "-lm";
		argv[i] = NULL;
		r = run_cmd (argv, verbose);
	} else if (have_cmd ("llc")) {
		char *spath = xasprintf ("%s.s", artifact);
		char *largv[] = { "llc", "-O2", (char *)artifact, "-o", spath, NULL };
		r = run_cmd (largv, verbose);
		if (r == 0) {
			const char *cc = getenv ("CC");
			if (!cc || !*cc) {
				cc = "cc";
			}
			char *cargv[96];
			int i = 0;
			cargv[i++] = (char *)cc;
			cargv[i++] = (char *)opt;
			cargv[i++] = "-w";
			cargv[i++] = "-fno-strict-aliasing";
			cargv[i++] = "-o";
			cargv[i++] = (char *)outpath;
			cargv[i++] = spath;
			cargv[i++] = rtpath;
			for (int k = 0; k < aholyc_nccflags; k++) {
				cargv[i++] = aholyc_ccflags[k];
			}
			cargv[i++] = "-lm";
			cargv[i] = NULL;
			r = run_cmd (cargv, verbose);
		}
		if (!keep) {
			unlink (spath);
		}
	} else {
		error ("LLVM backend needs 'clang' or 'llc' in PATH "
			"(install the LLVM toolchain, or use -b c)");
		r = 1;
	}
	if (!keep) {
		unlink (rtpath);
	}
	return r;
}

const Backend backend_ll = {
	.name = "llvm",
	.ext = ".ll",
	.descr = "LLVM-IR text, built to native with clang/llc (no LLVM libs linked)",
	.emit = ll_emit,
	.build = ll_build,
	.build_obj = ll_build_obj,
};
