/* mhc JavaScript backend: linear-memory model on one ArrayBuffer.
 * JS has no goto, and mhc lowers switch/break into gotos, so each function
 * becomes a program-counter state machine: for(;;) switch(pc){...}.
 * Exceptions ride JS exceptions with a per-invocation try-stack.
 */
#include "mhc.h"
#include <unistd.h>
#include <sys/stat.h>

/* ------------------------------------------------------------- strbuf */

typedef struct {
	char *s;
	size_t len, cap;
	bool term;      /* block ended with continue/return */
} Blk;

static Blk *blocks;
static int nblocks, capblocks;
static int cur_blk;
static FILE *o;
static Program *cur_prog;

static void blk_addf(int idx, const char *fmt, ...) {
	char buf[8192];
	va_list ap;
	va_start (ap, fmt);
	vsnprintf (buf, sizeof(buf), fmt, ap);
	va_end (ap);
	Blk *b = &blocks[idx];
	size_t n = strlen (buf);
	while (b->len + n + 1 > b->cap) {
		b->cap = b->cap? b->cap * 2: 256;
		b->s = realloc (b->s, b->cap);
	}
	memcpy (b->s + b->len, buf, n + 1);
	b->len += n;
}

static int new_block(void) {
	if (nblocks >= capblocks) {
		capblocks = capblocks? capblocks * 2: 32;
		blocks = realloc (blocks, capblocks * sizeof(Blk));
	}
	memset (&blocks[nblocks], 0, sizeof(Blk));
	return nblocks++;
}

#define EMIT(...) blk_addf (cur_blk, __VA_ARGS__)

/* ------------------------------------------------------- symbol layout */

typedef struct { int uid; long val; } UidMap;
static UidMap *umap;
static int numap, capumap;

static void uid_set(int uid, long val) {
	if (numap >= capumap) {
		capumap = capumap? capumap * 2: 64;
		umap = realloc (umap, capumap * sizeof(UidMap));
	}
	umap[numap].uid = uid;
	umap[numap].val = val;
	numap++;
}

static long uid_get(int uid) {
	for (int i = numap - 1; i >= 0; i--) {
		if (umap[i].uid == uid) {
			return umap[i].val;
		}
	}
	error ("js backend: no layout for uid %d", uid);
	return 0;
}

/* label name -> block index, per function */
typedef struct { char *name; int blk; } LabMap;
static LabMap lmap[512];
static int nlmap;

static int label_block(const char *name) {
	for (int i = 0; i < nlmap; i++) {
		if (!strcmp (lmap[i].name, name)) {
			return lmap[i].blk;
		}
	}
	if (nlmap >= 512) {
		error ("js backend: too many labels");
	}
	lmap[nlmap].name = xstrdup (name);
	lmap[nlmap].blk = new_block ();
	return lmap[nlmap++].blk;
}

static bool is_agg(Type *ty) {
	return ty && (ty->kind == TY_CLASS || ty->kind == TY_ARRAY);
}

static bool value_unsig(Type *ty) {
	return ty->kind == TY_INT && ty->is_unsigned;
}

static int store_size(Obj *v) {
	if (v->is_param) {
		return 8;
	}
	return v->ty->size? v->ty->size: 8;
}

static int elem_size(Type *ptrty) {
	int s = ptrty->base? ptrty->base->size: 1;
	return s? s: 1;
}

static const char *extname(Obj *fn) {
	/* 'throw' is reserved in JS */
	if (!strcmp (fn->name, "throw")) {
		return "hcThrowFn";
	}
	return fn->name;
}

static char *fname(Obj *fn) {
	if (fn == cur_prog->startup) {
		return xstrdup ("__hc_start");
	}
	if (fn->is_extern) {
		return xstrdup (extname (fn));
	}
	return xasprintf ("hc_%s", fn->name);
}

