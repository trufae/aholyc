/* aholyc C backend: emits "portable assembly" C99.
 * All values are hc_i64 (or hc_f64); addresses are hc_i64; loads/stores are
 * explicit width-typed derefs. The runtime C source is prepended so the
 * output is one self-contained translation unit.
 */
#include "aholyc.h"

static FILE *o;
static int try_depth;
static Program *cur_prog;

static void emit_val(Node *n);
static void emit_addr(Node *n);
static void emit_stmt(Node *n, int ind);

static bool cur_retf; /* current function returns F64 */
static bool cur_retv; /* current function returns U0 */

static bool value_unsig(Type *ty) {
	return ty->kind == TY_INT && ty->is_unsigned;
}

static bool is_agg(Type *ty) {
	return ty && (ty->kind == TY_CLASS || ty->kind == TY_ARRAY);
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
	fprintf (o, "(%s)", buf);
}

/* cast an argument to a runtime (extern C) function's parameter type */
static void emit_rt_arg(Node *a, Type *pty) {
	if (pty->kind == TY_PTR || pty->kind == TY_ARRAY) {
		fprintf (o, "(void*)(intptr_t)(");
		emit_val (a);
		fprintf (o, ")");
	} else if (pty->kind == TY_F64) {
		fprintf (o, "(hc_f64)(");
		emit_val (a);
		fprintf (o, ")");
	} else {
		fprintf (o, "(hc_i64)(");
		emit_val (a);
		fprintf (o, ")");
	}
}

static void emit_call(Node *n) {
	Obj *fn = n->func;
	bool isvoid = n->ty && n->ty->kind == TY_VOID;
	if (isvoid) {
		fprintf (o, "(");
	}
	if (fn) {
		fprintf (o, "%s(", objname (fn));
		Obj *p = fn->params;
		Node *a = n->args;
		int i = 0;
		/* named params */
		for (; a && i < n->nfixed; a = a->next, i++) {
			if (i) {
				fprintf (o, ",");
			}
			if (fn->is_extern) {
				emit_rt_arg (a, p? p->ty: ty_i64);
			} else {
				if (p && p->ty->kind == TY_F64) {
					fprintf (o, "(hc_f64)(");
				} else {
					fprintf (o, "(hc_i64)(");
				}
				emit_val (a);
				fprintf (o, ")");
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
				fprintf (o, ",");
			}
			fprintf (o, "%d,", extras);
			if (!fn->is_extern) {
				/* Internal pointers use HolyC's integer-address ABI. */
				fprintf (o, "(hc_i64)(intptr_t)(");
			}
			if (extras == 0) {
				fprintf (o, "(hc_i64*)0");
			} else {
				fprintf (o, "(hc_i64[]){");
				for (Node *e = a; e; e = e->next) {
					if (e != a) {
						fprintf (o, ",");
					}
					if (e->ty && e->ty->kind == TY_F64) {
						fprintf (o, "hc_f2b(");
						emit_val (e);
						fprintf (o, ")");
					} else {
						fprintf (o, "(hc_i64)(");
						emit_val (e);
						fprintf (o, ")");
					}
				}
				fprintf (o, "}");
			}
			if (!fn->is_extern) {
				fprintf (o, ")");
			}
		}
		fprintf (o, ")");
	} else {
		/* indirect call through pointer value */
		bool retf = n->ty && n->ty->kind == TY_F64;
		fprintf (o, "((%s(*)(", retf? "hc_f64": "hc_i64");
		bool first = true;
		for (Node *e = n->args; e; e = e->next) {
			if (!first) {
				fprintf (o, ",");
			}
			first = false;
			fprintf (o, "%s", e->ty && e->ty->kind == TY_F64? "hc_f64": "hc_i64");
		}
		if (first) {
			fprintf (o, "void");
		}
		fprintf (o, "))(intptr_t)(");
		emit_val (n->lhs);
		fprintf (o, "))(");
		first = true;
		for (Node *e = n->args; e; e = e->next) {
			if (!first) {
				fprintf (o, ",");
			}
			first = false;
			fprintf (o, "(%s)(", e->ty && e->ty->kind == TY_F64? "hc_f64": "hc_i64");
			emit_val (e);
			fprintf (o, ")");
		}
		fprintf (o, ")");
	}
	if (isvoid) {
		fprintf (o, ",(hc_i64)0)");
	}
}

