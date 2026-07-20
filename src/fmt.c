/* aholyc fmt — HolyC source formatter (see doc/format.md).
 *
 * Self-contained: its own tiny scanner (the compiler's lexer drops
 * comments, a formatter must not), and whitespace-only transforms:
 * lines are re-indented, never re-worded. Before printing or writing
 * anything, the output is verified to be byte-identical to the input
 * with all whitespace removed — if that ever fails, the file is left
 * untouched. Unparseable input degrades gracefully: lines inside
 * unterminated strings or comments pass through verbatim.
 *
 * Options come from the environment, not new compiler flags:
 *   AHOLYC_FMT_INDENT  spaces per level (default 2)
 *   AHOLYC_FMT_BRACES  0 disables moving function/class '{' to its own line
 */
#include "aholyc.h"
#include <unistd.h>

typedef struct {
	int outer;        /* indent level of the line that opened the block */
	bool is_switch;
	bool in_sub;      /* between start:/end: in a sub_switch */
} FBlock;

typedef struct {
	FBlock stk[256];
	int nstk;
	int paren;        /* () [] nesting carried across lines */
	bool in_bc;       /* inside a block comment */
	char in_str;      /* 0, '"' or '\'' when a literal spans lines */
	bool sw_pending;  /* saw 'switch': the next '{' is a switch block */
	int cur_indent;   /* indent level given to the line being scanned */
	/* braceless control bodies: if (x) <newline> stmt; indents +1 */
	int hang;         /* pending braceless if/else/for/while/do headers */
	bool ctrl_open;   /* control header with its '(...)' still open */
	bool stmt_open;   /* statement continued on the next line (no parens) */
	/* per-line facts collected by scan_line */
	char first_word[16], last_word[16];
	char last_code;   /* last code character on the line */
	int fw_state;
} FState;

static int fmt_indent = 2;
static bool fmt_braces = true;

/* indent level for a plain statement in the current block */
static int stmt_level(FState *st) {
	if (st->nstk == 0) {
		return 0;
	}
	FBlock *top = &st->stk[st->nstk - 1];
	return top->outer + (top->is_switch? 2: 1);
}

static bool word_is(const char *s, const char *w) {
	size_t n = strlen (w);
	if (strncmp (s, w, n)) {
		return false;
	}
	char c = s[n];
	return !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
	         (c >= '0' && c <= '9') || c == '_');
}