/* variable address as JS expression */
static char *var_addr(Obj *v) {
	if (v->is_extern) {
		return xasprintf ("EXT.%s", v->name);
	}
	if (v->is_global) {
		return xasprintf ("%ld", uid_get (v->uid));
	}
	return xasprintf ("(fp+%ld)", uid_get (v->uid));
}

static const char *ld_fn(Type *ty, int size) {
	if (ty->kind == TY_F64) {
		return "ldf";
	}
	switch (size) {
	case 1: return ty->is_unsigned? "ldu1": "lds1";
	case 2: return ty->is_unsigned? "ldu2": "lds2";
	case 4: return ty->is_unsigned? "ldu4": "lds4";
	}
	return "ld8";
}

static const char *st_fn(Type *ty, int size) {
	if (ty->kind == TY_F64) {
		return "stf";
	}
	switch (size) {
	case 1: return "st1";
	case 2: return "st2";
	case 4: return "st4";
	}
	return "st8";
}

static char *emit_val(Node *n);
static long str_addr[65536];

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
		return xasprintf ("(%s+%d)", b, n->member_ref->offset);
	}
	default:
		error ("js backend: not an lvalue (node kind %d)", n->kind);
		return NULL;
	}
}

static bool is_f(Node *n) {
	return n->ty && n->ty->kind == TY_F64;
}

static char *emit_call(Node *n) {
	Obj *fn = n->func;
	if (!fn) {
		/* indirect through function table */
		char *callee = emit_val (n->lhs);
		char *args = xstrdup ("");
		for (Node *a = n->args; a; a = a->next) {
			char *v = emit_val (a);
			char *na = xasprintf ("%s%s%s", args, *args? ",": "", v);
			free (args);
			args = na;
		}
		return xasprintf ("FT[(%s)-1](%s)", callee, args);
	}
	char *nm = fname (fn);
	if (fn->is_variadic) {
		char *fixed = xstrdup ("");
		Node *a = n->args;
		int i = 0;
		for (; a && i < n->nfixed; a = a->next, i++) {
			char *v = emit_val (a);
			char *nf = xasprintf ("%s%s%s", fixed, *fixed? ",": "", v);
			free (fixed);
			fixed = nf;
		}
		char *extras = xstrdup ("");
		char *flags = xstrdup ("");
		for (; a; a = a->next) {
			char *v = emit_val (a);
			char *ne = xasprintf ("%s%s%s", extras, *extras? ",": "", v);
			char *nf = xasprintf ("%s%s%d", flags, *flags? ",": "", is_f (a)? 1: 0);
			free (extras);
			free (flags);
			extras = ne;
			flags = nf;
		}
		char *r = xasprintf ("hcVCall(%s,[%s],[%s],[%s])", nm, fixed, extras, flags);
		if (n->ty && n->ty->kind == TY_VOID) {
			char *w = xasprintf ("((%s),0)", r);
			free (r);
			return w;
		}
		return r;
	}
	char *args = xstrdup ("");
	for (Node *a = n->args; a; a = a->next) {
		char *v = emit_val (a);
		char *na = xasprintf ("%s%s%s", args, *args? ",": "", v);
		free (args);
		args = na;
	}
	char *r = xasprintf ("%s(%s)", nm, args);
	if (n->ty && n->ty->kind == TY_VOID) {
		char *w = xasprintf ("((%s),0)", r);
		free (r);
		return w;
	}
	return r;
}

static const char *wrap_fn(Type *ty) {
	switch (ty->size) {
	case 1: return ty->is_unsigned? "wrapu8": "wrap8";
	case 2: return ty->is_unsigned? "wrapu16": "wrap16";
	case 4: return ty->is_unsigned? "wrapu32": "wrap32";
	}
	return NULL;
}

