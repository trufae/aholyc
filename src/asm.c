/* HolyC asm{} capture and native-backend emission.
 *
 * This is deliberately an assembler adapter, not an assembler.  It keeps the
 * instruction stream opaque so the compiler selected by the C/LLVM backend
 * owns target validation and encoding.  Only syntax that is specific to
 * HolyC is rewritten here: public (::) and block-local (@@) labels, $$, data
 * directives, and the size-suffixed Intel mnemonics used by TempleOS sources.
 */
#include "aholyc.h"

typedef struct {
	const char *from, *to, *mem_size;
	int mem_operand;
} AsmRename;

typedef struct {
	char suffix;
	const char *name;
} AsmWidth;

typedef struct {
	const char *name, *mem_size;
} AsmSize;

typedef struct {
	bool intel_dialect;
	const char *local_label_prefix, *align_nop_fill;
	const char *frame_pointer, *c_operand_modifier;
	const char *c_clobbers, *llvm_constraints;
	const AsmRename *renames;
	const AsmWidth *widths;
	const AsmSize *operand_sizes;
	const char *const *sized_mnemonics;
	const char *const *prefixes;
} AsmTarget;

typedef struct {
	char name[32];
	const char *mem_size;
	int mem_operand; /* 0: every memory operand, N: only operand N, -1: none */
	int data_width;
	bool align_fill, ignore;
} AsmMnemonic;

#include "asm/x64.inc.c"
#include "asm/arm64.inc.c"
#include "asm/riscv.inc.c"
#include "asm/mips.inc.c"
#include "asm/s390.inc.c"

static const AsmTarget generic_target = {
#ifdef __APPLE__
	.local_label_prefix = "Lahc_asm",
#else
	.local_label_prefix = ".Lahc_asm",
#endif
	.c_clobbers = "\"memory\"",
	.llvm_constraints = "~{memory}",
};

static const AsmTarget *asm_target(void) {
	const AsmTarget *target = &generic_target;
#if defined(__s390__) || defined(__s390x__)
	target = &target_s390;
#elif defined(__x86_64__) || defined(_M_X64)
	target = &target_x64;
#elif defined(__aarch64__) || defined(__arm64__) || defined(_M_ARM64)
	target = &target_arm64;
#elif defined(__riscv)
	target = &target_riscv;
#elif defined(__mips__) || defined(__mips) || defined(_MIPS_ARCH)
	target = &target_mips;
#endif
	return target;
}

typedef struct {
	Aholyc *cc;
	StrBuf *out;
	const AsmTarget *target;
	AholyAsm *block;
	int id;
	bool capture_operands, any, prev_word;
} AsmWriter;

static bool name_eq(const char *a, const char *b) {
	while (*a && *b) {
		int ac = *a >= 'A' && *a <= 'Z'? *a + ('a' - 'A'): *a;
		int bc = *b >= 'A' && *b <= 'Z'? *b + ('a' - 'A'): *b;
		if (ac != bc) {
			return false;
		}
		a++;
		b++;
	}
	return *a == *b;
}

static bool tok_is(Token *t, const char *s) {
	return t && (t->kind == TK_ID || t->kind == TK_KEYWORD ||
		t->kind == TK_TYPE || t->kind == TK_PUNCT) && t->str &&
		!strcmp (t->str, s);
}

static bool tok_word(Token *t) {
	return t && t->kind != TK_PUNCT && t->kind != TK_EOF;
}

static bool tok_label_name(Token *t) {
	return tok_word (t) && (t->kind == TK_ID || t->kind == TK_KEYWORD ||
		t->kind == TK_TYPE || t->kind == TK_NUM);
}

static void aw_before(AsmWriter *w, bool word, bool spaced) {
	if (w->any && (spaced || (word && w->prev_word)) &&
		w->out->len && w->out->data[w->out->len - 1] != ' ') {
		sb_putc (w->out, ' ');
	}
	w->any = true;
	w->prev_word = word;
}

static void aw_text(AsmWriter *w, const char *s, bool word, bool spaced) {
	aw_before (w, word, spaced);
	sb_puts (w->out, s);
}

