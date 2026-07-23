/* aholyc - another Holy-C compiler
 * Public domain, in the spirit of TempleOS.
 * Single shared header: lexer, types, AST, symbols, backend interface.
 */
#ifndef AHOLYC_H
#define AHOLYC_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdbool.h>
#include <setjmp.h>
#include "../include/aholyc.h"
#include "config.h"

#ifndef AHOLYC_BACKEND_LLVM
#define AHOLYC_BACKEND_LLVM 1
#endif
#ifndef AHOLYC_BACKEND_C
#define AHOLYC_BACKEND_C 1
#endif
#ifndef AHOLYC_BACKEND_JS
#define AHOLYC_BACKEND_JS 1
#endif

typedef struct AholyIncDir AholyIncDir;
typedef struct AholyMacro AholyMacro;
typedef struct { void (*fn)(void *); void *arg; } AholyCleanup;

/* ---------------------------------------------------------------- tokens */

typedef enum {
	TK_EOF,
	TK_ID,     /* identifier or keyword */
	TK_NUM,    /* integer literal (i64) */
	TK_FNUM,   /* float literal (f64) */
	TK_STR,    /* string literal */
	TK_CHR,    /* char literal (multi-char, packed little-endian) */
	TK_PUNCT,  /* operator / punctuation */
} TokenKind;

typedef struct Token Token;
#define HINT_INLINE 1
#define HINT_NOINLINE 2
struct Token {
	TokenKind kind;
	Token *next;
	int64_t ival;      /* TK_NUM, TK_CHR */
	double fval;       /* TK_FNUM */
	char *str;         /* TK_STR: decoded bytes; TK_ID/TK_PUNCT: text */
	int len;           /* length of str (TK_STR may contain NULs) */
	char *file;        /* source file name */
	int line;
	bool at_bol;       /* first token on its line (for directives) */
	bool has_space;    /* preceded by whitespace */
	bool no_expand;    /* macro self-reference guard */
	int hint_bits;      /* @bits=N attached by a preceding comment; 0 if none */
	int hint_align;     /* @align=N, -1 for natural, 0 if absent */
	unsigned hints;     /* HINT_* flags attached by a preceding comment */
	Aholyc *cc;         /* owning compiler */
};

/* ----------------------------------------------------------------- types */

typedef struct Type Type;
typedef struct Member Member;
typedef struct Obj Obj;
typedef struct Node Node;

typedef enum {
	TY_VOID,   /* U0: zero size */
	TY_INT,    /* I8..U64 by size + is_unsigned */
	TY_F64,
	TY_PTR,
	TY_ARRAY,
	TY_CLASS,  /* class or union */
	TY_FUNC,
} TypeKind;

struct Member {
	Member *next;
	Type *ty;
	char *name;
	int offset;
};

struct Type {
	TypeKind kind;
	int size;
	int align;
	bool is_unsigned;
	int bits;          /* requested integer value width; 0 if unhinted */
	Type *base;        /* TY_PTR/TY_ARRAY element, TY_FUNC return type */
	int array_len;
	/* TY_CLASS */
	char *name;
	Member *members;
	Type *parent;      /* single inheritance */
	bool is_union;
};

/* ------------------------------------------------------------------- AST */

typedef enum {
	/* expressions */
	ND_NUM, ND_FNUM, ND_STR,
	ND_VAR,            /* variable reference (obj) */
	ND_FUNCNAME,       /* function designator: &f or implicit call target */
	ND_ADD, ND_SUB, ND_MUL, ND_DIV, ND_MOD,
	ND_AND, ND_OR, ND_XOR, ND_SHL, ND_SHR,
	ND_POW,            /* ` operator */
	ND_EQ, ND_NE, ND_LT, ND_LE,
	ND_LOGAND, ND_LOGOR, ND_LOGXOR,
	ND_NOT, ND_BITNOT, ND_NEG,
	ND_ASSIGN,
	ND_COMMA,
	ND_MEMBER,         /* lhs.member (member in ->member_ref) */
	ND_DEREF, ND_ADDR,
	ND_CALL,           /* lhs = callee expr; args in ->args */
	ND_CAST,           /* lhs cast to ->ty (postfix in source) */
	ND_PREINC, ND_PREDEC, ND_POSTINC, ND_POSTDEC,
	/* statements */
	ND_EXPR_STMT,
	ND_BLOCK,
	ND_IF, ND_WHILE, ND_DOWHILE, ND_FOR,
	ND_RETURN, ND_BREAK_,  /* only inside lowering; parser resolves to goto */
	ND_GOTO, ND_LABEL,
	ND_TRY,            /* then = try body, els = catch body */
	ND_NOP,
} NodeKind;

