/* aholyc C backend: emits self-contained portable C99. */
#include "aholyc.h"

static FILE *o;
static int try_depth;
static Program *cur_prog;

static void emit_val(Node *n);
static void emit_addr(Node *n);
static void emit_stmt(Node *n, int ind);

static Type *cur_ret;

static bool value_unsig(Type *ty) {
	return ty->kind == TY_INT && ty->is_unsigned;
}

static bool is_agg(Type *ty) {
	return ty && (ty->kind == TY_CLASS || ty->kind == TY_ARRAY);
}

static bool is_ptr(Type *ty) {
	return ty && (ty->kind == TY_PTR || ty->kind == TY_ARRAY);
}

static bool is_fs_obj(Obj *v) {
	return v->is_extern && v->from_prelude && !strcmp (v->name, "Fs");
}

static const char *scalar_ctype(Type *ty) {
	if (ty->kind == TY_F64) {
		return "hc_f64";
	}
	if (ty->kind == TY_INT) {
		switch (ty->size) {
		case 1: return ty->is_unsigned? "uint8_t": "int8_t";
		case 2: return ty->is_unsigned? "uint16_t": "int16_t";
		case 4: return ty->is_unsigned? "uint32_t": "int32_t";
		}
	}
	return "hc_i64"; /* I64/U64/pointers/functions */
}

static const char *value_ctype(Type *ty) {
	return ty->kind == TY_F64? "hc_f64": "hc_i64";
}

static const char *extern_ctype(Type *ty) {
	return is_ptr (ty)? "void *": value_ctype (ty);
}

static bool signed_i1(Type *ty) {
	return ty->bits == 1 && !ty->is_unsigned;
}

static void emit_bits_begin(Type *ty) {
	if (signed_i1 (ty)) {
		fprintf (o, "-(hc_i64)(");
	} else {
		fprintf (o, "(hc_i64)(%s _BitInt(%d))",
			ty->is_unsigned? "unsigned": "signed", ty->bits);
	}
}

static void emit_bits_end(Type *ty) {
	if (signed_i1 (ty)) {
		fprintf (o, " & 1)");
	}
}

static void emit_narrowed(Node *n, Type *ty) {
	if (ty->bits) {
		emit_bits_begin (ty);
		emit_val (n);
		emit_bits_end (ty);
		return;
	}
	emit_val (n);
}

static char *objname(Obj *v) {
	static char buf[256];
	if (v->is_extern || v->is_public) {
		snprintf (buf, sizeof(buf), "%s", v->name);
	} else if (v->is_func) {
		if (cur_prog && v == cur_prog->startup) {
			snprintf (buf, sizeof(buf), "%s",
				aholyc_ctor_mode? "__hc_ctor_body": "__hc_start");
		} else {
			snprintf (buf, sizeof(buf), "hc_%s", v->name);
		}
	} else if (v->is_global) {
		snprintf (buf, sizeof(buf), "g%d_%s", v->uid, v->name);
	} else {
		snprintf (buf, sizeof(buf), "l%d_%s", v->uid, v->name);
	}
	return buf;
}

static char *labname(const char *l) {
	static char buf[256];
	snprintf (buf, sizeof(buf), "L%s", l);
	for (char *p = buf; *p; p++) {
		if (*p == '.') {
			*p = '_';
		}
	}
	return buf;
}

static int elem_size(Type *ptrty) {
	int s = ptrty->base? ptrty->base->size: 1;
	return s? s: 1; /* U0*: byte-scaled (deviation from TempleOS, see docs) */
}

static void emit_fnum(double d) {
	char buf[64];
	snprintf (buf, sizeof(buf), "%.17g", d);
	if (!strpbrk (buf, ".eEnN")) {
		strcat (buf, ".0");
	}
	fprintf (o, "%s", buf);
}

static void emit_rt_arg(Node *a, Type *pty) {
	if (!is_ptr (pty)) {
		emit_val (a);
	} else if (a->kind == ND_STR) {
		fprintf (o, "hcs%d", a->str_id);
	} else if (a->kind == ND_ADDR && a->lhs->kind == ND_VAR) {
		fprintf (o, "%s%s", is_agg (a->lhs->ty)? "": "&", objname (a->lhs->var));
	} else {
		fprintf (o, "(void *)(intptr_t)");
		emit_val (a);
	}
}