static void aw_asm_string(AsmWriter *w, Token *t, bool spaced) {
	aw_before (w, true, spaced);
	sb_putc (w->out, '"');
	for (int i = 0; i < t->len; i++) {
		unsigned char c = (unsigned char)t->str[i];
		switch (c) {
		case '\\': sb_puts (w->out, "\\\\"); break;
		case '"': sb_puts (w->out, "\\\""); break;
		case '\n': sb_puts (w->out, "\\n"); break;
		case '\r': sb_puts (w->out, "\\r"); break;
		case '\t': sb_puts (w->out, "\\t"); break;
		default:
			if (c >= 32 && c < 127) {
				sb_putc (w->out, c);
			} else {
				sb_printf (w->out, "\\%03o", c);
			}
			break;
		}
	}
	sb_putc (w->out, '"');
}

static void aw_token(AsmWriter *w, Token *t, bool force_space) {
	bool spaced = force_space || t->has_space;
	switch (t->kind) {
	case TK_NUM:
	case TK_CHR:
		aw_before (w, true, spaced);
		sb_printf (w->out, "%lld", (long long)t->ival);
		break;
	case TK_FNUM:
		aw_before (w, true, spaced);
		sb_printf (w->out, "%.17g", t->fval);
		break;
	case TK_STR:
		aw_asm_string (w, t, spaced);
		break;
	default:
		if (tok_is (t, "$$")) {
			aw_text (w, ".", false, spaced);
		} else {
			aw_text (w, t->str? t->str: "", tok_word (t), spaced);
		}
		break;
	}
}

static bool local_label_at(Token *t, Token *end) {
	return t && t != end && tok_is (t, "@") && t->next && t->next != end &&
		tok_is (t->next, "@") && t->next->next && t->next->next != end &&
		tok_label_name (t->next->next);
}

static void aw_local_label(AsmWriter *w, Token *t, bool force_space) {
	Token *name = t->next->next;
	aw_before (w, true, force_space || t->has_space);
	if (name->kind == TK_NUM) {
		sb_printf (w->out, "%s%d_%lld", w->target->local_label_prefix, w->id,
			(long long)name->ival);
	} else {
		sb_printf (w->out, "%s%d_%s", w->target->local_label_prefix, w->id,
			name->str);
	}
}

static Token *local_operand_end(AsmWriter *w, Token *t, Token *end) {
	if (!w->target->frame_pointer || !tok_is (t, "&") || !t->next ||
		t->next == end || t->next->kind != TK_ID || !t->next->next ||
		t->next->next == end || !tok_is (t->next->next, "[")) {
		return NULL;
	}
	Token *frame = t->next->next->next;
	Token *close = frame? frame->next: NULL;
	if (!frame || frame == end || !frame->str || close == end ||
		!name_eq (frame->str, w->target->frame_pointer) ||
		!tok_is (close, "]")) {
		return NULL;
	}
	return close->next;
}

static AholyAsmOperand *block_operand(AsmWriter *w, Token *name,
		bool require_local) {
	for (AholyAsmOperand *op = w->block->operands; op; op = op->next) {
		if (!strcmp (op->name, name->str)) {
			op->require_local |= require_local;
			return op;
		}
	}
	AholyAsmOperand *op = xcalloc (w->cc, 1, sizeof(*op));
	op->tok = name;
	op->name = name->str;
	op->marker = w->block->nmarkers++;
	op->index = -1;
	op->require_local = require_local;
	if (w->block->operand_tail) {
		w->block->operand_tail->next = op;
	} else {
		w->block->operands = op;
	}
	w->block->operand_tail = op;
	return op;
}

static void aw_operand_marker(AsmWriter *w, Token *t, bool force_space,
		bool brackets, bool require_local) {
	AholyAsmOperand *op = block_operand (w, t->next, require_local);
	aw_before (w, true, force_space || t->has_space);
	if (brackets) {
		sb_putc (w->out, '[');
	}
	sb_printf (w->out, "\x1f%d\x1f", op->marker);
	if (brackets) {
		sb_putc (w->out, ']');
	}
}