static void emit_load(Node *n) {
	/* n has an address (emit_addr) and scalar type: load + widen */
	Type *ty = n->ty;
	if (is_agg (ty)) {
		/* aggregate value = its address */
		emit_addr (n);
		return;
	}
	if (ty->kind == TY_F64) {
		fprintf (o, "(*(hc_f64*)(intptr_t)(");
		emit_addr (n);
		fprintf (o, "))");
		return;
	}
	fprintf (o, "((hc_i64)*(%s*)(intptr_t)(", scalar_ctype (ty));
	emit_addr (n);
	fprintf (o, "))");
}

static void emit_val(Node *n) {
	switch (n->kind) {
	case ND_NUM:
		fprintf (o, "((hc_i64)0x%llxULL)", (unsigned long long)n->ival);
		break;
	case ND_FNUM:
		emit_fnum (n->fval);
		break;
	case ND_STR:
		fprintf (o, "((hc_i64)(intptr_t)hcs%d)", n->str_id);
		break;
	case ND_VAR: {
		Obj *v = n->var;
		if (is_fs_obj (v)) {
			fprintf (o, "((hc_i64)(intptr_t)__hc_fs())");
		} else if (is_agg (v->ty)) {
			fprintf (o, "((hc_i64)(intptr_t)%s)", objname (v));
		} else if (v->ty->kind == TY_F64) {
			fprintf (o, "%s", objname (v));
		} else {
			fprintf (o, "((hc_i64)%s)", objname (v));
		}
		break;
	}
	case ND_FUNCNAME:
		fprintf (o, "((hc_i64)(intptr_t)&%s)", objname (n->func));
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
			fprintf (o, "((hc_i64)(intptr_t)memcpy((void*)(intptr_t)(");
			emit_addr (l);
			fprintf (o, "),(void*)(intptr_t)(");
			emit_val (n->rhs);
			fprintf (o, "),%d))", l->ty->size);
			break;
		}
		if (l->kind == ND_VAR && !is_agg (l->ty)) {
			fprintf (o, "(%s=(%s)(", objname (l->var), scalar_ctype (l->ty));
			emit_val (n->rhs);
			fprintf (o, "))");
			break;
		}
		fprintf (o, "(*(%s*)(intptr_t)(", scalar_ctype (l->ty));
		emit_addr (l);
		fprintf (o, ")=(%s)(", scalar_ctype (l->ty));
		emit_val (n->rhs);
		fprintf (o, "))");
		break;
	}
	case ND_CAST: {
		Type *to = n->ty;
		Type *from = n->lhs->ty;
		if (to->kind == TY_F64 && from->kind != TY_F64) {
			fprintf (o, "((hc_f64)%s(", value_unsig (from)? "(hc_u64)": "");
			emit_val (n->lhs);
			fprintf (o, "))");
		} else if (to->kind != TY_F64 && from->kind == TY_F64) {
			if (to->kind == TY_INT && to->size < 8) {
				fprintf (o, "((hc_i64)(%s)(hc_i64)(", scalar_ctype (to));
				emit_val (n->lhs);
				fprintf (o, "))");
			} else {
				fprintf (o, "((hc_i64)(");
				emit_val (n->lhs);
				fprintf (o, "))");
			}
		} else if (to->kind == TY_INT && to->size < 8) {
			fprintf (o, "((hc_i64)(%s)(", scalar_ctype (to));
			emit_val (n->lhs);
			fprintf (o, "))");
		} else {
			fprintf (o, "(");
			emit_val (n->lhs);
			fprintf (o, ")");
		}
		break;
	}
	case ND_ADD:
	case ND_SUB: {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = lt && (lt->kind == TY_PTR || lt->kind == TY_ARRAY);
		bool rp = rt && (rt->kind == TY_PTR || rt->kind == TY_ARRAY);
		if (lp && rp && n->kind == ND_SUB) {
			fprintf (o, "(((");
			emit_val (n->lhs);
			fprintf (o, ")-(");
			emit_val (n->rhs);
			fprintf (o, "))/%d)", elem_size (lt));
			break;
		}
		if (lp) {
			fprintf (o, "((");
			emit_val (n->lhs);
			fprintf (o, ")%s((", n->kind == ND_ADD? "+": "-");
			emit_val (n->rhs);
			fprintf (o, ")*%d))", elem_size (lt));
			break;
		}
		/* numeric */
		fprintf (o, "((");
		emit_val (n->lhs);
		fprintf (o, ")%s(", n->kind == ND_ADD? "+": "-");
		emit_val (n->rhs);
		fprintf (o, "))");
		break;
	}
	case ND_MUL:
	case ND_DIV:
	case ND_MOD:
	case ND_SHR: {
		const char *op = n->kind == ND_MUL? "*": n->kind == ND_DIV? "/":
			n->kind == ND_MOD? "%": ">>";
		bool unsig = n->ty->kind == TY_INT && n->ty->is_unsigned;
		if (n->ty->kind != TY_F64 && unsig && n->kind != ND_MUL) {
			fprintf (o, "((hc_i64)((hc_u64)(");
			emit_val (n->lhs);
			fprintf (o, ")%s(hc_u64)(", op);
			emit_val (n->rhs);
			fprintf (o, ")))");
		} else {
			fprintf (o, "((");
			emit_val (n->lhs);
			fprintf (o, ")%s(", op);
			emit_val (n->rhs);
			fprintf (o, "))");
		}
		break;
	}
	case ND_AND: case ND_OR: case ND_XOR: case ND_SHL: {
		const char *op = n->kind == ND_AND? "&": n->kind == ND_OR? "|":
			n->kind == ND_XOR? "^": "<<";
		fprintf (o, "((");
		emit_val (n->lhs);
		fprintf (o, ")%s(", op);
		emit_val (n->rhs);
		fprintf (o, "))");
		break;
	}
	case ND_POW:
		fprintf (o, "__hc_pow(");
		emit_val (n->lhs);
		fprintf (o, ",");
		emit_val (n->rhs);
		fprintf (o, ")");
		break;
	case ND_EQ: case ND_NE: case ND_LT: case ND_LE: {
		const char *op = n->kind == ND_EQ? "==": n->kind == ND_NE? "!=":
			n->kind == ND_LT? "<": "<=";
		bool unsig = n->lhs->ty->kind == TY_INT &&
			(value_unsig (n->lhs->ty) || value_unsig (n->rhs->ty));
		if (unsig && (n->kind == ND_LT || n->kind == ND_LE)) {
			fprintf (o, "((hc_i64)((hc_u64)(");
			emit_val (n->lhs);
			fprintf (o, ")%s(hc_u64)(", op);
			emit_val (n->rhs);
			fprintf (o, ")))");
		} else {
			fprintf (o, "((hc_i64)((");
			emit_val (n->lhs);
			fprintf (o, ")%s(", op);
			emit_val (n->rhs);
			fprintf (o, ")))");
		}
		break;
	}
	case ND_LOGAND:
	case ND_LOGOR:
		fprintf (o, "((hc_i64)((");
		emit_val (n->lhs);
		fprintf (o, ")%s(", n->kind == ND_LOGAND? "&&": "||");
		emit_val (n->rhs);
		fprintf (o, ")))");
		break;
	case ND_LOGXOR:
		fprintf (o, "((hc_i64)(!(");
		emit_val (n->lhs);
		fprintf (o, ")!=!(");
		emit_val (n->rhs);
		fprintf (o, ")))");
		break;
	case ND_NOT:
		fprintf (o, "((hc_i64)!(");
		emit_val (n->lhs);
		fprintf (o, "))");
		break;
	case ND_BITNOT:
		fprintf (o, "(~(");
		emit_val (n->lhs);
		fprintf (o, "))");
		break;
	case ND_NEG:
		fprintf (o, "(-(");
		emit_val (n->lhs);
		fprintf (o, "))");
		break;
	case ND_COMMA:
		fprintf (o, "((");
		emit_val (n->lhs);
		fprintf (o, "),(");
		emit_val (n->rhs);
		fprintf (o, "))");
		break;
	case ND_CALL:
		emit_call (n);
		break;
	case ND_NOP:
		fprintf (o, "((hc_i64)0)");
		break;
	default:
		error ("C backend: unexpected node kind %d in expression", n->kind);
	}
}