static void emit_call(Node *n, bool value) {
	Obj *fn = n->func;
	bool isvoid = value && n->ty && n->ty->kind == TY_VOID;
	if (isvoid) {
		fprintf (o, "(");
	}
	if (value && fn && fn->is_extern && is_ptr (fn->ty->base)) {
		fprintf (o, "(hc_i64)(intptr_t)");
	}
	if (fn) {
		fprintf (o, "%s(", objname (fn));
		Obj *p = fn->params;
		Node *a = n->args;
		int i = 0;
		for (; a && i < n->nfixed; a = a->next, i++) {
			fprintf (o, "%s", i? ", ": "");
			if (fn->is_extern) {
				emit_rt_arg (a, p? p->ty: ty_i64);
			} else {
				emit_val (a);
			}
			if (p) {
				p = p->next;
			}
		}
		if (fn->is_variadic) {
			/* count extras */
			int extras = 0;
			for (Node *e = a; e; e = e->next) {
				extras++;
			}
			if (i) {
				fprintf (o, ", ");
			}
			fprintf (o, "%d, ", extras);
			if (!fn->is_extern) {
				fprintf (o, "(hc_i64)(intptr_t)");
			}
			if (extras == 0) {
				fprintf (o, "(hc_i64 *)0");
			} else {
				fprintf (o, "(hc_i64[]){");
				for (Node *e = a; e; e = e->next) {
					if (e != a) {
						fprintf (o, ", ");
					}
					if (e->ty && e->ty->kind == TY_F64) {
						fprintf (o, "hc_f2b(");
						emit_val (e);
						fprintf (o, ")");
					} else {
						emit_val (e);
					}
				}
				fprintf (o, "}");
			}
		}
		fprintf (o, ")");
	} else {
		bool retf = n->ty && n->ty->kind == TY_F64;
		fprintf (o, "((%s(*)(", retf? "hc_f64": "hc_i64");
		bool first = true;
		for (Node *e = n->args; e; e = e->next) {
			fprintf (o, "%s", first? "": ", ");
			first = false;
			fprintf (o, "%s", value_ctype (e->ty));
		}
		if (first) {
			fprintf (o, "void");
		}
		fprintf (o, "))(intptr_t)");
		emit_val (n->lhs);
		fprintf (o, ")(");
		first = true;
		for (Node *e = n->args; e; e = e->next) {
			fprintf (o, "%s", first? "": ", ");
			first = false;
			emit_val (e);
		}
		fprintf (o, ")");
	}
	if (isvoid) {
		fprintf (o, ", 0)");
	}
}

static void emit_load(Node *n) {
	Type *ty = n->ty;
	if (is_agg (ty)) {
		emit_addr (n);
		return;
	}
	if (ty->kind == TY_F64) {
		fprintf (o, "*(hc_f64 *)(intptr_t)");
		emit_addr (n);
		return;
	}
	if (ty->bits) {
		emit_bits_begin (ty);
	} else if (ty->kind == TY_INT && ty->size < 8) {
		fprintf (o, "(hc_i64)");
	}
	fprintf (o, "*(%s *)(intptr_t)", scalar_ctype (ty));
	emit_addr (n);
	if (ty->bits) {
		emit_bits_end (ty);
	}
}

static const char *binop(NodeKind kind) {
	static const char *const ops[] = {
		[ND_ADD] = "+", [ND_SUB] = "-", [ND_MUL] = "*", [ND_DIV] = "/",
		[ND_MOD] = "%", [ND_AND] = "&", [ND_OR] = "|", [ND_XOR] = "^",
		[ND_SHL] = "<<", [ND_SHR] = ">>", [ND_EQ] = "==", [ND_NE] = "!=",
		[ND_LT] = "<", [ND_LE] = "<=", [ND_LOGAND] = "&&", [ND_LOGOR] = "||",
		[ND_COMMA] = ",",
	};
	return ops[kind];
}