static void render_range(AsmWriter *w, Token *t, Token *end,
		bool force_first_space) {
	bool first = true;
	while (t && t != end) {
		Token *after = local_operand_end (w, t, end);
		if (after) {
			aw_operand_marker (w, t, first && force_first_space, true, true);
			t = after;
			first = false;
			continue;
		}
		if (local_label_at (t, end)) {
			aw_local_label (w, t, first && force_first_space);
			t = t->next->next->next;
			first = false;
			continue;
		}
		/* In a function, &local becomes a named address operand. If name is
		 * not a local, the emitter retains TempleOS's symbol spelling. */
		if (tok_is (t, "&") && t->next != end && tok_word (t->next) &&
			!t->next->has_space) {
			if (w->capture_operands && t->next->kind == TK_ID) {
				aw_operand_marker (w, t, first && force_first_space, false, false);
				t = t->next->next;
				first = false;
				continue;
			}
			/* TempleOS's unary & marks a symbol for assembler resolution. */
			t = t->next;
			continue;
		}
		aw_token (w, t, first && force_first_space);
		first = false;
		t = t->next;
	}
}

static bool name_in(const char *name, const char *const *names) {
	if (!names) {
		return false;
	}
	for (int i = 0; names[i]; i++) {
		if (name_eq (name, names[i])) {
			return true;
		}
	}
	return false;
}

static const char *width_name(const AsmTarget *target, int c) {
	for (const AsmWidth *w = target->widths; w && w->suffix; w++) {
		if (c == w->suffix || c == w->suffix + ('A' - 'a')) {
			return w->name;
		}
	}
	return NULL;
}

static void mnemonic_init(const AsmTarget *target, AsmMnemonic *m,
		const char *name) {
	memset (m, 0, sizeof(*m));
	snprintf (m->name, sizeof(m->name), "%s", name);
	m->mem_operand = -1;

	static const struct {
		const char *from, *to;
		int data_width;
		bool align_fill, ignore;
	} common[] = {
		{ "IMPORT", ".extern", 0, false, false },
		{ "DU8", ".byte", 1, false, false },
		{ "DU16", ".short", 2, false, false },
		{ "DU32", ".long", 4, false, false },
		{ "DU64", ".quad", 8, false, false },
		{ "ALIGN", ".balign", 0, true, false },
		{ "ORG", ".org", 0, false, false },
		{ "BINFILE", ".incbin", 0, false, false },
		{ "LIST", "", 0, false, true },
		{ "NOLIST", "", 0, false, true },
		{ NULL, NULL, 0, false, false }
	};
	for (int i = 0; common[i].from; i++) {
		if (name_eq (name, common[i].from)) {
			snprintf (m->name, sizeof(m->name), "%s", common[i].to);
			m->data_width = common[i].data_width;
			m->align_fill = common[i].align_fill;
			m->ignore = common[i].ignore;
			return;
		}
	}
	for (const AsmRename *r = target->renames; r && r->from; r++) {
		if (name_eq (name, r->from)) {
			snprintf (m->name, sizeof(m->name), "%s", r->to);
			m->mem_size = r->mem_size;
			m->mem_operand = r->mem_operand;
			return;
		}
	}
	size_t n = strlen (name);
	const char *width = n > 1? width_name (target, name[n - 1]): NULL;
	if (width) {
		char base[32];
		if (n < sizeof(base)) {
			memcpy (base, name, n - 1);
			base[n - 1] = 0;
			if (name_in (base, target->sized_mnemonics)) {
				for (size_t i = 0; i < n - 1; i++) {
					m->name[i] = base[i] >= 'A' && base[i] <= 'Z'?
						base[i] + ('a' - 'A'): base[i];
				}
				m->name[n - 1] = 0;
				if (!name_eq (base, "lea")) {
					m->mem_size = width;
					m->mem_operand = 0;
				}
			}
		}
	}
}

static bool instruction_prefix(const AsmTarget *target, Token *t) {
	return t && t->str && name_in (t->str, target->prefixes);
}

static bool range_has(Token *t, Token *end, const char *s) {
	for (; t && t != end; t = t->next) {
		if (tok_is (t, s)) {
			return true;
		}
	}
	return false;
}

static const char *operand_size(const AsmTarget *target, Token *t) {
	if (!t || !t->str) {
		return NULL;
	}
	for (const AsmSize *s = target->operand_sizes; s && s->name; s++) {
		if (name_eq (t->str, s->name)) {
			return s->mem_size;
		}
	}
	return NULL;
}

