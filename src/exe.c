/* aholyc #exe{} — compile-time execution via dlopen (see doc/exe.md).
 *
 * A #exe block is compiled by the same lexer/parser/codegen as any
 * program, using the C backend, into a shared library that is
 * dlopened into the compiler process and run. Because it lives in
 * the compiler's address space it sees the compiler's internals
 * directly: a small generated bridge routes callbacks to this run, and the
 * Token class declared in runtime/exe.hc mirrors struct Token from
 * aholyc.h byte for byte, so blocks can inspect and mutate the live
 * token stream in place.
 */
#include "aholyc.h"
#include <dlfcn.h>
#include <unistd.h>
#include <time.h>

typedef struct {
	void (*put)(void *, void *);
	void *(*get)(void *);
	void (*set)(void *, void *);
	int64_t (*cd)(void *, void *);
	int64_t (*now)(void *);
} ExeApi;

typedef struct {
	Aholyc *cc;
	Token *stream;
	StrBuf out;
} ExeRun;

/* append one StreamPrint result; each one starts a fresh line so
 * injected directives (#define, nested #exe) are at start-of-line */
static void stream_put(void *ctx, void *s) {
	ExeRun *run = ctx;
	if (s) {
		sb_puts (&run->out, s);
	}
	sb_putc (&run->out, '\n');
}

/* the compiler's token stream right after the #exe block */
static void *stream_get(void *ctx) { return ((ExeRun *)ctx)->stream; }

/* replace the stream head: lets a block consume tokens it parsed */
static void stream_set(void *ctx, void *stream) { ((ExeRun *)ctx)->stream = stream; }

static int64_t exe_cd(void *ctx, void *path) {
	return path && lex_set_cwd (((ExeRun *)ctx)->cc, path);
}

static int64_t exe_now(void *ctx) { (void)ctx; return (int64_t)time (NULL); }

static void cleanup_dso(void *handle) { dlclose (handle); }

/* Definitions for the externs declared by runtime/exe.hc.  The bridge lives
 * in each generated DSO, so concurrent compilers never need a global router. */
static const char exe_bridge[] =
	"typedef struct{void(*put)(void*,void*);void*(*get)(void*);"
	"void(*set)(void*,void*);hc_i64(*cd)(void*,void*);hc_i64(*now)(void*);} AholyApi;\n"
	"static void *ctx;static AholyApi *api;\n"
	"void __aholyc_exe_init(void*c,void*a){ctx=c;api=a;}\n"
	"void __StreamPutS(void*s){api->put(ctx,s);}\n"
	"void *ExeStream(void){return api->get(ctx);}\n"
	"void ExeStreamSet(void*s){api->set(ctx,s);}\n"
	"hc_i64 Cd(void*p){return api->cd(ctx,p);}\n"
	"hc_i64 Now(void){return api->now(ctx);}\n";

/* ------------------------------------------------------- driver */

/* Compile and run one #exe block. 'block' is its preprocessed body,
 * EOF-terminated; *rest is the stream after the block, which the
 * block may advance. Returns the text to splice into the stream. */
char *exe_run(Aholyc *cc, Token *block, Token **rest) {
	/* a stand-alone program: runtime prelude, exe API, block body.
	 * The body is preprocessed last so the exe API macros apply. */
	Token *toks = lex_string (cc, aholyc_i_prelude_hc, "<prelude>", NULL);
	toks = token_join (toks, lex_string (cc, aholyc_i_exe_hc, "<exe-api>", NULL));
	toks = token_join (toks, lex_preprocess (cc, block));
	Program *p = parse (cc, toks, true);
	ExeRun run = { .cc = cc, .stream = *rest };
	sb_init (&run.out, cc);

	const char *tmp = getenv ("TMPDIR");
	if (!tmp || !*tmp) {
		tmp = "/tmp";
	}
	char *dir = xasprintf (cc, "%s/aholyc-exe-XXXXXX", tmp);
	if (!mkdtemp (dir)) {
		error (cc, "#exe: cannot create temporary directory");
	}
	char *cpath = xasprintf (cc, "%s/block.c", dir);
	char *sopath = xasprintf (cc, "%s/block.so", dir);
	StrBuf src;
	sb_init (&src, cc);
	aholyc_i_backend_c.emit (cc, p, &src, false, false);
	sb_puts (&src, exe_bridge);
	write_file (cc, cpath, src.data, src.len);

	const char *tool = getenv ("CC");
	if (!tool || !*tool) {
		tool = have_cmd (cc, "cc")? "cc": have_cmd (cc, "clang")? "clang": "gcc";
	}
	char *argv[] = {
		(char *)tool, "-O0", "-w", "-fno-strict-aliasing",
#ifdef __APPLE__
		"-bundle", "-Wl,-undefined,dynamic_lookup",
#else
		"-shared", "-fPIC",
#endif
		"-o", sopath, cpath, "-lm", NULL
	};
	if (run_cmd (cc, argv) != 0) {
		error (cc, "#exe: failed to build %s (kept for inspection)", cpath);
	}
	void *h = dlopen (sopath, RTLD_NOW | RTLD_LOCAL);
	if (!h) {
		error (cc, "#exe: dlopen: %s", dlerror ());
	}
	cleanup_push (cc, cleanup_dso, h);
	void (*init)(void *, void *) = (void (*)(void *, void *))(intptr_t)
		dlsym (h, "__aholyc_exe_init");
	if (!init) {
		error (cc, "#exe: callback bridge missing in %s", sopath);
	}
	ExeApi api = { stream_put, stream_get, stream_set, exe_cd, exe_now };
	init (&run, &api);
	int64_t (*entry)(int64_t, int64_t) =
		(int64_t (*)(int64_t, int64_t))(intptr_t)dlsym (h, "__hc_start");
	if (!entry) {
		error (cc, "#exe: no __hc_start in %s", sopath);
	}
	int64_t noargs = 0;
	entry (0, (int64_t)(intptr_t)&noargs);
	cleanup_pop (cc);
	dlclose (h);
	if (!cc->keep) {
		unlink (cpath);
		unlink (sopath);
		rmdir (dir);
	}
	*rest = run.stream;
	return sb_take (&run.out);
}
