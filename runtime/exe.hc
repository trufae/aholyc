// aholyc #exe prelude: compiled in front of every #exe{} block.
// The block runs inside the compiler process; these externs resolve to
// a per-DSO bridge initialized with callbacks (see src/exe.c).

// Token kinds, same values as TokenKind in src/aholyc.h.
#define TK_EOF   0
#define TK_ID    1
#define TK_NUM   2
#define TK_FNUM  3
#define TK_STR   4
#define TK_CHR   5
#define TK_PUNCT 6
#define TK_KEYWORD 7
#define TK_TYPE  8

// Mirror of struct Token in src/aholyc.h: same names, same offsets.
// ExeStream() points at the compiler's live tokens, so writes here
// mutate the program being compiled.  HolyC classes are packed while
// the C struct is aligned, so '$$' pins the C compiler's padding.
class Token
{
  I32 kind;
  $$ = 8;
  Token *next;
  I64 ival;       // TK_NUM, TK_CHR
  F64 fval;       // TK_FNUM
  U8 *str;        // TK_STR bytes; TK_ID/TK_KEYWORD/TK_TYPE/TK_PUNCT text
  I32 len;
  $$ = 48;
  U8 *file;
  I32 line;
  Bool at_bol;
  Bool has_space;
  Bool no_expand;
  $$ = 88;        // sizeof matches the C struct (private fields follow)
};

// compiler callbacks supplied through the generated DSO bridge
extern U0 __StreamPutS(U8 *s);
extern Token *ExeStream();        // tokens following this #exe block
extern U0 ExeStreamSet(Token *t); // consume tokens from the stream
extern I64 Cd(U8 *path);          // set this compiler instance's cwd
extern I64 Now();                 // compile-time clock (unix seconds)

// Injects text into the compile stream. Used in #exe{} blocks.
U0 StreamPrint(U8 *fmt, ...)
{
  U8 *s = StrPrintJoin(NULL, fmt, argc, argv);
  __StreamPutS(s);
  Free(s);
}

// Accepted for TempleOS compatibility; aholyc's codegen has no such
// knobs, so these are no-ops (see doc/exe.md).
#define OPTf_ECHO               0
#define OPTf_TRACE              1
#define OPTf_NO_REG_VAR         2
#define OPTf_WARN_PAREN         3
#define OPTf_WARN_DUP_TYPES     4
#define OPTf_GLBLS_ON_DATA_HEAP 5
I64 Option(I64 opt, I64 val) { return 0; }
U0 PassTrace(I64 mask) {}
Bool Echo(Bool val) { return FALSE; }