static void render_operand(AsmWriter *w, Token *start, Token *end,
		AsmMnemonic *mn, int operand) {
	if (start == end) {
		return;
	}
	if (mn->align_fill && operand == 2 && start->next == end &&
		w->target->align_nop_fill && start->kind == TK_ID &&
		name_eq (start->str, "OC_NOP")) {
		aw_text (w, w->target->align_nop_fill, true, true);
		return;
	}
	const char *explicit_size = operand_size (w->target, start);
	if (explicit_size && start->next != end &&
		range_has (start->next, end, "[")) {
		start = start->next;
	} else {
		explicit_size = NULL;
	}
	const char *mem_size = explicit_size? explicit_size: mn->mem_size;
	bool qualify = mem_size && range_has (start, end, "[") &&
		(explicit_size || mn->mem_operand == 0 || mn->mem_operand == operand);
	if (qualify) {
		aw_text (w, mem_size, true, true);
	}
	render_range (w, start, end, qualify);
}

static Token *skip_label(Token *p, Token *end, bool *global) {
	*global = false;
	if (!p || p == end) {
		return p;
	}
	Token *colon = NULL;
	if (local_label_at (p, end)) {
		colon = p->next->next->next;
	} else if (tok_label_name (p) && p->next != end) {
		colon = p->next;
	}
	if (!colon || colon == end || !tok_is (colon, ":")) {
		return p;
	}
	Token *after = colon->next;
	if (p->kind == TK_ID && after != end && tok_is (after, ":")) {
		*global = true;
		after = after->next;
	}
	return after;
}

static Token *top_level_comma(Token *start, Token *end) {
	int square = 0, paren = 0, brace = 0;
	for (Token *t = start; t && t != end; t = t->next) {
		if (tok_is (t, "[")) square++;
		else if (tok_is (t, "]") && square) square--;
		else if (tok_is (t, "(")) paren++;
		else if (tok_is (t, ")") && paren) paren--;
		else if (tok_is (t, "{")) brace++;
		else if (tok_is (t, "}") && brace) brace--;
		else if (tok_is (t, ",") && !square && !paren && !brace) return t;
	}
	return end;
}

static Token *data_dup(Token *start, Token *end, Token **value,
		Token **value_end) {
	int square = 0, paren = 0, brace = 0;
	for (Token *t = start; t && t != end; t = t->next) {
		if (tok_is (t, "[") ) square++;
		else if (tok_is (t, "]") && square) square--;
		else if (tok_is (t, "{")) brace++;
		else if (tok_is (t, "}") && brace) brace--;
		else if (!square && !paren && !brace && tok_is (t, "DUP") &&
			t->next != end && tok_is (t->next, "(")) {
			int depth = 1;
			Token *close = t->next->next;
			for (; close && close != end; close = close->next) {
				if (tok_is (close, "(")) depth++;
				else if (tok_is (close, ")") && --depth == 0) break;
			}
			if (!close || close == end || close->next != end || t == start) {
				return NULL;
			}
			*value = t->next->next;
			*value_end = close;
			return t;
		} else if (tok_is (t, "(")) {
			paren++;
		} else if (tok_is (t, ")") && paren) {
			paren--;
		}
	}
	return NULL;
}

static AsmWriter line_writer(AsmWriter *base) {
	AsmWriter w = {
		.cc = base->cc, .out = base->out, .target = base->target,
		.block = base->block, .id = base->id,
		.capture_operands = base->capture_operands,
	};
	return w;
}

static void render_data(AsmWriter *base, Token *start, Token *end,
		const AsmMnemonic *mn) {
	if (base->any) {
		sb_putc (base->out, '\n');
	}
	for (Token *item = start; item && item != end;) {
		Token *item_end = top_level_comma (item, end);
		if (item != item_end) {
			AsmWriter w = line_writer (base);
			if (item->kind == TK_STR && item->next == item_end) {
				aw_text (&w, ".ascii", true, false);
				render_range (&w, item, item_end, true);
			} else {
				Token *value = NULL, *value_end = NULL;
				Token *dup = data_dup (item, item_end, &value, &value_end);
				if (dup) {
					aw_text (&w, ".fill", true, false);
					render_range (&w, item, dup, true);
					aw_text (&w, ",", false, false);
					char width[8];
					snprintf (width, sizeof(width), "%d", mn->data_width);
					aw_text (&w, width, true, true);
					aw_text (&w, ",", false, false);
					render_range (&w, value, value_end, true);
				} else {
					aw_text (&w, mn->name, true, false);
					render_range (&w, item, item_end, true);
				}
			}
			sb_putc (base->out, '\n');
		}
		item = item_end == end? end: item_end->next;
	}
}