static void emit_binary(Node *n) {
	fprintf (o, "(");
	emit_val (n->lhs);
	fprintf (o, " %s ", binop (n->kind));
	emit_val (n->rhs);
	fprintf (o, ")");
}

static void emit_unsigned_binary(Node *n) {
	fprintf (o, "(hc_i64)((hc_u64)");
	emit_val (n->lhs);
	fprintf (o, " %s (hc_u64)", binop (n->kind));
	emit_val (n->rhs);
	fprintf (o, ")");
}

static void emit_truth(Node *n) {
	switch (n->kind) {
	case ND_EQ: case ND_NE: case ND_LT: case ND_LE:
		if ((n->kind == ND_LT || n->kind == ND_LE) &&
		    n->lhs->ty->kind == TY_INT &&
		    (value_unsig (n->lhs->ty) || value_unsig (n->rhs->ty))) {
			fprintf (o, "((hc_u64)");
			emit_val (n->lhs);
			fprintf (o, " %s (hc_u64)", binop (n->kind));
			emit_val (n->rhs);
			fprintf (o, ")");
		} else {
			emit_binary (n);
		}
		break;
	case ND_LOGAND:
	case ND_LOGOR:
		fprintf (o, "(");
		emit_truth (n->lhs);
		fprintf (o, " %s ", binop (n->kind));
		emit_truth (n->rhs);
		fprintf (o, ")");
		break;
	case ND_LOGXOR:
		fprintf (o, "(!");
		emit_truth (n->lhs);
		fprintf (o, " != !");
		emit_truth (n->rhs);
		fprintf (o, ")");
		break;
	case ND_NOT:
		fprintf (o, "!");
		emit_truth (n->lhs);
		break;
	default:
		emit_val (n);
	}
}