static void emit_addr(Node *n) {
	switch (n->kind) {
	case ND_VAR:
		if (is_agg (n->var->ty)) {
			fprintf (o, "((hc_i64)(intptr_t)%s)", objname (n->var));
		} else {
			fprintf (o, "((hc_i64)(intptr_t)&%s)", objname (n->var));
		}
		break;
	case ND_DEREF:
		emit_val (n->lhs);
		break;
	case ND_MEMBER:
		fprintf (o, "((");
		emit_addr (n->lhs);
		fprintf (o, ")+%d)", n->member_ref->offset);
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

static void emit_stmt(Node *n, int ind) {
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT:
		ind_ (ind);
		fprintf (o, "(void)(");
		emit_val (n->lhs);
		fprintf (o, ");\n");
		break;
	case ND_BLOCK:
		ind_ (ind);
		fprintf (o, "{\n");
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (s, ind + 1);
		}
		ind_ (ind);
		fprintf (o, "}\n");
		break;
	case ND_IF:
		ind_ (ind);
		fprintf (o, "if (");
		emit_val (n->cond);
		fprintf (o, ") {\n");
		emit_stmt (n->then, ind + 1);
		ind_ (ind);
		fprintf (o, "}\n");
		if (n->els) {
			ind_ (ind);
			fprintf (o, "else {\n");
			emit_stmt (n->els, ind + 1);
			ind_ (ind);
			fprintf (o, "}\n");
		}
		break;
	case ND_WHILE:
		ind_ (ind);
		fprintf (o, "while (");
		emit_val (n->cond);
		fprintf (o, ") {\n");
		emit_stmt (n->then, ind + 1);
		ind_ (ind);
		fprintf (o, "}\n");
		break;
	case ND_DOWHILE:
		ind_ (ind);
		fprintf (o, "do {\n");
		emit_stmt (n->then, ind + 1);
		ind_ (ind);
		fprintf (o, "} while (");
		emit_val (n->cond);
		fprintf (o, ");\n");
		break;
	case ND_FOR:
		ind_ (ind);
		fprintf (o, "{\n");
		if (n->init) {
			emit_stmt (n->init, ind + 1);
		}
		ind_ (ind + 1);
		fprintf (o, "for (;;) {\n");
		if (n->cond) {
			ind_ (ind + 2);
			fprintf (o, "if (!(");
			emit_val (n->cond);
			fprintf (o, ")) break;\n");
		}
		emit_stmt (n->then, ind + 2);
		if (n->inc) {
			emit_stmt (n->inc, ind + 2);
		}
		ind_ (ind + 1);
		fprintf (o, "}\n");
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
			fprintf (o, "return (%s)(", cur_retf? "hc_f64": "hc_i64");
			emit_val (n->lhs);
			fprintf (o, ");\n");
		} else {
			fprintf (o, "%s\n", cur_retv? "return;": "return 0;");
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
		fprintf (o, "if (!_setjmp(*(jmp_buf*)hjb)) {\n");
		try_depth++;
		emit_stmt (n->then, ind + 1);
		try_depth--;
		ind_ (ind + 1);
		fprintf (o, "__hc_try_pop();\n");
		ind_ (ind);
		fprintf (o, "} else {\n");
		emit_stmt (n->els, ind + 1);
		ind_ (ind + 1);
		fprintf (o, "if (!__hc_fs()->catch_except) throw(__hc_fs()->except_ch);\n");
		ind_ (ind);
		fprintf (o, "} }\n");
		break;
	default:
		/* expressions used as a bare statement (shouldn't happen) */
		ind_ (ind);
		fprintf (o, "(void)(");
		emit_val (n);
		fprintf (o, ");\n");
		break;
	}
}