static void render_line(Aholyc *cc, StrBuf *out, const AsmTarget *target,
		AholyAsm *block, Token *start, Token *end, int id,
		bool capture_operands) {
	if (!start || start == end) {
		return;
	}
	bool global;
	Token *body = skip_label (start, end, &global);
	if (global) {
		sb_printf (out, ".globl %s\n", start->str);
	}

	AsmWriter w = {
		.cc = cc, .out = out, .target = target, .block = block, .id = id,
		.capture_operands = capture_operands,
	};
	if (body != start) {
		if (global) {
			aw_text (&w, start->str, true, false);
			aw_text (&w, ":", false, false);
		} else {
			render_range (&w, start, body, false);
		}
		if (body == end) {
			sb_putc (out, '\n');
			return;
		}
	}

	Token *op = body;
	while (op != end && instruction_prefix (target, op) && op->next != end) {
		AsmMnemonic prefix;
		mnemonic_init (target, &prefix, op->str);
		aw_text (&w, prefix.name, true, op->has_space);
		op = op->next;
	}
	if (op == end || !tok_word (op)) {
		render_range (&w, op, end, body != start);
		sb_putc (out, '\n');
		return;
	}

	AsmMnemonic mn;
	mnemonic_init (target, &mn, op->str);
	if (mn.ignore) {
		if (w.any) {
			sb_putc (out, '\n');
		}
		return;
	}
	if (mn.data_width) {
		render_data (&w, op->next, end, &mn);
		return;
	}
	aw_text (&w, mn.name, true, op->has_space || body != start);
	Token *operand = op->next;
	Token *q = operand;
	int square = 0, paren = 0, brace = 0, nth = 1;
	while (q && q != end) {
		if (tok_is (q, "[") ) square++;
		else if (tok_is (q, "]") && square > 0) square--;
		else if (tok_is (q, "(")) paren++;
		else if (tok_is (q, ")") && paren > 0) paren--;
		else if (tok_is (q, "{")) brace++;
		else if (tok_is (q, "}") && brace > 0) brace--;
		if (tok_is (q, ",") && square == 0 && paren == 0 && brace == 0) {
			render_operand (&w, operand, q, &mn, nth++);
			aw_text (&w, ",", false, q->has_space);
			operand = q->next;
		}
		q = q->next;
	}
	render_operand (&w, operand, end, &mn, nth);
	sb_putc (out, '\n');
}

static bool same_file(Token *a, Token *b) {
	if (a->file == b->file) {
		return true;
	}
	return a->file && b->file && !strcmp (a->file, b->file);
}

static Token *semicolon_directive(Token *start, Token *end) {
	bool global;
	Token *op = skip_label (start, end, &global);
	(void)global;
	return op && op != end && (tok_is (op, "IMPORT") ||
		tok_is (op, "DU8") || tok_is (op, "DU16") ||
		tok_is (op, "DU32") || tok_is (op, "DU64") ||
		tok_is (op, "BINFILE"))? op: NULL;
}

static bool needs_semicolon(Token *start, Token *end) {
	return semicolon_directive (start, end) != NULL;
}

static char *render_body(Aholyc *cc, AholyAsm *block, Token *start,
		Token *end, int id, bool capture_operands) {
	StrBuf out;
	sb_init (&out, cc);
	const AsmTarget *target = asm_target ();
	Token *line = start;
	Token *prev = NULL;
	for (Token *t = start; t && t != end; t = t->next) {
		bool newline = prev && (t->line != prev->line || !same_file (t, prev) ||
			t->at_bol);
		if (newline && !needs_semicolon (line, t)) {
			render_line (cc, &out, target, block, line, t, id,
				capture_operands);
			line = t;
		}
		if (tok_is (t, ";")) {
			render_line (cc, &out, target, block, line, t, id,
				capture_operands);
			line = t->next;
			prev = NULL;
			continue;
		}
		prev = t;
	}
	if (line && line != end) {
		Token *directive = semicolon_directive (line, end);
		if (directive) {
			error_tok (cc, directive, "%s requires a terminating ';'",
				directive->str);
		}
		render_line (cc, &out, target, block, line, end, id,
			capture_operands);
	}
	return sb_take (&out);
}