typedef enum {
	TRY_NONE,           /* body cannot throw; catch is unreachable */
	TRY_LOCAL,          /* body needs only a compiler-generated branch */
	TRY_DYNAMIC,        /* body can receive an exception from a callee */
} TryMode;

struct Node {
	NodeKind kind;
	Node *next;        /* statement list / arg list chain */
	Type *ty;          /* value type of expression */
	Token *tok;        /* for diagnostics */

	Node *lhs, *rhs;
	Node *cond, *then, *els;
	Node *init, *inc;      /* for-loop */
	Node *body;            /* block contents */
	Node *args;            /* call arguments */

	Obj *var;              /* ND_VAR */
	Obj *func;             /* ND_FUNCNAME, resolved direct calls */
	Member *member_ref;    /* ND_MEMBER */
	char *label;           /* ND_GOTO/ND_LABEL */

	int64_t ival;          /* ND_NUM */
	double fval;           /* ND_FNUM */
	char *str;             /* ND_STR bytes */
	int str_len;
	int str_id;            /* assigned string-literal index */
	int nfixed;            /* ND_CALL: args bound to named params; rest variadic */
	bool bit_cast;         /* ND_CAST: postfix I64<->F64 keeps the bit pattern
	                          (TempleOS spec; ToI64/ToF64 convert the value) */
	TryMode try_mode;       /* ND_TRY lowering selected by effect analysis */
};

/* --------------------------------------------------------------- objects */

struct Obj {
	Obj *next;
	char *name;
	Type *ty;
	bool is_func;
	bool is_global;
	bool is_extern;    /* runtime/libc symbol: emit unmangled, no body */
	bool is_variadic;  /* declared with ... (gets argc/argv) */
	bool is_static_dur; /* global storage */
	bool is_param;     /* function parameter: stored full-width (64-bit) */
	bool is_public;    /* HolyC 'public': exported, unmangled symbol */
	bool from_prelude; /* extern declared by the prelude (runtime API) */
	bool address_taken; /* storage is observable through a pointer */
	bool can_throw;     /* inferred: an exception may escape this function */
	unsigned hints;     /* HINT_* function attributes */
	int align;          /* requested local alignment; 0 if absent */
	/* functions */
	Obj *params;       /* chain via next (separate list from locals) */
	int nparams;
	Node **defaults;   /* per-param default expr or NULL */
	Node *body;        /* NULL for extern decls */
	Obj *locals;       /* all locals incl. params (for allocation) */
	/* variables */
	Node *init;        /* lowered into startup code by parser (globals) */
	int uid;           /* unique id for scoped locals in output */
};

/* --------------------------------------------------------------- program */

typedef struct StrLit StrLit;

/* Small-string optimized growable buffer. data is always NUL-terminated. */
typedef struct {
	Aholyc *cc;
	char *data;
	size_t len;
	size_t cap;
	char buf[64];
} StrBuf;
struct StrLit {
	StrLit *next;
	char *data;
	int len;           /* excluding implicit NUL */
	int id;
};

typedef struct {
	Obj *funcs;        /* defined + extern functions */
	Obj *globals;      /* global variables */
	Obj *startup;      /* synthetic function: top-level code, in order */
	StrLit *strings;
	int nstrings;
} Program;

/* ------------------------------------------------------------- compiler */

typedef struct { char **v; int n, cap; } Argv;

struct Aholyc {
	void *allocs;
	AholyIncDir *inc_dirs;
	AholyMacro *macros;
	char *cwd;
	Argv ccflags;
	FILE *diagnostics;
	AholyCleanup cleanups[8];
	jmp_buf error_jmp;
	char error[1024];
	int ncleanups;
	bool verbose, keep, use_hints, error_active;
};

/* ---------------------------------------------------------------- lexer */

Token *lex_file(Aholyc *cc, const char *path);
Token *lex_string(Aholyc *cc, const char *src, const char *fake_name,
	Token *chain_after);
Token *token_join(Token *a, Token *b);
void lex_add_include_dir(Aholyc *cc, const char *dir);
bool lex_set_cwd(Aholyc *cc, const char *path);
void lex_reset(Aholyc *cc);
/* preprocessor (lexpp.c); tokenize + search_include (lex.c) are shared
 * between the two translation units */