static bool ident_start(char c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static bool ident_char(char c) {
	return ident_start (c) || (c >= '0' && c <= '9');
}

static bool space_char(char c) {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static const char *skip_space(const char *s) {
	while (space_char (*s)) {
		s++;
	}
	return s;
}

/* 'name:' alone (goto label): TempleOS puts these at column 0 */
static bool is_label_line(const char *s) {
	int i = 0;
	if (!ident_start (s[0])) {
		return false;
	}
	while (ident_char (s[i])) {
		i++;
	}
	if (s[i] != ':') {
		return false;
	}
	if (word_is (s, "case") || word_is (s, "default") ||
	    word_is (s, "start") || word_is (s, "end")) {
		return false;
	}
	for (i++; s[i]; i++) {
		if (s[i] == '/' && (s[i + 1] == '/' || s[i + 1] == '*')) {
			return true; /* trailing comment only */
		}
		if (s[i] != ' ' && s[i] != '\t') {
			return false;
		}
	}
	return true;
}

/* remember first/last code word of the line; the first-word capture
 * skips leading '}' and 'else' so '} else if (...)' reads as "if" */
static void note_word(FState *st, const char *w, int n) {
	if (n > 15) {
		n = 15;
	}
	memcpy (st->last_word, w, n);
	st->last_word[n] = 0;
	if (st->fw_state == 0 && !strcmp (st->last_word, "else")) {
		strcpy (st->first_word, "else");
		st->fw_state = 1;
	} else if (st->fw_state <= 1) {
		memcpy (st->first_word, st->last_word, n + 1);
		st->fw_state = 2;
	}
}

/* advance the scan state over one (already indent-stripped) line */
static void scan_line(FState *st, const char *s) {
	st->first_word[0] = st->last_word[0] = 0;
	st->last_code = 0;
	st->fw_state = 0;
	for (int i = 0; s[i];) {
		if (st->in_bc) {
			if (s[i] == '*' && s[i + 1] == '/') {
				st->in_bc = false;
				i += 2;
			} else {
				i++;
			}
			continue;
		}
		if (st->in_str) {
			if (s[i] == '\\' && s[i + 1]) {
				i += 2;
			} else if (s[i] == st->in_str) {
				st->last_code = st->in_str;
				st->in_str = 0;
				i++;
			} else {
				i++;
			}
			continue;
		}
		char c = s[i];
		if (c == '/' && s[i + 1] == '/') {
			return; /* rest of line is a comment */
		}
		if (c == '/' && s[i + 1] == '*') {
			st->in_bc = true;
			i += 2;
			continue;
		}
		if (c == '"' || c == '\'') {
			st->in_str = c;
			st->last_code = c;
			st->last_word[0] = 0;
			if (st->fw_state <= 1) {
				st->fw_state = 2;
			}
			i++;
			continue;
		}
		if (ident_start (c)) {
			int w = i;
			if (st->paren == 0 && word_is (s + i, "switch")) {
				st->sw_pending = true;
			}
			while (ident_char (s[i])) {
				i++;
			}
			note_word (st, s + w, i - w);
			st->last_code = s[i - 1];
			continue;
		}
		if (c != ' ' && c != '\t') {
			st->last_code = c;
			st->last_word[0] = 0;
			if (st->fw_state <= 1 && c != '}') {
				st->fw_state = 2; /* '}' may prefix '} else if' */
			}
		}
		switch (c) {
		case '(': case '[':
			st->paren++;
			break;
		case ')': case ']':
			if (st->paren > 0) {
				st->paren--;
			}
			break;
		case '{':
			if (st->nstk < 256) {
				st->stk[st->nstk].outer = st->cur_indent;
				st->stk[st->nstk].is_switch = st->sw_pending;
				st->nstk++;
			}
			st->sw_pending = false;
			break;
		case '}':
			if (st->nstk > 0) {
				st->nstk--;
			}
			st->sw_pending = false;
			break;
		case ';':
			if (st->paren == 0) {
				st->sw_pending = false;
			}
			break;
		default:
			break;
		}
		i++;
	}
}

/* If the line is a top-level function/class header ending with '{'
 * (optionally followed by a // comment), return the offset of that
 * '{' so it can be moved to its own line; -1 otherwise. */
static int split_pos(FState *st, const char *s) {
	if (!fmt_braces || st->nstk > 0 || st->paren > 0 || st->hang > 0 ||
	    st->in_bc || st->in_str || s[0] == '#' || s[0] == '{') {
		return -1;
	}
	static const char *ctrl[] = {
		"if", "else", "while", "for", "do", "switch", "try",
		"catch", "lock", NULL
	};
	for (int i = 0; ctrl[i]; i++) {
		if (word_is (s, ctrl[i])) {
			return -1;
		}
	}
	bool is_class = word_is (s, "class") || word_is (s, "union") ||
		(word_is (s, "public") && (strstr (s, "class") || strstr (s, "union")));
	/* scan for the last code-level '{' and what surrounds it */
	int brace = -1, prev_code = -1;
	bool code_after = false, bc = false;
	char q = 0;
	for (int i = 0; s[i];) {
		if (bc) {
			if (s[i] == '*' && s[i + 1] == '/') {
				bc = false;
				i++;
			}
			i++;
			continue;
		}
		if (q) {
			if (s[i] == '\\' && s[i + 1]) {
				i++;
			} else if (s[i] == q) {
				q = 0;
			}
			i++;
			continue;
		}
		if (s[i] == '/' && s[i + 1] == '/') {
			break; /* trailing comment: fine after '{' */
		}
		if (s[i] == '/' && s[i + 1] == '*') {
			bc = true;
			i += 2;
			code_after = brace >= 0? true: code_after;
			continue;
		}
		if (s[i] == '"' || s[i] == '\'') {
			q = s[i];
		}
		if (s[i] != ' ' && s[i] != '\t') {
			if (s[i] == '{') {
				brace = i;
				code_after = false;
			} else {
				if (brace >= 0) {
					code_after = true;
				} else {
					prev_code = i;
				}
			}
		}
		i++;
	}
	if (bc || q || brace <= 0 || code_after) {
		return -1; /* no header, unterminated, or '{ code...' one-liner */
	}
	if (!is_class && (prev_code < 0 || s[prev_code] != ')')) {
		return -1; /* functions must end '...) {' */
	}
	return brace;
}

/* ------------------------------------------------------- formatting */

static void put_indent(FILE *o, int level) {
	for (int n = level * fmt_indent; n > 0; n--) {
		fputc (' ', o);
	}
}

static char *fmt_run(const char *src) {
	char *out = NULL;
	size_t outsz = 0;
	FILE *o = open_memstream (&out, &outsz);
	if (!o) {
		return NULL;
	}
	FState st = {0};
	const char *p = src;
	int pending_blank = 0;
	bool wrote_any = false;

	while (*p) {
		const char *e = strchr (p, '\n');
		size_t len = e? (size_t)(e - p): strlen (p);
		char *line = xmalloc (len + 1);
		memcpy (line, p, len);
		line[len] = 0;
		p += len + (e? 1: 0);

		if (st.in_bc || st.in_str) {
			/* inside a multi-line comment/string: verbatim */
			for (int i = 0; i < pending_blank; i++) {
				fputc ('\n', o);
			}
			pending_blank = 0;
			fputs (line, o);
			fputc ('\n', o);
			wrote_any = true;
			st.cur_indent = stmt_level (&st);
			scan_line (&st, line);
			free (line);
			continue;
		}

		/* strip leading and trailing whitespace */
		char *b = skip_space (line);
		char *t = b + strlen (b);
		while (t > b && (t[-1] == ' ' || t[-1] == '\t' || t[-1] == '\r')) {
			*--t = 0;
		}
		if (!*b) {
			if (wrote_any) {
				pending_blank++; /* dropped at EOF, kept elsewhere */
			}
			free (line);
			continue;
		}
		for (int i = 0; i < pending_blank; i++) {
			fputc ('\n', o);
		}
		pending_blank = 0;

		/* pick this line's indent level */
		int level;
		FBlock *top = st.nstk > 0? &st.stk[st.nstk - 1]: NULL;
		if (b[0] == '}') {
			level = top? top->outer: 0;
		} else if (top && top->is_switch &&
		           (word_is (b, "case") || word_is (b, "default") ||
		            word_is (b, "start") || word_is (b, "end"))) {
			/* sub_switch: cases between start:/end: one level deeper */
			bool is_case = word_is (b, "case") || word_is (b, "default");
			level = top->outer + 1 + (is_case && top->in_sub? 1: 0);
			if (word_is (b, "start")) {
				top->in_sub = true;
			} else if (word_is (b, "end")) {
				top->in_sub = false;
			}
		} else if (is_label_line (b)) {
			level = 0;
		} else {
			int add = st.hang + (st.stmt_open? 1: 0);
			if (b[0] == '{' && add > 0) {
				add--; /* '{' aligns with the header it belongs to */
			}
			level = stmt_level (&st) + add;
		}
		if (st.paren > 0) {
			int cont = st.paren;
			if (b[0] == ')' || b[0] == ']') {
				cont--;
			}
			level += cont > 4? 4: cont;
		}

		int sp = split_pos (&st, b);
		if (sp > 0) {
			/* header line, then '{' (plus any comment) on its own */
			char *hdr = xmalloc (sp + 1);
			memcpy (hdr, b, sp);
			hdr[sp] = 0;
			char *ht = hdr + strlen (hdr);
			while (ht > hdr && (ht[-1] == ' ' || ht[-1] == '\t')) {
				*--ht = 0;
			}
			put_indent (o, level);
			fputs (hdr, o);
			fputc ('\n', o);
			put_indent (o, level);
			fputs (b + sp, o);
			fputc ('\n', o);
			free (hdr);
		} else {
			put_indent (o, level);
			fputs (b, o);
			fputc ('\n', o);
		}
		wrote_any = true;
		st.cur_indent = level;
		scan_line (&st, b);

		/* hanging bodies: a control header without '{' indents the
		 * following statement; any completed statement clears it.
		 * Directive lines are whole by definition: skip, like comments. */
		if (!st.in_str && !st.in_bc && b[0] != '#') {
			bool ctrl = word_is (st.first_word, "if") ||
				word_is (st.first_word, "while") ||
				word_is (st.first_word, "for");
			char lc = st.last_code;
			if (lc == '{' || lc == ';' || lc == '}' || lc == ':') {
				st.hang = 0;
				st.ctrl_open = false;
				st.stmt_open = false;
			} else if (st.paren > 0) {
				if (ctrl) {
					st.ctrl_open = true;
				}
			} else if (lc == ')' && (ctrl || st.ctrl_open)) {
				st.hang++;
				st.ctrl_open = false;
			} else if (!strcmp (st.last_word, "else") ||
			           !strcmp (st.last_word, "do")) {
				st.hang++;
			} else if (lc) {
				st.stmt_open = true; /* ends mid-statement: ',' '=' ... */
			}
		}
		free (line);
	}
	fclose (o);
	return out? out: xstrdup ("");
}

/* the only allowed difference is whitespace: verify or refuse */
static bool ws_equal(const char *a, const char *b) {
	for (;;) {
		a = skip_space (a);
		b = skip_space (b);
		if (*a != *b) {
			return false;
		}
		if (!*a) {
			return true;
		}
		a++;
		b++;
	}
}

/* ----------------------------------------------------------- driver */

int fmt_main(int argc, char **argv) {
	bool write = false, quiet = false;
	const char *files[256];
	int nfiles = 0;

	const char *env = getenv ("AHOLYC_FMT_INDENT");
	if (env && atoi (env) >= 1 && atoi (env) <= 16) {
		fmt_indent = atoi (env);
	}
	env = getenv ("AHOLYC_FMT_BRACES");
	if (env && (!strcmp (env, "0") || !strcmp (env, "off") || !strcmp (env, "no"))) {
		fmt_braces = false;
	}

	for (int i = 0; i < argc; i++) {
		if (!strcmp (argv[i], "-w")) {
			write = true;
		} else if (!strcmp (argv[i], "-q")) {
			quiet = true;
		} else if (!strcmp (argv[i], "-h")) {
			printf ("usage: aholyc fmt [-w | -q] [file.HC ... | -]\n"
				"  -w  rewrite files in place (only when they change)\n"
				"  -q  no output; list files needing formatting, exit 1 if any\n"
				"  -   read from stdin, write to stdout\n"
				"env: AHOLYC_FMT_INDENT=n  AHOLYC_FMT_BRACES=0  (doc/format.md)\n");
			return 0;
		} else if (nfiles < 256) {
			files[nfiles++] = argv[i];
		} else {
			fprintf (stderr, "aholyc fmt: too many files\n");
			return 1;
		}
	}
	if (nfiles == 0) {
		files[nfiles++] = "-"; /* like gofmt: no args means stdin */
	}

	int rc = 0;
	for (int i = 0; i < nfiles; i++) {
		bool is_stdin = !strcmp (files[i], "-");
		char *src = read_source (files[i]);
		if (!src) {
			fprintf (stderr, "aholyc fmt: cannot open '%s'\n", files[i]);
			rc = 1;
			continue;
		}
		char *out = fmt_run (src);
		if (!out || !ws_equal (src, out)) {
			/* never emit anything that fails verification */
			fprintf (stderr, "aholyc fmt: internal error on '%s', left untouched\n",
				is_stdin? "(stdin)": files[i]);
			free (src);
			free (out);
			rc = 1;
			continue;
		}
		bool changed = strcmp (src, out) != 0;
		if (quiet) {
			if (changed) {
				if (!is_stdin) {
					printf ("%s\n", files[i]);
				}
				rc = 1;
			}
		} else if (write && !is_stdin) {
			if (changed) {
				char *tmp = xasprintf ("%s.fmt.tmp", files[i]);
				FILE *f = fopen (tmp, "wb");
				if (!f || fwrite (out, 1, strlen (out), f) != strlen (out)) {
					fprintf (stderr, "aholyc fmt: cannot write '%s'\n", tmp);
					if (f) {
						fclose (f);
					}
					unlink (tmp);
					rc = 1;
				} else {
					fclose (f);
					if (rename (tmp, files[i]) != 0) {
						fprintf (stderr, "aholyc fmt: cannot replace '%s'\n", files[i]);
						unlink (tmp);
						rc = 1;
					}
				}
				free (tmp);
			}
		} else {
			fputs (out, stdout);
		}
		free (src);
		free (out);
	}
	return rc;
}