static void emit_val(Node *n) {
	switch (n->kind) {
	case ND_NUM:
		fprintf (o, "(hc_i64)0x%llxULL", (unsigned long long)n->ival);
		break;
	case ND_FNUM:
		emit_fnum (n->fval);
		break;
	case ND_STR:
		fprintf (o, "(hc_i64)(intptr_t)hcs%d", n->str_id);
		break;
	case ND_VAR: {
		Obj *v = n->var;
		if (is_fs_obj (v)) {
			fprintf (o, "(hc_i64)(intptr_t)__hc_fs()");
		} else if (is_agg (v->ty)) {
			fprintf (o, "(hc_i64)(intptr_t)%s", objname (v));
		} else if (v->ty->kind == TY_F64) {
			fprintf (o, "%s", objname (v));
		} else if (v->ty->bits) {
			emit_bits_begin (v->ty);
			fprintf (o, "%s", objname (v));
			emit_bits_end (v->ty);
		} else if (v->ty->kind == TY_INT && v->ty->size < 8) {
			fprintf (o, "(hc_i64)%s", objname (v));
		} else {
			fprintf (o, "%s", objname (v));
		}
		break;
	}
	case ND_FUNCNAME:
		fprintf (o, "(hc_i64)(intptr_t)&%s", objname (n->func));
		break;
	case ND_DEREF:
		if (is_agg (n->ty)) {
			emit_val (n->lhs); /* class value: address */
		} else {
			emit_load (n);
		}
		break;
	case ND_MEMBER:
		emit_load (n);
		break;
	case ND_ADDR:
		emit_addr (n->lhs);
		break;
	case ND_ASSIGN: {
		Node *l = n->lhs;
		if (l->ty && l->ty->kind == TY_CLASS) {
			fprintf (o, "(hc_i64)(intptr_t)memcpy((void *)(intptr_t)");
			emit_addr (l);
			fprintf (o, ", (void *)(intptr_t)");
			emit_val (n->rhs);
			fprintf (o, ", %d)", l->ty->size);
			break;
		}
		if (l->kind == ND_VAR && !is_agg (l->ty)) {
			fprintf (o, "(%s = ", objname (l->var));
			if (l->ty->bits) {
				emit_narrowed (n->rhs, l->ty);
			} else {
				emit_val (n->rhs);
			}
			fprintf (o, ")");
			break;
		}
		fprintf (o, "(*(%s *)(intptr_t)", scalar_ctype (l->ty));
		emit_addr (l);
		fprintf (o, " = ");
		emit_narrowed (n->rhs, l->ty);
		fprintf (o, ")");
		break;
	}
	case ND_CAST: {
		Type *to = n->ty;
		Type *from = n->lhs->ty;
		if (to->kind == TY_F64 && from->kind != TY_F64) {
			fprintf (o, "(hc_f64)%s", value_unsig (from)? "(hc_u64)": "");
			emit_val (n->lhs);
		} else if (to->kind != TY_F64 && from->kind == TY_F64) {
			if (to->kind == TY_INT && to->size < 8) {
				fprintf (o, "(hc_i64)(%s)(hc_i64)", scalar_ctype (to));
			} else {
				fprintf (o, "(hc_i64)");
			}
			emit_val (n->lhs);
		} else if (to->kind == TY_INT && to->size < 8) {
			fprintf (o, "(hc_i64)(%s)", scalar_ctype (to));
			emit_val (n->lhs);
		} else {
			emit_val (n->lhs);
		}
		break;
	}
	case ND_ADD:
	case ND_SUB: {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = is_ptr (lt);
		bool rp = is_ptr (rt);
		if (lp && rp && n->kind == ND_SUB) {
			fprintf (o, "((");
			emit_val (n->lhs);
			fprintf (o, " - ");
			emit_val (n->rhs);
			fprintf (o, ") / %d)", elem_size (lt));
			break;
		}
		if (lp) {
			fprintf (o, "(");
			emit_val (n->lhs);
			fprintf (o, " %s ", binop (n->kind));
			emit_val (n->rhs);
			fprintf (o, " * %d)", elem_size (lt));
			break;
		}
		emit_binary (n);
		break;
	}
	case ND_MUL:
	case ND_DIV:
	case ND_MOD:
	case ND_SHR: {
		bool unsig = n->ty->kind == TY_INT && n->ty->is_unsigned;
		if (n->ty->kind != TY_F64 && unsig && n->kind != ND_MUL) {
			emit_unsigned_binary (n);
		} else {
			emit_binary (n);
		}
		break;
	}
	case ND_AND:
	case ND_OR:
	case ND_XOR:
	case ND_SHL:
		emit_binary (n);
		break;
	case ND_POW:
		fprintf (o, "__hc_pow(");
		emit_val (n->lhs);
		fprintf (o, ", ");
		emit_val (n->rhs);
		fprintf (o, ")");
		break;
	case ND_EQ:
	case ND_NE:
	case ND_LT:
	case ND_LE:
	case ND_LOGAND:
	case ND_LOGOR:
	case ND_LOGXOR:
	case ND_NOT:
		fprintf (o, "(hc_i64)");
		emit_truth (n);
		break;
	case ND_BITNOT:
		fprintf (o, "~");
		emit_val (n->lhs);
		break;
	case ND_NEG:
		fprintf (o, "-");
		emit_val (n->lhs);
		break;
	case ND_COMMA:
		emit_binary (n);
		break;
	case ND_CALL:
		emit_call (n, true);
		break;
	case ND_NOP:
		fprintf (o, "0");
		break;
	default:
		error ("C backend: unexpected node kind %d in expression", n->kind);
	}
}

static void emit_addr(Node *n) {
	switch (n->kind) {
	case ND_VAR:
		if (is_agg (n->var->ty)) {
			fprintf (o, "(hc_i64)(intptr_t)%s", objname (n->var));
		} else {
			fprintf (o, "(hc_i64)(intptr_t)&%s", objname (n->var));
		}
		break;
	case ND_DEREF:
		emit_val (n->lhs);
		break;
	case ND_MEMBER:
		if (n->member_ref->offset) {
			fprintf (o, "(");
			emit_addr (n->lhs);
			fprintf (o, " + %d)", n->member_ref->offset);
		} else {
			emit_addr (n->lhs);
		}
		break;
	default:
		error ("C backend: not an lvalue (node kind %d)", n->kind);
	}
}