Token *lex_preprocess(Aholyc *cc, Token *raw);
void lex_define(Aholyc *cc, const char *name, const char *value);
bool lex_is_identifier(const char *s);
Token *tokenize(Aholyc *cc, const char *src, const char *fname);
char *search_include(Aholyc *cc, const char *name, const char *from_file);

/* ---------------------------------------------------------------- parser */

Program *parse(Aholyc *cc, Token *tok, bool align_hints);

/* --------------------------------------------------------------- analysis */

void analyze_exceptions(Program *prog);
bool is_throw_call(Node *n);

/* ------------------------------------------------------------------ #exe
 * Compile-time execution (exe.c): the block is compiled with the C
 * backend into a shared library, dlopened into the compiler process
 * and run; its StreamPrint output is returned for stream splicing.
 * *rest is the token stream after the block; the block may advance it. */
char *exe_run(Aholyc *cc, Token *block, Token **rest);

/* ------------------------------------------------------------ diagnostics */

void error(Aholyc *cc, const char *fmt, ...);
void error_tok(Aholyc *cc, Token *tok, const char *fmt, ...);
void warn_tok(Aholyc *cc, Token *tok, const char *fmt, ...);

/* ---------------------------------------------------------------- backend
 * Pluggable codegen. A backend turns the AST into a source artifact
 * (LLVM-IR, C, JS, ...) and knows how to produce an executable from it
 * using external tools only (never linked-in libraries).
 */
typedef struct Backend {
	const char *name;   /* -b <name> */
	const char *ext;    /* artifact extension, e.g. ".ll" */
	const char *descr;
	/* Append program source text to an initialized buffer. */
	void (*emit)(Aholyc *cc, Program *prog, StrBuf *out,
		bool object_mode, bool ctor_mode);
	/* Build executable from emitted artifact. Returns 0 on success.
	 * opt: optimization flag string, e.g. "-Os". */
	int (*build)(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt);
	/* Build a relocatable object (-c). NULL if unsupported. */
	int (*build_obj)(Aholyc *cc, const char *artifact,
		const char *outpath, const char *opt);
} Backend;

#if AHOLYC_BACKEND_LLVM
extern const Backend aholyc_i_backend_ll;
#endif
#if AHOLYC_BACKEND_C
extern const Backend aholyc_i_backend_c;
#endif
#if AHOLYC_BACKEND_JS
extern const Backend aholyc_i_backend_js;
#endif

/* Embedded runtime sources (generated by tools/file2c) */
#if AHOLYC_BACKEND_LLVM || AHOLYC_BACKEND_C
extern const char aholyc_i_rt_c_src[];
#endif
#if AHOLYC_BACKEND_JS
extern const char aholyc_i_rt_js_src[];
#endif
extern const char aholyc_i_prelude_hc[];
#if AHOLYC_BACKEND_C
extern const char aholyc_i_exe_hc[];
#endif

/* driver helpers */
void arg_push(Aholyc *cc, Argv *a, const char *s);
int run_cmd(Aholyc *cc, char *const argv[]);
int run_cc(Aholyc *cc, const char *tool, const char *opt, const char *out,
	const char *const inputs[], int ninputs, bool object, bool gc);
bool have_cmd(Aholyc *cc, const char *name);
void arg_push_words(Aholyc *cc, Argv *a, char *s);
void pkgconfig_push(Aholyc *cc, const char *pkgs);

/* 'aholyc fmt' source formatter (fmt.c, self-contained; doc/format.md) */
int fmt_main(Aholyc *cc, int argc, char **argv);

/* misc */
char *read_source(Aholyc *cc, const char *path);
void write_file(Aholyc *cc, const char *path,
	const char *data, size_t len);
char *xstrdup(Aholyc *cc, const char *s);
char *xasprintf(Aholyc *cc, const char *fmt, ...);
void *xmalloc(Aholyc *cc, size_t n);
void *xcalloc(Aholyc *cc, size_t n, size_t m);
void xfree_to(Aholyc *cc, void *mark);
void cleanup_push(Aholyc *cc, void (*fn)(void *), void *arg);
static inline void cleanup_pop(Aholyc *cc) { cc->ncleanups--; }
static inline void cleanup_file(void *file) { fclose (file); }

void sb_init(StrBuf *sb, Aholyc *cc);
void sb_putn(StrBuf *sb, const char *s, size_t n);
void sb_puts(StrBuf *sb, const char *s);
void sb_putc(StrBuf *sb, int c);
void sb_printf(StrBuf *sb, const char *fmt, ...);
char *sb_take(StrBuf *sb);

#endif