static void emit_func_sig(Obj *fn) {
	Type *ret = fn->ty->base;
	const char *rc = ret->kind == TY_F64? "hc_f64":
		ret->kind == TY_VOID? "void": "hc_i64";
	bool exported = fn->is_public ||
		(cur_prog && fn == cur_prog->startup && !aholyc_ctor_mode);
	fprintf (o, "%s%s %s(", exported? "": "static ", rc, objname (fn));
	bool first = true;
	for (Obj *p = fn->params; p; p = p->next) {
		if (!first) {
			fprintf (o, ",");
		}
		first = false;
		fprintf (o, "%s %s", p->ty->kind == TY_F64? "hc_f64": "hc_i64",
			objname (p));
	}
	if (first) {
		fprintf (o, "void");
	}
	fprintf (o, ")");
}

static void emit_func(Program *prog, Obj *fn) {
	(void)prog;
	cur_retf = fn->ty->base && fn->ty->base->kind == TY_F64;
	cur_retv = fn->ty->base && fn->ty->base->kind == TY_VOID;
	emit_func_sig (fn);
	fprintf (o, " {\n");
	for (Obj *v = fn->locals; v; v = v->next) {
		if (is_agg (v->ty)) {
			fprintf (o, "\thc_i64 %s[%d] = {0};\n", objname (v),
				(v->ty->size + 7) / 8? (v->ty->size + 7) / 8: 1);
		} else if (v->ty->kind == TY_F64) {
			fprintf (o, "\thc_f64 %s = 0;\n", objname (v));
		} else {
			fprintf (o, "\t%s %s = 0;\n", scalar_ctype (v->ty), objname (v));
		}
	}
	try_depth = 0;
	emit_stmt (fn->body, 1);
	if (fn->ty->base->kind != TY_VOID) {
		fprintf (o, "\treturn 0;\n");
	}
	fprintf (o, "}\n\n");
}