AholyAsm *asm_parse(Aholyc *cc, Token **rest, int id, bool function_scope) {
	Token *kw = *rest;
	if (!tok_is (kw, "asm")) {
		error_tok (cc, kw, "internal error: expected asm statement");
	}
	Token *open = kw->next;
	if (!tok_is (open, "{")) {
		error_tok (cc, open, "expected '{' after 'asm'");
	}
	int depth = 1;
	Token *end = open->next;
	while (end && end->kind != TK_EOF) {
		if (tok_is (end, "{")) {
			depth++;
		} else if (tok_is (end, "}") && --depth == 0) {
			break;
		}
		end = end->next;
	}
	if (!end || end->kind == TK_EOF) {
		error_tok (cc, open, "unterminated asm block");
	}
	AholyAsm *a = xcalloc (cc, 1, sizeof(*a));
	a->tok = kw;
	a->id = id;
	a->text = render_body (cc, a, open->next, end, id, function_scope);
	*rest = end->next;
	if (tok_is (*rest, ";")) {
		*rest = (*rest)->next;
	}
	return a;
}

static void put_indent(StrBuf *out, int n) {
	while (n-- > 0) {
		sb_putc (out, '\t');
	}
}

static bool operand_marker(const char *s, size_t n, size_t *at, int *index) {
	size_t i = *at;
	if ((unsigned char)s[i] != 0x1f || i + 2 >= n) {
		return false;
	}
	int v = 0;
	size_t p = i + 1;
	if (s[p] < '0' || s[p] > '9') {
		return false;
	}
	while (p < n && s[p] >= '0' && s[p] <= '9') {
		v = v * 10 + s[p++] - '0';
	}
	if (p >= n || (unsigned char)s[p] != 0x1f) {
		return false;
	}
	*at = p;
	*index = v;
	return true;
}

static AholyAsmOperand *operand_by_marker(AholyAsm *a, int marker) {
	for (AholyAsmOperand *op = a? a->operands: NULL; op; op = op->next) {
		if (op->marker == marker) {
			return op;
		}
	}
	return NULL;
}

static void c_literal(StrBuf *out, const AsmTarget *target, AholyAsm *a,
		const char *s, size_t n, bool template_escapes) {
	sb_putc (out, '"');
	for (size_t i = 0; i < n; i++) {
		unsigned char c = (unsigned char)s[i];
		int marker;
		if (template_escapes && operand_marker (s, n, &i, &marker)) {
			AholyAsmOperand *op = operand_by_marker (a, marker);
			if (op && op->var) {
				sb_putc (out, '%');
				if (target->c_operand_modifier) {
					sb_puts (out, target->c_operand_modifier);
				}
				sb_printf (out, "[ahc%d]", op->index);
			} else if (op) {
				sb_puts (out, op->name);
			}
		} else if (template_escapes && c == '%') {
			sb_puts (out, "%%");
		} else if (template_escapes && (c == '{' || c == '}' || c == '|')) {
			sb_putc (out, '%');
			sb_putc (out, c);
		} else if (c == '\\') {
			sb_puts (out, "\\\\");
		} else if (c == '"') {
			sb_puts (out, "\\\"");
		} else if (c == '\t') {
			sb_puts (out, "\\t");
		} else if (c >= 32 && c < 127) {
			sb_putc (out, c);
		} else {
			sb_printf (out, "\\%03o", c);
		}
	}
	sb_puts (out, "\\n\"");
}

static void c_text_lines(StrBuf *out, const AsmTarget *target,
		AholyAsm *a, const char *text, int indent, bool template_escapes) {
	const char *p = text;
	while (*p) {
		const char *e = strchr (p, '\n');
		size_t n = e? (size_t)(e - p): strlen (p);
		put_indent (out, indent);
		c_literal (out, target, a, p, n, template_escapes);
		sb_putc (out, '\n');
		p = e? e + 1: p + n;
	}
}

static void c_wrapper_line(StrBuf *out, const AsmTarget *target,
		const char *line, int indent, bool template_escapes) {
	put_indent (out, indent);
	c_literal (out, target, NULL, line, strlen (line), template_escapes);
	sb_putc (out, '\n');
}

void asm_emit_c_module(Aholyc *cc, StrBuf *out, AholyAsm *a) {
	(void)cc;
	const AsmTarget *target = asm_target ();
	sb_puts (out, "__asm__(\n");
	c_wrapper_line (out, target, ".text", 1, false);
	if (target->intel_dialect) {
		c_wrapper_line (out, target, ".intel_syntax noprefix", 1, false);
	}
	c_text_lines (out, target, a, a->text, 1, false);
	if (target->intel_dialect) {
		c_wrapper_line (out, target, ".att_syntax prefix", 1, false);
	}
	c_wrapper_line (out, target, ".text", 1, false);
	sb_puts (out, ");\n\n");
}

