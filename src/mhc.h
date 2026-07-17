/* mhc - modern HolyC compiler
 * Public domain, in the spirit of TempleOS.
 * Single shared header: lexer, types, AST, symbols, backend interface.
 */
#ifndef MHC_H
#define MHC_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdbool.h>

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
	Type *base;        /* TY_PTR/TY_ARRAY element, TY_FUNC return type */
	int array_len;
	/* TY_CLASS */
	char *name;
	Member *members;
	Type *parent;      /* single inheritance */
	bool is_union;
};

extern Type *ty_u0, *ty_i8, *ty_u8, *ty_i16, *ty_u16, *ty_i32, *ty_u32,
	*ty_i64, *ty_u64, *ty_f64;

Type *ptr_to(Type *base);
Type *array_of(Type *base, int len);
bool is_integer(Type *ty);
bool is_numeric(Type *ty);
Member *find_member(Type *ty, char *name);

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

/* ---------------------------------------------------------------- lexer */

Token *lex_file(const char *path);
Token *lex_string(const char *src, const char *fake_name, Token *chain_after);
Token *token_join(Token *a, Token *b);
void lex_add_include_dir(const char *dir);
void lex_define(const char *name, const char *value);

/* ---------------------------------------------------------------- parser */

Program *parse(Token *tok);

/* ------------------------------------------------------------ diagnostics */

void error(const char *fmt, ...);
void error_tok(Token *tok, const char *fmt, ...);
void warn_tok(Token *tok, const char *fmt, ...);

/* ---------------------------------------------------------------- backend
 * Pluggable codegen. A backend turns the AST into a source artifact
 * (LLVM-IR, C, JS, ...) and knows how to produce an executable from it
 * using external tools only (never linked-in libraries).
 */
typedef struct Backend {
	const char *name;   /* -b <name> */
	const char *ext;    /* artifact extension, e.g. ".ll" */
	const char *descr;
	/* Emit program as source text to out. */
	void (*emit)(Program *prog, FILE *out);
	/* Build executable from emitted artifact. Returns 0 on success.
	 * opt: optimization flag string, e.g. "-Os". */
	int (*build)(const char *artifact, const char *outpath,
	             const char *opt, bool verbose, bool keep);
	/* Build a relocatable object (-c). NULL if unsupported. */
	int (*build_obj)(const char *artifact, const char *outpath,
	                 const char *opt, bool verbose, bool keep);
} Backend;

/* -c / object emission: startup code becomes a constructor, the runtime
 * is declared instead of embedded, 'public' symbols are exported. */
extern bool mhc_obj_mode;

/* pass-through toolchain flags (-I/-L/-l), appended to cc invocations */
extern char *mhc_ccflags[64];
extern int mhc_nccflags;

extern const Backend backend_ll;
extern const Backend backend_c;
extern const Backend backend_js;

/* Embedded runtime sources (generated by tools/file2c) */
extern const char rt_c_src[];
extern const char rt_js_src[];
extern const char prelude_hc[];

/* driver helpers */
int run_cmd(char *const argv[], bool verbose);
bool have_cmd(const char *name);

/* misc */
char *xstrdup(const char *s);
char *xasprintf(const char *fmt, ...);
void *xmalloc(size_t n);
void *xcalloc(size_t n, size_t m);

#endif