static void ind_(int n) {
	while (n-- > 0) {
		fputc ('\t', o);
	}
}

static void emit_inner(Node *n, int ind) {
	if (n->kind == ND_BLOCK) {
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (s, ind);
		}
	} else {
		emit_stmt (n, ind);
	}
}

static void emit_body(Node *n, int ind) {
	fprintf (o, "{\n");
	emit_inner (n, ind + 1);
	ind_ (ind);
	fprintf (o, "}\n");
}

static void emit_discarded(Node *n) {
	if (n->kind == ND_CALL) {
		emit_call (n, false);
	} else {
		emit_val (n);
	}
}

static void emit_stmt(Node *n, int ind) {
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT:
		ind_ (ind);
		emit_discarded (n->lhs);
		fprintf (o, ";\n");
		break;
	case ND_BLOCK:
		emit_inner (n, ind);
		break;
	case ND_IF:
		ind_ (ind);
		fprintf (o, "if (");
		emit_truth (n->cond);
		fprintf (o, ") ");
		emit_body (n->then, ind);
		if (n->els) {
			ind_ (ind);
			fprintf (o, "else ");
			emit_body (n->els, ind);
		}
		break;
	case ND_WHILE:
		ind_ (ind);
		fprintf (o, "while (");
		emit_truth (n->cond);
		fprintf (o, ") ");
		emit_body (n->then, ind);
		break;
	case ND_DOWHILE:
		ind_ (ind);
		fprintf (o, "do ");
		emit_body (n->then, ind);
		ind_ (ind);
		fprintf (o, "while (");
		emit_truth (n->cond);
		fprintf (o, ");\n");
		break;
	case ND_FOR:
		if (n->init) {
			emit_inner (n->init, ind);
		}
		ind_ (ind);
		fprintf (o, "for (;;) {\n");
		if (n->cond) {
			ind_ (ind + 1);
			fprintf (o, "if (!");
			emit_truth (n->cond);
			fprintf (o, ") break;\n");
		}
		emit_inner (n->then, ind + 1);
		if (n->inc) {
			emit_inner (n->inc, ind + 1);
		}
		ind_ (ind);
		fprintf (o, "}\n");
		break;
	case ND_RETURN:
		for (int i = 0; i < try_depth; i++) {
			ind_ (ind);
			fprintf (o, "__hc_try_pop();\n");
		}
		ind_ (ind);
		if (n->lhs) {
			fprintf (o, "return ");
			emit_val (n->lhs);
			fprintf (o, ";\n");
		} else {
			fprintf (o, "%s\n", cur_ret->kind == TY_VOID? "return;": "return 0;");
		}
		break;
	case ND_GOTO:
		ind_ (ind);
		fprintf (o, "goto %s;\n", labname (n->label));
		break;
	case ND_LABEL:
		ind_ (ind);
		fprintf (o, "%s: ;\n", labname (n->label));
		break;
	case ND_TRY:
		ind_ (ind);
		fprintf (o, "{ void *hjb = __hc_try_push();\n");
		ind_ (ind);
		fprintf (o, "if (!_setjmp(*(jmp_buf *)hjb)) {\n");
		try_depth++;
		emit_inner (n->then, ind + 1);
		try_depth--;
		ind_ (ind + 1);
		fprintf (o, "__hc_try_pop();\n");
		ind_ (ind);
		fprintf (o, "} else {\n");
		emit_inner (n->els, ind + 1);
		ind_ (ind + 1);
		fprintf (o, "if (!__hc_fs()->catch_except) throw(__hc_fs()->except_ch);\n");
		ind_ (ind);
		fprintf (o, "} }\n");
		break;
	default:
		ind_ (ind);
		emit_discarded (n);
		fprintf (o, ";\n");
		break;
	}
}