void asm_emit_c_inline(Aholyc *cc, StrBuf *out, AholyAsm *a, int indent,
		void *ctx, AsmObjNameFn objname) {
	(void)cc;
	const AsmTarget *target = asm_target ();
	put_indent (out, indent);
	sb_puts (out, "__asm__ volatile (\n");
	if (target->intel_dialect) {
		c_wrapper_line (out, target, ".intel_syntax noprefix", indent + 1, true);
	}
	c_text_lines (out, target, a, a->text, indent + 1, true);
	if (target->intel_dialect) {
		c_wrapper_line (out, target, ".att_syntax prefix", indent + 1, true);
	}
	put_indent (out, indent + 1);
	sb_puts (out, ": : ");
	for (AholyAsmOperand *op = a->operands; op; op = op->next) {
		if (!op->var) {
			continue;
		}
		sb_printf (out, "%s[ahc%d] \"r\" (&%s)",
			op->index? ", ": "", op->index, objname (ctx, op->var));
	}
	sb_printf (out, " : %s);\n", target->c_clobbers);
}

static void llvm_escaped(StrBuf *out, AholyAsm *a, const char *s, size_t n,
		bool inline_asm) {
	sb_putc (out, '"');
	for (size_t i = 0; i < n; i++) {
		unsigned char c = (unsigned char)s[i];
		int marker;
		if (inline_asm && operand_marker (s, n, &i, &marker)) {
			AholyAsmOperand *op = operand_by_marker (a, marker);
			if (op && op->var) {
				sb_printf (out, "$%d", op->index);
			} else if (op) {
				sb_puts (out, op->name);
			}
		} else if (inline_asm && c == '$') {
			sb_puts (out, "$$");
		} else if (c == '"' || c == '\\' || c < 32 || c >= 127) {
			sb_printf (out, "\\%02X", c);
		} else {
			sb_putc (out, c);
		}
	}
	sb_putc (out, '"');
}

static void llvm_module_line(StrBuf *out, const char *line, size_t n) {
	sb_puts (out, "module asm ");
	llvm_escaped (out, NULL, line, n, false);
	sb_putc (out, '\n');
}

void asm_emit_llvm_module(Aholyc *cc, StrBuf *out, AholyAsm *a) {
	(void)cc;
	const AsmTarget *target = asm_target ();
	llvm_module_line (out, ".text", 5);
	if (target->intel_dialect) {
		llvm_module_line (out, ".intel_syntax noprefix", 22);
	}
	const char *p = a->text;
	while (*p) {
		const char *e = strchr (p, '\n');
		size_t n = e? (size_t)(e - p): strlen (p);
		llvm_module_line (out, p, n);
		p = e? e + 1: p + n;
	}
	if (target->intel_dialect) {
		llvm_module_line (out, ".att_syntax prefix", 18);
	}
	llvm_module_line (out, ".text", 5);
	sb_putc (out, '\n');
}

void asm_emit_llvm_inline(Aholyc *cc, StrBuf *out, AholyAsm *a,
		void *ctx, AsmObjNameFn objname) {
	(void)cc;
	const AsmTarget *target = asm_target ();
	sb_puts (out, "  call void asm sideeffect ");
	if (target->intel_dialect) {
		sb_puts (out, "inteldialect ");
	}
	llvm_escaped (out, a, a->text, strlen (a->text), true);
	sb_puts (out, ", \"");
	for (AholyAsmOperand *op = a->operands; op; op = op->next) {
		if (op->var) {
			sb_puts (out, "r,");
		}
	}
	sb_printf (out, "%s\"(", target->llvm_constraints);
	for (AholyAsmOperand *op = a->operands; op; op = op->next) {
		if (!op->var) {
			continue;
		}
		sb_printf (out, "%sptr %s", op->index? ", ": "", objname (ctx, op->var));
	}
	sb_puts (out, ")\n");
}

void asm_reject_js(Aholyc *cc, Program *prog) {
	if (prog->asm_tok) {
		error_tok (cc, prog->asm_tok,
			"asm statements are not supported by the js backend; use c or llvm");
	}
}