static char *emit_val(Node *n) {
	switch (n->kind) {
	case ND_NUM:
		return xasprintf ("%lld", (long long)n->ival);
	case ND_FNUM: {
		char buf[64];
		snprintf (buf, sizeof(buf), "%.17g", n->fval);
		return xstrdup (buf);
	}
	case ND_STR:
		return xasprintf ("%ld", str_addr[n->str_id]);
	case ND_VAR: {
		Obj *v = n->var;
		if (is_agg (v->ty)) {
			return var_addr (v);
		}
		return xasprintf ("%s(%s)", ld_fn (v->ty, store_size (v)), var_addr (v));
	}
	case ND_FUNCNAME:
		return xasprintf ("%ld", uid_get (n->func->uid));
	case ND_DEREF:
		if (is_agg (n->ty)) {
			return emit_val (n->lhs);
		}
		return xasprintf ("%s(%s)", ld_fn (n->ty, n->ty->size? n->ty->size: 8),
			emit_val (n->lhs));
	case ND_MEMBER:
		if (is_agg (n->ty)) {
			return emit_addr (n);
		}
		return xasprintf ("%s(%s)", ld_fn (n->ty, n->ty->size? n->ty->size: 8),
			emit_addr (n));
	case ND_ADDR:
		return emit_addr (n->lhs);
	case ND_ASSIGN: {
		Node *l = n->lhs;
		char *rv = emit_val (n->rhs);
		if (l->ty && l->ty->kind == TY_CLASS) {
			return xasprintf ("MemCpy(%s,%s,%d)", emit_addr (l), rv, l->ty->size);
		}
		if (l->kind == ND_VAR && l->var->is_param && l->ty->kind != TY_F64 &&
		    l->ty->size && l->ty->size < 8) {
			/* narrow declared type in a 64-bit param slot */
			return xasprintf ("st8(%s,%s(%s))", var_addr (l->var),
				wrap_fn (l->ty), rv);
		}
		int sz = l->kind == ND_VAR? store_size (l->var):
			(l->ty->size? l->ty->size: 8);
		return xasprintf ("%s(%s,%s)", st_fn (l->ty, sz), emit_addr (l), rv);
	}
	case ND_CAST: {
		Type *to = n->ty, *from = n->lhs->ty;
		char *v = emit_val (n->lhs);
		if (to->kind == TY_F64 && from->kind != TY_F64) {
			if (value_unsig (from)) {
				return xasprintf ("((%s)<0?(%s)+18446744073709551616:(%s))", v, v, v);
			}
			return v;
		}
		if (to->kind != TY_F64 && from->kind == TY_F64) {
			char *t = xasprintf ("Math.trunc(%s)", v);
			if (to->kind == TY_INT && to->size < 8) {
				return xasprintf ("%s(%s)", wrap_fn (to), t);
			}
			return t;
		}
		if (to->kind == TY_INT && to->size < 8) {
			return xasprintf ("%s(%s)", wrap_fn (to), v);
		}
		return v;
	}
	case ND_ADD:
	case ND_SUB: {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = lt && (lt->kind == TY_PTR || lt->kind == TY_ARRAY);
		bool rp = rt && (rt->kind == TY_PTR || rt->kind == TY_ARRAY);
		char *a = emit_val (n->lhs);
		char *b = emit_val (n->rhs);
		if (lp && rp && n->kind == ND_SUB) {
			return xasprintf ("divi((%s)-(%s),%d)", a, b, elem_size (lt));
		}
		if (lp) {
			return xasprintf ("((%s)%s(%s)*%d)", a,
				n->kind == ND_ADD? "+": "-", b, elem_size (lt));
		}
		return xasprintf ("((%s)%s(%s))", a, n->kind == ND_ADD? "+": "-", b);
	}
	case ND_MUL:
		return xasprintf ("((%s)*(%s))", emit_val (n->lhs), emit_val (n->rhs));
	case ND_DIV:
		if (n->ty->kind == TY_F64) {
			return xasprintf ("((%s)/(%s))", emit_val (n->lhs), emit_val (n->rhs));
		}
		return xasprintf ("%s(%s,%s)", n->ty->is_unsigned? "divu": "divi",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_MOD:
		if (n->ty->kind == TY_INT && n->ty->is_unsigned) {
			return xasprintf ("remu(%s,%s)", emit_val (n->lhs), emit_val (n->rhs));
		}
		return xasprintf ("((%s)%%(%s))", emit_val (n->lhs), emit_val (n->rhs));
	case ND_AND:
		return xasprintf ("and64(%s,%s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_OR:
		return xasprintf ("or64(%s,%s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_XOR:
		return xasprintf ("xor64(%s,%s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_SHL:
		return xasprintf ("shl64(%s,%s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_SHR:
		return xasprintf ("%s(%s,%s)",
			n->ty->kind == TY_INT && n->ty->is_unsigned? "lshr64": "ashr64",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_POW:
		return xasprintf ("Math.pow(%s,%s)", emit_val (n->lhs), emit_val (n->rhs));
	case ND_EQ: case ND_NE: case ND_LT: case ND_LE: {
		bool unsig = n->lhs->ty->kind == TY_INT &&
			(value_unsig (n->lhs->ty) || value_unsig (n->rhs->ty));
		char *a = emit_val (n->lhs);
		char *b = emit_val (n->rhs);
		if (unsig && (n->kind == ND_LT || n->kind == ND_LE)) {
			return xasprintf ("%s(%s,%s)", n->kind == ND_LT? "ltu": "leu", a, b);
		}
		const char *op = n->kind == ND_EQ? "===": n->kind == ND_NE? "!==":
			n->kind == ND_LT? "<": "<=";
		return xasprintf ("((%s)%s(%s)?1:0)", a, op, b);
	}
	case ND_LOGAND:
		return xasprintf ("((%s)!==0?(((%s)!==0)?1:0):0)",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_LOGOR:
		return xasprintf ("((%s)!==0?1:(((%s)!==0)?1:0))",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_LOGXOR:
		return xasprintf ("(((%s)!==0)!==((%s)!==0)?1:0)",
			emit_val (n->lhs), emit_val (n->rhs));
	case ND_NOT:
		return xasprintf ("((%s)===0?1:0)", emit_val (n->lhs));
	case ND_BITNOT:
		return xasprintf ("not64(%s)", emit_val (n->lhs));
	case ND_NEG:
		return xasprintf ("(-(%s))", emit_val (n->lhs));
	case ND_COMMA:
		return xasprintf ("((%s),(%s))", emit_val (n->lhs), emit_val (n->rhs));
	case ND_CALL:
		return emit_call (n);
	case ND_NOP:
		return xstrdup ("0");
	default:
		error ("js backend: unexpected node kind %d in expression", n->kind);
		return NULL;
	}
}

/* --------------------------------------------------------- statements */

static bool cur_retv;

static void jump_to(int blk) {
	EMIT ("pc=%d;continue;\n", blk);
	blocks[cur_blk].term = true;
}

static void emit_stmt(Node *n) {
	if (blocks[cur_blk].term && n->kind != ND_LABEL) {
		/* unreachable code after goto/return: park it in a dead block */
		cur_blk = new_block ();
	}
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT: {
		char *v = emit_val (n->lhs);
		EMIT ("%s;\n", v);
		break;
	}
	case ND_BLOCK:
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (s);
		}
		break;
	case ND_IF: {
		int tb = new_block ();
		int eb = n->els? new_block (): -1;
		int db = new_block ();
		char *c = emit_val (n->cond);
		EMIT ("pc=(%s)!==0?%d:%d;continue;\n", c, tb, n->els? eb: db);
		blocks[cur_blk].term = true;
		cur_blk = tb;
		emit_stmt (n->then);
		if (!blocks[cur_blk].term) {
			jump_to (db);
		}
		if (n->els) {
			cur_blk = eb;
			emit_stmt (n->els);
			if (!blocks[cur_blk].term) {
				jump_to (db);
			}
		}
		cur_blk = db;
		break;
	}
	case ND_WHILE: {
		int hb = new_block (), bb = new_block (), db = new_block ();
		jump_to (hb);
		cur_blk = hb;
		char *c = emit_val (n->cond);
		EMIT ("pc=(%s)!==0?%d:%d;continue;\n", c, bb, db);
		blocks[cur_blk].term = true;
		cur_blk = bb;
		emit_stmt (n->then);
		if (!blocks[cur_blk].term) {
			jump_to (hb);
		}
		cur_blk = db;
		break;
	}
	case ND_DOWHILE: {
		int bb = new_block (), hb = new_block (), db = new_block ();
		jump_to (bb);
		cur_blk = bb;
		emit_stmt (n->then);
		if (!blocks[cur_blk].term) {
			jump_to (hb);
		}
		cur_blk = hb;
		char *c = emit_val (n->cond);
		EMIT ("pc=(%s)!==0?%d:%d;continue;\n", c, bb, db);
		blocks[cur_blk].term = true;
		cur_blk = db;
		break;
	}
	case ND_FOR: {
		if (n->init) {
			emit_stmt (n->init);
		}
		int hb = new_block (), bb = new_block (), db = new_block ();
		jump_to (hb);
		cur_blk = hb;
		if (n->cond) {
			char *c = emit_val (n->cond);
			EMIT ("pc=(%s)!==0?%d:%d;continue;\n", c, bb, db);
			blocks[cur_blk].term = true;
		} else {
			jump_to (bb);
		}
		cur_blk = bb;
		emit_stmt (n->then);
		if (n->inc && !blocks[cur_blk].term) {
			emit_stmt (n->inc);
		}
		if (!blocks[cur_blk].term) {
			jump_to (hb);
		}
		cur_blk = db;
		break;
	}
	case ND_RETURN:
		if (n->lhs) {
			char *v = emit_val (n->lhs);
			EMIT ("return (%s);\n", v);
		} else {
			EMIT ("return 0;\n");
		}
		blocks[cur_blk].term = true;
		break;
	case ND_GOTO:
		jump_to (label_block (n->label));
		break;
	case ND_LABEL: {
		int b = label_block (n->label);
		if (!blocks[cur_blk].term) {
			jump_to (b);
		}
		cur_blk = b;
		break;
	}
	case ND_TRY: {
		int body = new_block (), catchb = new_block (), db = new_block ();
		EMIT ("__tries.push(%d);", catchb);
		jump_to (body);
		cur_blk = body;
		emit_stmt (n->then);
		if (!blocks[cur_blk].term) {
			EMIT ("__tries.pop();");
			jump_to (db);
		}
		cur_blk = catchb;
		emit_stmt (n->els);
		if (!blocks[cur_blk].term) {
			EMIT ("if(ld8(TASK+8)===0)hcThrowFn(ld8(TASK));\n");
			jump_to (db);
		}
		cur_blk = db;
		break;
	}
	default: {
		char *v = emit_val (n);
		EMIT ("%s;\n", v);
		break;
	}
	}
}

/* ------------------------------------------------------------ function */

static long align8(long v) {
	return (v + 7) & ~7L;
}

static void emit_func(Obj *fn) {
	/* frame layout */
	long off = 0;
	int np = 0;
	for (Obj *p = fn->params; p; p = p->next, np++) {
		uid_set (p->uid, off);
		off += 8;
	}
	for (Obj *v = fn->locals; v; v = v->next) {
		uid_set (v->uid, off);
		off += align8 (v->ty->size? v->ty->size: 8);
	}
	long framesz = off;

	nblocks = 0;
	nlmap = 0;
	cur_retv = fn->ty->base && fn->ty->base->kind == TY_VOID;
	(void)cur_retv;
	int entry = new_block ();
	cur_blk = entry;
	emit_stmt (fn->body);
	if (!blocks[cur_blk].term) {
		blk_addf (cur_blk, "return 0;\n");
	}

	fprintf (o, "function %s(", fname (fn));
	for (int i = 0; i < np; i++) {
		fprintf (o, "%sa%d", i? ",": "", i);
	}
	fprintf (o, "){\n");
	fprintf (o, " const fp=FP;FP+=%ld;\n", framesz);
	if (framesz) {
		fprintf (o, " U8A.fill(0,fp,fp+%ld);\n", framesz);
	}
	np = 0;
	for (Obj *p = fn->params; p; p = p->next, np++) {
		fprintf (o, " %s(fp+%ld,a%d);\n",
			p->ty->kind == TY_F64? "stf": "st8", uid_get (p->uid), np);
	}
	fprintf (o, " const __tries=[];let pc=%d;\n", entry);
	fprintf (o, " try{for(;;){try{switch(pc){\n");
	for (int i = 0; i < nblocks; i++) {
		fprintf (o, " case %d:{\n%s }\n", i, blocks[i].s? blocks[i].s: "");
	}
	fprintf (o, " default:return 0;\n");
	fprintf (o, " }}catch(e){if(e!==HCEXC)throw e;"
		"if(__tries.length){pc=__tries.pop();continue;}throw e;}}}\n");
	fprintf (o, " finally{FP=fp;}\n}\n");
}

/* ---------------------------------------------------------------- emit */

static void js_emit(Program *prog, FILE *out) {
	o = out;
	cur_prog = prog;
	numap = 0;
	fprintf (o, "#!/usr/bin/env node\n");
	fputs (rt_js_src, o);

	/* data layout: strings then globals, from address 64 */
	long addr = 64;
	for (StrLit *s = prog->strings; s; s = s->next) {
		str_addr[s->id] = addr;
		addr = align8 (addr + s->len + 1);
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (g->is_extern) {
			continue;
		}
		uid_set (g->uid, addr);
		long sz = g->ty->size? g->ty->size: 8;
		if (sz < 8) {
			sz = 8;
		}
		addr = align8 (addr + sz);
	}
	/* function table indices */
	int fidx = 0;
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		uid_set (f->uid, ++fidx); /* FT index + 1 */
	}

	/* functions */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (f);
	}
	emit_func (prog->startup);

	/* function table */
	fprintf (o, "const FT=[");
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		fprintf (o, "hc_%s,", f->name);
	}
	fprintf (o, "];\n");

	/* data init */
	for (StrLit *s = prog->strings; s; s = s->next) {
		fprintf (o, "D(%ld,[", str_addr[s->id]);
		for (int i = 0; i < s->len; i++) {
			fprintf (o, "%d,", (unsigned char)s->data[i]);
		}
		fprintf (o, "0]);\n");
	}
	fprintf (o, "setLayout(%ld);\n", addr);

	/* run */
	fprintf (o, "try{__hc_start();}catch(e){if(e===HCEXC){"
		"process.stderr.write(\"Unhandled Exception '\"+chstr(ld8(TASK))+\"'\\n\");"
		"process.exit(1);}throw e;}\n");
}

static int js_build(const char *artifact, const char *outpath,
                    const char *opt, bool verbose, bool keep) {
	(void)opt;
	(void)keep;
	/* the artifact is already a runnable node script: install + chmod */
	FILE *in = fopen (artifact, "rb");
	if (!in) {
		error ("cannot read %s", artifact);
	}
	FILE *outf = fopen (outpath, "wb");
	if (!outf) {
		fclose (in);
		error ("cannot write %s", outpath);
	}
	char buf[65536];
	size_t n;
	while ((n = fread (buf, 1, sizeof(buf), in)) > 0) {
		fwrite (buf, 1, n, outf);
	}
	fclose (in);
	fclose (outf);
	chmod (outpath, 0755);
	if (verbose) {
		fprintf (stderr, "mhc: wrote node script %s\n", outpath);
	}
	if (!have_cmd ("node")) {
		fprintf (stderr, "mhc: warning: 'node' not found in PATH; "
			"%s needs a JavaScript runtime\n", outpath);
	}
	return 0;
}

const Backend backend_js = {
	.name = "js",
	.ext = ".js",
	.descr = "JavaScript for node (linear-memory model)",
	.emit = js_emit,
	.build = js_build,
};
