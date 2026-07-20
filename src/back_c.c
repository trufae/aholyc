/* aholyc C backend: emits self-contained portable C99. */
#include "aholyc.h"

typedef struct {
	Aholyc *cc;
	Program *prog;
	FILE *out;
	Type *ret;
	int try_depth;
	bool ctor_mode;
	char name[256], label[256];
} CGen;

static void emit_val(CGen *cg, Node *n);
static void emit_addr(CGen *cg, Node *n);
static void emit_stmt(CGen *cg, Node *n, int ind);

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

static void emit_bits_begin(CGen *cg, Type *ty) {
	if (signed_i1 (ty)) {
		fprintf (cg->out, "-(hc_i64)(");
	} else {
		fprintf (cg->out, "(hc_i64)(%s _BitInt(%d))",
			ty->is_unsigned? "unsigned": "signed", ty->bits);
	}
}

static void emit_bits_end(CGen *cg, Type *ty) {
	if (signed_i1 (ty)) {
		fprintf (cg->out, " & 1)");
	}
}

static void emit_narrowed(CGen *cg, Node *n, Type *ty) {
	if (ty->bits) {
		emit_bits_begin (cg, ty);
		emit_val (cg, n);
		emit_bits_end (cg, ty);
		return;
	}
	emit_val (cg, n);
}

static char *objname(CGen *cg, Obj *v) {
	char *buf = cg->name;
	if (v->is_extern || v->is_public) {
		snprintf (buf, sizeof(cg->name), "%s", v->name);
	} else if (v->is_func) {
		if (cg->prog && v == cg->prog->startup) {
			snprintf (buf, sizeof(cg->name), "%s",
				cg->ctor_mode? "__hc_ctor_body": "__hc_start");
		} else {
			snprintf (buf, sizeof(cg->name), "hc_%s", v->name);
		}
	} else if (v->is_global) {
		snprintf (buf, sizeof(cg->name), "g%d_%s", v->uid, v->name);
	} else {
		snprintf (buf, sizeof(cg->name), "l%d_%s", v->uid, v->name);
	}
	return buf;
}