static void emit_func_sig(Obj *fn) {
	Type *ret = fn->ty->base;
	const char *rc = ret->kind == TY_VOID? "void": value_ctype (ret);
	bool exported = fn->is_public ||
		(cur_prog && fn == cur_prog->startup && !aholyc_ctor_mode);
	fprintf (o, "%s%s%s%s %s(", exported?
		(fn->hints & HINT_INLINE? "extern ": ""): "static ",
		fn->hints & HINT_INLINE? "inline ": "",
		fn->hints & HINT_NOINLINE? "__attribute__((noinline)) ": "", rc, objname (fn));
	bool first = true;
	for (Obj *p = fn->params; p; p = p->next) {
		fprintf (o, "%s%s %s", first? "": ", ", value_ctype (p->ty), objname (p));
		first = false;
	}
	if (first) {
		fprintf (o, "void");
	}
	fprintf (o, ")");
}

static void emit_func(Obj *fn) {
	cur_ret = fn->ty->base;
	emit_func_sig (fn);
	fprintf (o, " {\n");
	for (Obj *v = fn->locals; v; v = v->next) {
		fprintf (o, "\t");
		if (v->align) {
			fprintf (o, "_Alignas(%d) ", v->align < v->ty->align? v->ty->align: v->align);
		}
		if (is_agg (v->ty)) {
			fprintf (o, "hc_i64 %s[%d] = {0};\n", objname (v),
				(v->ty->size + 7) / 8? (v->ty->size + 7) / 8: 1);
		} else if (v->ty->kind == TY_F64) {
			fprintf (o, "hc_f64 %s = 0;\n", objname (v));
		} else if (v->ty->bits && !signed_i1 (v->ty) && !v->address_taken) {
			fprintf (o, "%s _BitInt(%d) %s = 0;\n",
				v->ty->is_unsigned? "unsigned": "signed", v->ty->bits,
				objname (v));
		} else {
			fprintf (o, "%s %s = 0;\n", scalar_ctype (v->ty), objname (v));
		}
	}
	try_depth = 0;
	emit_inner (fn->body, 1);
	if (cur_ret->kind != TY_VOID) {
		fprintf (o, "\treturn 0;\n");
	}
	fprintf (o, "}\n\n");
}

/* only_user skips the runtime API already embedded in the translation unit. */
static void emit_extern_decls(Program *prog, bool only_user) {
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (!f->is_extern || (only_user && f->from_prelude)) {
			continue;
		}
		Type *ret = f->ty->base;
		fprintf (o, "extern %s%s%s %s(",
			f->hints & HINT_INLINE? "inline ": "",
			f->hints & HINT_NOINLINE? "__attribute__((noinline)) ": "",
			ret->kind == TY_VOID? "void": extern_ctype (ret), f->name);
		int np = 0;
		for (Obj *p = f->params; p; p = p->next, np++) {
			fprintf (o, "%s%s", np? ", ": "", extern_ctype (p->ty));
		}
		fprintf (o, "%s);\n", np? "": "void");
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (!g->is_extern || !strcmp (g->name, "Fs") ||
		    (only_user && g->from_prelude)) {
			continue;
		}
		if (is_agg (g->ty)) {
			fprintf (o, "extern hc_i64 %s[];\n", g->name);
		} else {
			fprintf (o, "extern %s %s;\n", scalar_ctype (g->ty), g->name);
		}
	}
}

/* -c mode: the runtime is linked separately, so declare it instead */
static void emit_obj_preamble(Program *prog) {
	fprintf (o,
		"#include <stdint.h>\n"
		"#include <string.h>\n"
		"#include <setjmp.h>\n"
		"#if defined(_MSC_VER)\n"
		"#define HC_TLS __declspec(thread)\n"
		"#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L\n"
		"#define HC_TLS _Thread_local\n"
		"#elif defined(__GNUC__) || defined(__clang__)\n"
		"#define HC_TLS __thread\n"
		"#else\n"
		"#error \"aholyc output needs thread-local storage support\"\n"
		"#endif\n"
		"typedef int64_t hc_i64;\n"
		"typedef uint64_t hc_u64;\n"
		"typedef double hc_f64;\n"
		"typedef struct { hc_i64 except_ch, catch_except; } HcTask;\n"
		"extern HC_TLS HcTask *Fs;\n"
		"extern HcTask *__hc_fs(void);\n"
		"extern void *__hc_try_push(void);\n"
		"extern void __hc_try_pop(void);\n"
		"extern hc_f64 __hc_pow(hc_f64, hc_f64);\n"
		"extern void __hc_register_start(hc_i64 (*)(hc_i64, hc_i64));\n");
	emit_extern_decls (prog, false);
}