/* declare extern symbols, mapped like emit_rt_arg does. only_user skips
 * the runtime API (already defined when rt.c is embedded in the TU). */
static void emit_extern_decls(Program *prog, bool only_user) {
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (!f->is_extern || (only_user && f->from_prelude)) {
			continue;
		}
		Type *ret = f->ty->base;
		fprintf (o, "extern %s %s(",
			ret->kind == TY_F64? "hc_f64":
			ret->kind == TY_VOID? "void":
			ret->kind == TY_PTR? "void *": "hc_i64", f->name);
		int np = 0;
		for (Obj *p = f->params; p; p = p->next, np++) {
			fprintf (o, "%s%s", np? ",": "",
				p->ty->kind == TY_F64? "hc_f64":
				p->ty->kind == TY_PTR || p->ty->kind == TY_ARRAY? "void *":
				"hc_i64");
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
		"extern hc_f64 __hc_pow(hc_f64, hc_f64);\n");
	emit_extern_decls (prog, false);
}

static void c_emit(Program *prog, FILE *out) {
	o = out;
	cur_prog = prog;
	fprintf (o, "/* generated by aholyc (HolyC -> C) */\n");
	if (aholyc_obj_mode) {
		emit_obj_preamble (prog);
	} else {
		/* static runtime: unused API functions get discarded */
		fprintf (o, "#define HC_API static\n");
		fputs (rt_c_src, o);
		emit_extern_decls (prog, true);
	}
	fprintf (o, "\n/* ---- program ---- */\n");
	fprintf (o, "static hc_i64 hc_f2b(hc_f64 d){hc_i64 v;memcpy(&v,&d,8);return v;}\n");
	/* string literals */
	for (StrLit *s = prog->strings; s; s = s->next) {
		fprintf (o, "static unsigned char hcs%d[] = {", s->id);
		for (int i = 0; i < s->len; i++) {
			fprintf (o, "%d,", (unsigned char)s->data[i]);
		}
		fprintf (o, "0};\n");
	}
	/* globals */
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
	/* prototypes */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func_sig (f);
		fprintf (o, ";\n");
	}
	fprintf (o, "\n");
	/* bodies */
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (prog, f);
	}
	/* Startup is a normal hidden-pair function.  A -c module wraps it in a
	 * no-argument constructor because module startup has no process entry. */
	emit_func (prog, prog->startup);
	if (aholyc_ctor_mode) {
		fprintf (o, "static hc_i64 __hc_empty_argv[1];\n"
			"__attribute__((constructor)) static void __hc_ctor(void) {\n"
			"\t__hc_ctor_body(0, (hc_i64)(intptr_t)__hc_empty_argv);\n"
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

static int c_build_obj(const char *artifact, const char *outpath,
                       const char *opt, bool verbose, bool keep) {
	(void)keep;
	char *argv[96];
	int i = 0;
	argv[i++] = (char *)pick_cc ();
	argv[i++] = (char *)opt;
	argv[i++] = "-fno-strict-aliasing";
	argv[i++] = "-w";
	argv[i++] = "-c";
	argv[i++] = "-o";
	argv[i++] = (char *)outpath;
	argv[i++] = (char *)artifact;
	for (int k = 0; k < aholyc_nccflags; k++) {
		argv[i++] = aholyc_ccflags[k];
	}
	argv[i] = NULL;
	return run_cmd (argv, verbose);
}

static int c_build(const char *artifact, const char *outpath,
                   const char *opt, bool verbose, bool keep) {
	(void)keep;
	char *argv[96];
	int i = 0;
	argv[i++] = (char *)pick_cc ();
	argv[i++] = (char *)opt;
	argv[i++] = "-fno-strict-aliasing";
	argv[i++] = "-w";
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
	for (int k = 0; k < aholyc_nccflags; k++) {
		argv[i++] = aholyc_ccflags[k];
	}
	argv[i++] = "-lm";
	argv[i] = NULL;
	return run_cmd (argv, verbose);
}

const Backend backend_c = {
	.name = "c",
	.ext = ".c",
	.descr = "portable C99 (built with the system C compiler)",
	.emit = c_emit,
	.build = c_build,
	.build_obj = c_build_obj,
};