static char *labname(CGen *cg, const char *l) {
	char *buf = cg->label;
	snprintf (buf, sizeof(cg->label), "L%s", l);
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

static void emit_fnum(CGen *cg, double d) {
	char buf[64];
	snprintf (buf, sizeof(buf), "%.17g", d);
	if (!strpbrk (buf, ".eEnN")) {
		strcat (buf, ".0");
	}
	fprintf (cg->out, "%s", buf);
}

static void emit_rt_arg(CGen *cg, Node *a, Type *pty) {
	if (!is_ptr (pty)) {
		emit_val (cg, a);
	} else if (a->kind == ND_STR) {
		fprintf (cg->out, "hcs%d", a->str_id);
	} else if (a->kind == ND_ADDR && a->lhs->kind == ND_VAR) {
		fprintf (cg->out, "%s%s", is_agg (a->lhs->ty)? "": "&", objname (cg, a->lhs->var));
	} else {
		fprintf (cg->out, "(void *)(intptr_t)");
		emit_val (cg, a);
	}
}

static void emit_call(CGen *cg, Node *n, bool value) {
	Obj *fn = n->func;
	bool isvoid = value && n->ty && n->ty->kind == TY_VOID;
	if (isvoid) {
		fprintf (cg->out, "(");
	}
	if (value && fn && fn->is_extern && is_ptr (fn->ty->base)) {
		fprintf (cg->out, "(hc_i64)(intptr_t)");
	}
	if (fn) {
		fprintf (cg->out, "%s(", objname (cg, fn));
		Obj *p = fn->params;
		Node *a = n->args;
		int i = 0;
		for (; a && i < n->nfixed; a = a->next, i++) {
			fprintf (cg->out, "%s", i? ", ": "");
			if (fn->is_extern) {
				emit_rt_arg (cg, a, p->ty);
			} else {
				emit_val (cg, a);
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
				fprintf (cg->out, ", ");
			}
			fprintf (cg->out, "%d, ", extras);
			if (!fn->is_extern) {
				fprintf (cg->out, "(hc_i64)(intptr_t)");
			}
			if (extras == 0) {
				fprintf (cg->out, "(hc_i64 *)0");
			} else {
				fprintf (cg->out, "(hc_i64[]){");
				for (Node *e = a; e; e = e->next) {
					if (e != a) {
						fprintf (cg->out, ", ");
					}
					if (e->ty && e->ty->kind == TY_F64) {
						fprintf (cg->out, "hc_f2b(");
						emit_val (cg, e);
						fprintf (cg->out, ")");
					} else {
						emit_val (cg, e);
					}
				}
				fprintf (cg->out, "}");
			}
		}
		fprintf (cg->out, ")");
	} else {
		bool retf = n->ty && n->ty->kind == TY_F64;
		fprintf (cg->out, "((%s(*)(", retf? "hc_f64": "hc_i64");
		bool first = true;
		for (Node *e = n->args; e; e = e->next) {
			fprintf (cg->out, "%s", first? "": ", ");
			first = false;
			fprintf (cg->out, "%s", value_ctype (e->ty));
		}
		if (first) {
			fprintf (cg->out, "void");
		}
		fprintf (cg->out, "))(intptr_t)");
		emit_val (cg, n->lhs);
		fprintf (cg->out, ")(");
		first = true;
		for (Node *e = n->args; e; e = e->next) {
			fprintf (cg->out, "%s", first? "": ", ");
			first = false;
			emit_val (cg, e);
		}
		fprintf (cg->out, ")");
	}
	if (isvoid) {
		fprintf (cg->out, ", 0)");
	}
}

static void emit_load(CGen *cg, Node *n) {
	Type *ty = n->ty;
	if (is_agg (ty)) {
		emit_addr (cg, n);
		return;
	}
	if (ty->kind == TY_F64) {
		fprintf (cg->out, "*(hc_f64 *)(intptr_t)");
		emit_addr (cg, n);
		return;
	}
	if (ty->bits) {
		emit_bits_begin (cg, ty);
	} else if (ty->kind == TY_INT && ty->size < 8) {
		fprintf (cg->out, "(hc_i64)");
	}
	fprintf (cg->out, "*(%s *)(intptr_t)", scalar_ctype (ty));
	emit_addr (cg, n);
	if (ty->bits) {
		emit_bits_end (cg, ty);
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

static void emit_binary(CGen *cg, Node *n) {
	fprintf (cg->out, "(");
	emit_val (cg, n->lhs);
	fprintf (cg->out, " %s ", binop (n->kind));
	emit_val (cg, n->rhs);
	fprintf (cg->out, ")");
}

static void emit_unsigned_binary(CGen *cg, Node *n) {
	fprintf (cg->out, "(hc_i64)((hc_u64)");
	emit_val (cg, n->lhs);
	fprintf (cg->out, " %s (hc_u64)", binop (n->kind));
	emit_val (cg, n->rhs);
	fprintf (cg->out, ")");
}

static void emit_truth(CGen *cg, Node *n) {
	switch (n->kind) {
	case ND_EQ: case ND_NE: case ND_LT: case ND_LE:
		if ((n->kind == ND_LT || n->kind == ND_LE) &&
		    n->lhs->ty->kind == TY_INT &&
		    (value_unsig (n->lhs->ty) || value_unsig (n->rhs->ty))) {
			fprintf (cg->out, "((hc_u64)");
			emit_val (cg, n->lhs);
			fprintf (cg->out, " %s (hc_u64)", binop (n->kind));
			emit_val (cg, n->rhs);
			fprintf (cg->out, ")");
		} else {
			emit_binary (cg, n);
		}
		break;
	case ND_LOGAND:
	case ND_LOGOR:
		fprintf (cg->out, "(");
		emit_truth (cg, n->lhs);
		fprintf (cg->out, " %s ", binop (n->kind));
		emit_truth (cg, n->rhs);
		fprintf (cg->out, ")");
		break;
	case ND_LOGXOR:
		fprintf (cg->out, "(!");
		emit_truth (cg, n->lhs);
		fprintf (cg->out, " != !");
		emit_truth (cg, n->rhs);
		fprintf (cg->out, ")");
		break;
	case ND_NOT:
		fprintf (cg->out, "!");
		emit_truth (cg, n->lhs);
		break;
	default:
		emit_val (cg, n);
	}
}

static void emit_val(CGen *cg, Node *n) {
	switch (n->kind) {
	case ND_NUM:
		fprintf (cg->out, "(hc_i64)0x%llxULL", (unsigned long long)n->ival);
		break;
	case ND_FNUM:
		emit_fnum (cg, n->fval);
		break;
	case ND_STR:
		fprintf (cg->out, "(hc_i64)(intptr_t)hcs%d", n->str_id);
		break;
	case ND_VAR: {
		Obj *v = n->var;
		if (is_fs_obj (v)) {
			fprintf (cg->out, "(hc_i64)(intptr_t)__hc_fs()");
		} else if (is_agg (v->ty)) {
			fprintf (cg->out, "(hc_i64)(intptr_t)%s", objname (cg, v));
		} else if (v->ty->kind == TY_F64) {
			fprintf (cg->out, "%s", objname (cg, v));
		} else if (v->ty->bits) {
			emit_bits_begin (cg, v->ty);
			fprintf (cg->out, "%s", objname (cg, v));
			emit_bits_end (cg, v->ty);
		} else if (v->ty->kind == TY_INT && v->ty->size < 8) {
			fprintf (cg->out, "(hc_i64)%s", objname (cg, v));
		} else {
			fprintf (cg->out, "%s", objname (cg, v));
		}
		break;
	}
	case ND_FUNCNAME:
		fprintf (cg->out, "(hc_i64)(intptr_t)&%s", objname (cg, n->func));
		break;
	case ND_DEREF:
		if (is_agg (n->ty)) {
			emit_val (cg, n->lhs); /* class value: address */
		} else {
			emit_load (cg, n);
		}
		break;
	case ND_MEMBER:
		emit_load (cg, n);
		break;
	case ND_ADDR:
		emit_addr (cg, n->lhs);
		break;
	case ND_ASSIGN: {
		Node *l = n->lhs;
		if (l->ty && l->ty->kind == TY_CLASS) {
			fprintf (cg->out, "(hc_i64)(intptr_t)memcpy((void *)(intptr_t)");
			emit_addr (cg, l);
			fprintf (cg->out, ", (void *)(intptr_t)");
			emit_val (cg, n->rhs);
			fprintf (cg->out, ", %d)", l->ty->size);
			break;
		}
		if (l->kind == ND_VAR && !is_agg (l->ty)) {
			fprintf (cg->out, "(%s = ", objname (cg, l->var));
			if (l->ty->bits) {
				emit_narrowed (cg, n->rhs, l->ty);
			} else {
				emit_val (cg, n->rhs);
			}
			fprintf (cg->out, ")");
			break;
		}
		fprintf (cg->out, "(*(%s *)(intptr_t)", scalar_ctype (l->ty));
		emit_addr (cg, l);
		fprintf (cg->out, " = ");
		emit_narrowed (cg, n->rhs, l->ty);
		fprintf (cg->out, ")");
		break;
	}
	case ND_CAST: {
		Type *to = n->ty;
		Type *from = n->lhs->ty;
		if (to->kind == TY_F64 && from->kind != TY_F64) {
			fprintf (cg->out, "(hc_f64)%s", value_unsig (from)? "(hc_u64)": "");
			emit_val (cg, n->lhs);
		} else if (to->kind != TY_F64 && from->kind == TY_F64) {
			if (to->kind == TY_INT && to->size < 8) {
				fprintf (cg->out, "(hc_i64)(%s)(hc_i64)", scalar_ctype (to));
			} else {
				fprintf (cg->out, "(hc_i64)");
			}
			emit_val (cg, n->lhs);
		} else if (to->kind == TY_INT && to->size < 8) {
			fprintf (cg->out, "(hc_i64)(%s)", scalar_ctype (to));
			emit_val (cg, n->lhs);
		} else {
			emit_val (cg, n->lhs);
		}
		break;
	}
	case ND_ADD:
	case ND_SUB: {
		Type *lt = n->lhs->ty, *rt = n->rhs->ty;
		bool lp = is_ptr (lt);
		bool rp = is_ptr (rt);
		if (lp && rp && n->kind == ND_SUB) {
			fprintf (cg->out, "((");
			emit_val (cg, n->lhs);
			fprintf (cg->out, " - ");
			emit_val (cg, n->rhs);
			fprintf (cg->out, ") / %d)", elem_size (lt));
			break;
		}
		if (lp) {
			fprintf (cg->out, "(");
			emit_val (cg, n->lhs);
			fprintf (cg->out, " %s ", binop (n->kind));
			emit_val (cg, n->rhs);
			fprintf (cg->out, " * %d)", elem_size (lt));
			break;
		}
		emit_binary (cg, n);
		break;
	}
	case ND_MUL:
	case ND_DIV:
	case ND_MOD:
	case ND_SHR: {
		bool unsig = n->ty->kind == TY_INT && n->ty->is_unsigned;
		if (n->ty->kind != TY_F64 && unsig && n->kind != ND_MUL) {
			emit_unsigned_binary (cg, n);
		} else {
			emit_binary (cg, n);
		}
		break;
	}
	case ND_AND:
	case ND_OR:
	case ND_XOR:
	case ND_SHL:
		emit_binary (cg, n);
		break;
	case ND_POW:
		fprintf (cg->out, "__hc_pow(");
		emit_val (cg, n->lhs);
		fprintf (cg->out, ", ");
		emit_val (cg, n->rhs);
		fprintf (cg->out, ")");
		break;
	case ND_EQ:
	case ND_NE:
	case ND_LT:
	case ND_LE:
	case ND_LOGAND:
	case ND_LOGOR:
	case ND_LOGXOR:
	case ND_NOT:
		fprintf (cg->out, "(hc_i64)");
		emit_truth (cg, n);
		break;
	case ND_BITNOT:
		fprintf (cg->out, "~");
		emit_val (cg, n->lhs);
		break;
	case ND_NEG:
		fprintf (cg->out, "-");
		emit_val (cg, n->lhs);
		break;
	case ND_COMMA:
		emit_binary (cg, n);
		break;
	case ND_CALL:
		emit_call (cg, n, true);
		break;
	case ND_NOP:
		fprintf (cg->out, "0");
		break;
	default:
		aholyc_i_error (cg->cc, "C backend: unexpected node kind %d in expression", n->kind);
	}
}

static void emit_addr(CGen *cg, Node *n) {
	switch (n->kind) {
	case ND_VAR:
		if (is_agg (n->var->ty)) {
			fprintf (cg->out, "(hc_i64)(intptr_t)%s", objname (cg, n->var));
		} else {
			fprintf (cg->out, "(hc_i64)(intptr_t)&%s", objname (cg, n->var));
		}
		break;
	case ND_DEREF:
		emit_val (cg, n->lhs);
		break;
	case ND_MEMBER:
		if (n->member_ref->offset) {
			fprintf (cg->out, "(");
			emit_addr (cg, n->lhs);
			fprintf (cg->out, " + %d)", n->member_ref->offset);
		} else {
			emit_addr (cg, n->lhs);
		}
		break;
	default:
		aholyc_i_error (cg->cc, "C backend: not an lvalue (node kind %d)", n->kind);
	}
}

static void ind_(CGen *cg, int n) {
	while (n-- > 0) {
		fputc ('\t', cg->out);
	}
}

static void emit_inner(CGen *cg, Node *n, int ind) {
	if (n->kind == ND_BLOCK) {
		for (Node *s = n->body; s; s = s->next) {
			emit_stmt (cg, s, ind);
		}
	} else {
		emit_stmt (cg, n, ind);
	}
}

static void emit_body(CGen *cg, Node *n, int ind) {
	fprintf (cg->out, "{\n");
	emit_inner (cg, n, ind + 1);
	ind_ (cg, ind);
	fprintf (cg->out, "}\n");
}

static void emit_discarded(CGen *cg, Node *n) {
	if (n->kind == ND_CALL) {
		emit_call (cg, n, false);
	} else {
		emit_val (cg, n);
	}
}

static void emit_stmt(CGen *cg, Node *n, int ind) {
	switch (n->kind) {
	case ND_NOP:
		break;
	case ND_EXPR_STMT:
		ind_ (cg, ind);
		emit_discarded (cg, n->lhs);
		fprintf (cg->out, ";\n");
		break;
	case ND_BLOCK:
		emit_inner (cg, n, ind);
		break;
	case ND_IF:
		ind_ (cg, ind);
		fprintf (cg->out, "if (");
		emit_truth (cg, n->cond);
		fprintf (cg->out, ") ");
		emit_body (cg, n->then, ind);
		if (n->els) {
			ind_ (cg, ind);
			fprintf (cg->out, "else ");
			emit_body (cg, n->els, ind);
		}
		break;
	case ND_WHILE:
		ind_ (cg, ind);
		fprintf (cg->out, "while (");
		emit_truth (cg, n->cond);
		fprintf (cg->out, ") ");
		emit_body (cg, n->then, ind);
		break;
	case ND_DOWHILE:
		ind_ (cg, ind);
		fprintf (cg->out, "do ");
		emit_body (cg, n->then, ind);
		ind_ (cg, ind);
		fprintf (cg->out, "while (");
		emit_truth (cg, n->cond);
		fprintf (cg->out, ");\n");
		break;
	case ND_FOR:
		if (n->init) {
			emit_inner (cg, n->init, ind);
		}
		ind_ (cg, ind);
		fprintf (cg->out, "for (;;) {\n");
		if (n->cond) {
			ind_ (cg, ind + 1);
			fprintf (cg->out, "if (!");
			emit_truth (cg, n->cond);
			fprintf (cg->out, ") break;\n");
		}
		emit_inner (cg, n->then, ind + 1);
		if (n->inc) {
			emit_inner (cg, n->inc, ind + 1);
		}
		ind_ (cg, ind);
		fprintf (cg->out, "}\n");
		break;
	case ND_RETURN:
		for (int i = 0; i < cg->try_depth; i++) {
			ind_ (cg, ind);
			fprintf (cg->out, "__hc_try_pop();\n");
		}
		ind_ (cg, ind);
		if (n->lhs) {
			fprintf (cg->out, "return ");
			emit_val (cg, n->lhs);
			fprintf (cg->out, ";\n");
		} else {
			fprintf (cg->out, "%s\n", cg->ret->kind == TY_VOID? "return;": "return 0;");
		}
		break;
	case ND_GOTO:
		ind_ (cg, ind);
		fprintf (cg->out, "goto %s;\n", labname (cg, n->label));
		break;
	case ND_LABEL:
		ind_ (cg, ind);
		fprintf (cg->out, "%s: ;\n", labname (cg, n->label));
		break;
	case ND_TRY:
		ind_ (cg, ind);
		fprintf (cg->out, "{ void *hjb = __hc_try_push();\n");
		ind_ (cg, ind);
		fprintf (cg->out, "if (!_setjmp(*(jmp_buf *)hjb)) {\n");
		cg->try_depth++;
		emit_inner (cg, n->then, ind + 1);
		cg->try_depth--;
		ind_ (cg, ind + 1);
		fprintf (cg->out, "__hc_try_pop();\n");
		ind_ (cg, ind);
		fprintf (cg->out, "} else {\n");
		emit_inner (cg, n->els, ind + 1);
		ind_ (cg, ind + 1);
		fprintf (cg->out, "if (!__hc_fs()->catch_except) throw(__hc_fs()->except_ch);\n");
		ind_ (cg, ind);
		fprintf (cg->out, "} }\n");
		break;
	default:
		ind_ (cg, ind);
		emit_discarded (cg, n);
		fprintf (cg->out, ";\n");
		break;
	}
}

static void emit_func_sig(CGen *cg, Obj *fn) {
	Type *ret = fn->ty->base;
	const char *rc = ret->kind == TY_VOID? "void": value_ctype (ret);
	bool exported = fn->is_public ||
		(cg->prog && fn == cg->prog->startup && !cg->ctor_mode);
	fprintf (cg->out, "%s%s%s%s %s(", exported?
		(fn->hints & HINT_INLINE? "extern ": ""): "static ",
		fn->hints & HINT_INLINE? "inline ": "",
		fn->hints & HINT_NOINLINE? "__attribute__((noinline)) ": "", rc, objname (cg, fn));
	bool first = true;
	for (Obj *p = fn->params; p; p = p->next) {
		fprintf (cg->out, "%s%s %s", first? "": ", ", value_ctype (p->ty), objname (cg, p));
		first = false;
	}
	if (first) {
		fprintf (cg->out, "void");
	}
	fprintf (cg->out, ")");
}

static void emit_func(CGen *cg, Obj *fn) {
	cg->ret = fn->ty->base;
	emit_func_sig (cg, fn);
	fprintf (cg->out, " {\n");
	for (Obj *v = fn->locals; v; v = v->next) {
		fprintf (cg->out, "\t");
		if (v->align) {
			fprintf (cg->out, "_Alignas(%d) ", v->align < v->ty->align? v->ty->align: v->align);
		}
		if (is_agg (v->ty)) {
			fprintf (cg->out, "hc_i64 %s[%d] = {0};\n", objname (cg, v),
				(v->ty->size + 7) / 8? (v->ty->size + 7) / 8: 1);
		} else if (v->ty->kind == TY_F64) {
			fprintf (cg->out, "hc_f64 %s = 0;\n", objname (cg, v));
		} else if (v->ty->bits && !signed_i1 (v->ty) && !v->address_taken) {
			fprintf (cg->out, "%s _BitInt(%d) %s = 0;\n",
				v->ty->is_unsigned? "unsigned": "signed", v->ty->bits,
				objname (cg, v));
		} else {
			fprintf (cg->out, "%s %s = 0;\n", scalar_ctype (v->ty), objname (cg, v));
		}
	}
	cg->try_depth = 0;
	emit_inner (cg, fn->body, 1);
	if (cg->ret->kind != TY_VOID) {
		fprintf (cg->out, "\treturn 0;\n");
	}
	fprintf (cg->out, "}\n\n");
}

/* only_user skips the runtime API already embedded in the translation unit. */
static void emit_extern_decls(CGen *cg, bool only_user) {
	Program *prog = cg->prog;
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (!f->is_extern || (only_user && f->from_prelude)) {
			continue;
		}
		Type *ret = f->ty->base;
		fprintf (cg->out, "extern %s%s%s %s(",
			f->hints & HINT_INLINE? "inline ": "",
			f->hints & HINT_NOINLINE? "__attribute__((noinline)) ": "",
			ret->kind == TY_VOID? "void": extern_ctype (ret), f->name);
		int np = 0;
		for (Obj *p = f->params; p; p = p->next, np++) {
			fprintf (cg->out, "%s%s", np? ", ": "", extern_ctype (p->ty));
		}
		fprintf (cg->out, "%s);\n", np? "": "void");
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (!g->is_extern || !strcmp (g->name, "Fs") ||
		    (only_user && g->from_prelude)) {
			continue;
		}
		if (is_agg (g->ty)) {
			fprintf (cg->out, "extern hc_i64 %s[];\n", g->name);
		} else {
			fprintf (cg->out, "extern %s %s;\n", scalar_ctype (g->ty), g->name);
		}
	}
}

/* -c mode: the runtime is linked separately, so declare it instead */
static void emit_obj_preamble(CGen *cg) {
	fprintf (cg->out,
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
	emit_extern_decls (cg, false);
}

static void c_emit(Aholyc *cc, Program *prog, FILE *out,
		bool object_mode, bool ctor_mode) {
	CGen gen = {
		.cc = cc, .prog = prog, .out = out,
		.ctor_mode = ctor_mode,
	};
	CGen *cg = &gen;
	fprintf (cg->out, "/* generated by aholyc (HolyC -> C) */\n");
	if (object_mode) {
		emit_obj_preamble (cg);
	} else {
		fprintf (cg->out, "#define HC_API static\n");
		fputs (aholyc_i_rt_c_src, cg->out);
		emit_extern_decls (cg, true);
	}
	fprintf (cg->out, "\n/* ---- program ---- */\n");
	fprintf (cg->out, "static hc_i64 hc_f2b(hc_f64 d){hc_i64 v;memcpy(&v,&d,8);return v;}\n");
	for (StrLit *s = prog->strings; s; s = s->next) {
		fprintf (cg->out, "static unsigned char hcs%d[] = {", s->id);
		for (int i = 0; i < s->len; i++) {
			fprintf (cg->out, "%d,", (unsigned char)s->data[i]);
		}
		fprintf (cg->out, "0};\n");
	}
	for (Obj *g = prog->globals; g; g = g->next) {
		if (g->is_extern) {
			continue; /* declared in the preamble / defined by the runtime */
		}
		const char *sto = g->is_public? "": "static ";
		if (is_agg (g->ty)) {
			int words = (g->ty->size + 7) / 8;
			fprintf (cg->out, "%shc_i64 %s[%d];\n", sto, objname (cg, g), words? words: 1);
		} else if (g->ty->kind == TY_F64) {
			fprintf (cg->out, "%shc_f64 %s;\n", sto, objname (cg, g));
		} else {
			fprintf (cg->out, "%s%s %s;\n", sto, scalar_ctype (g->ty), objname (cg, g));
		}
	}
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func_sig (cg, f);
		fprintf (cg->out, ";\n");
	}
	fprintf (cg->out, "\n");
	for (Obj *f = prog->funcs; f; f = f->next) {
		if (f->is_extern || !f->body) {
			continue;
		}
		emit_func (cg, f);
	}
	/* A -c module constructor registers the hidden-pair startup function. */
	emit_func (cg, prog->startup);
	if (cg->ctor_mode) {
		fprintf (cg->out, "__attribute__((constructor)) static void __hc_ctor(void) {\n"
			"\t__hc_register_start(__hc_ctor_body);\n"
			"}\n");
	}
}

static int c_compile(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt, bool object) {
	const char *inputs[] = { artifact };
	return aholyc_i_run_cc (cc, NULL, opt, outpath, inputs, 1, object, !object);
}

static int c_build_obj(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt) {
	return c_compile (cc, artifact, outpath, opt, true);
}

static int c_build(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt) {
	return c_compile (cc, artifact, outpath, opt, false);
}

const Backend aholyc_i_backend_c = {
	.name = "c",
	.ext = ".c",
	.descr = "portable C99 (built with the system C compiler)",
	.emit = c_emit,
	.build = c_build,
	.build_obj = c_build_obj,
};