static void c_emit(Program *prog, FILE *out) {
	o = out;
	cur_prog = prog;
	fprintf (o, "/* generated by aholyc (HolyC -> C) */\n");
	if (aholyc_obj_mode) {
		emit_obj_preamble (prog);
	} else {
		fprintf (o, "#define HC_API static\n");
		fputs (rt_c_src, o);
		emit_extern_decls (prog, true);
	}
	fprintf (o, "\n/* ---- program ---- */\n");
	fprintf (o, "static hc_i64 hc_f2b(hc_f64 d){hc_i64 v;memcpy(&v,&d,8);return v;}\n");
	for (StrLit *s = prog->strings; s; s = s->next) {
		fprintf (o, "static unsigned char hcs%d[] = {", s->id);
		for (int i = 0; i < s->len; i++) {
			fprintf (o, "%d,", (unsigned char)s->data[i]);
		}
		fprintf (o, "0};\n");
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (g->is_extern) {
			continue; /* declared in the preamble / defined by the runtime */
		}
		const char *sto = g->is_public? "": "static ";
		if (is_agg (g->ty)) {
			int words = (g->ty->size + 7) / 8;
			fprintf (o, "%shc_i64 %s[%d];\n", sto, objname (g), words? words: 1);
		} else if (g->ty->kind == TY_F64) {
			fprintf (o, "%shc_f64 %s;\n", sto, objname (g));
		} else {
			fprintf (o, "%s%s %s;\n", sto, scalar_ctype (g->ty), objname (g));
		}
	}
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func_sig (f);
		fprintf (o, ";\n");
	}
	fprintf (o, "\n");
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (f);
	}
	/* A -c module constructor registers the hidden-pair startup function. */
	emit_func (prog->startup);
	if (aholyc_ctor_mode) {
		fprintf (o, "__attribute__((constructor)) static void __hc_ctor(void) {\n"
			"\t__hc_register_start(__hc_ctor_body);\n"
			"}\n");
	}
}

static const char *pick_cc(void) {
	const char *cc = getenv ("CC");
	if (!cc || !*cc) {
		cc = have_cmd ("cc")? "cc": have_cmd ("clang")? "clang": "gcc";
	}
	return cc;
}

static int c_compile(const char *artifact, const char *outpath,
                     const char *opt, bool verbose, bool keep, bool object) {
	(void)keep;
	char *argv[96];
	int i = 0;
	argv[i++] = (char *)pick_cc ();
	argv[i++] = (char *)opt;
	argv[i++] = "-fno-strict-aliasing";
	argv[i++] = "-w";
	if (object) {
		argv[i++] = "-c";
	} else {
		argv[i++] = "-ffunction-sections";
		argv[i++] = "-fdata-sections";
#ifdef __APPLE__
		argv[i++] = "-Wl,-dead_strip";
#else
		argv[i++] = "-Wl,--gc-sections";
#endif
	}
	argv[i++] = "-o";
	argv[i++] = (char *)outpath;
	argv[i++] = (char *)artifact;
	for (int k = 0; k < aholyc_nccflags; k++) {
		argv[i++] = aholyc_ccflags[k];
	}
	if (!object) {
		argv[i++] = "-lm";
	}
	argv[i] = NULL;
	return run_cmd (argv, verbose);
}

static int c_build_obj(const char *a, const char *o, const char *opt, bool v, bool keep) {
	return c_compile (a, o, opt, v, keep, true);
}

static int c_build(const char *a, const char *o, const char *opt, bool v, bool keep) {
	return c_compile (a, o, opt, v, keep, false);
}

const Backend backend_c = {
	.name = "c",
	.ext = ".c",
	.descr = "portable C99 (built with the system C compiler)",
	.emit = c_emit,
	.build = c_build,
	.build_obj = c_build_obj,
};
