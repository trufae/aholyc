/* ahc #exe{} — compile-time execution via dlopen (see doc/exe.md).
 *
 * A #exe block is compiled by the same lexer/parser/codegen as any
 * program, using the C backend, into a shared library that is
 * dlopened into the compiler process and run. Because it lives in
 * the compiler's address space it sees the compiler's internals
 * directly: the shim functions below are exported from the ahc
 * binary (linked -rdynamic) and resolve at dlopen time, and the
 * Token class declared in runtime/exe.hc mirrors struct Token from
 * ahc.h byte for byte, so blocks can inspect and mutate the live
 * token stream in place.
 */
#include "ahc.h"
#include <dlfcn.h>
#include <unistd.h>
#include <time.h>

static char *sbuf;      /* StreamPrint accumulator */
static size_t slen, scap;
static Token *stream;   /* tokens following the block being run */

/* ------------- API exported to #exe blocks (resolved at dlopen) */

void __StreamPutS(char *s);
Token *ExeStream(void);
void ExeStreamSet(Token *t);
int64_t Cd(char *path);
int64_t Now(void);

/* append one StreamPrint result; each one starts a fresh line so
 * injected directives (#define, nested #exe) are at start-of-line */
void __StreamPutS(char *s) {
	size_t n = s? strlen (s): 0;
	if (slen + n + 2 > scap) {
		scap = (scap? scap * 2: 256) + n;
		sbuf = realloc (sbuf, scap);
		if (!sbuf) {
			error ("out of memory");
		}
	}
	memcpy (sbuf + slen, s, n);
	slen += n;
	sbuf[slen++] = '\n';
	sbuf[slen] = 0;
}

/* the compiler's token stream right after the #exe block */
Token *ExeStream(void) {
	return stream;
}

/* replace the stream head: lets a block consume tokens it parsed */
void ExeStreamSet(Token *t) {
	stream = t;
}

int64_t Cd(char *path) {
	return path && chdir (path) == 0;
}

int64_t Now(void) {
	return (int64_t)time (NULL);
}

/* ------------------------------------------------------- driver */

/* Compile and run one #exe block. 'block' is its preprocessed body,
 * EOF-terminated; *rest is the stream after the block, which the
 * block may advance. Returns the text to splice into the stream. */
char *exe_run(Token *block, Token **rest) {
	static int seq;
	bool save_obj = ahc_obj_mode;
	ahc_obj_mode = false;

	/* a stand-alone program: runtime prelude, exe API, block body.
	 * The body is preprocessed last so the exe API macros apply. */
	Token *toks = lex_string (prelude_hc, "<prelude>", NULL);
	toks = token_join (toks, lex_string (exe_hc, "<exe-api>", NULL));
	toks = token_join (toks, lex_preprocess (block));

	stream = *rest;
	slen = 0;
	if (sbuf) {
		sbuf[0] = 0;
	}

	Program *p = parse (toks);
	ahc_obj_mode = save_obj;

	const char *tmp = getenv ("TMPDIR");
	if (!tmp || !*tmp) {
		tmp = "/tmp";
	}
	char *cpath = xasprintf ("%s/ahc-exe-%d-%d.c", tmp, (int)getpid (), seq);
	char *sopath = xasprintf ("%s/ahc-exe-%d-%d.so", tmp, (int)getpid (), seq);
	seq++;
	FILE *f = fopen (cpath, "w");
	if (!f) {
		error ("#exe: cannot write '%s'", cpath);
	}
	backend_c.emit (p, f);
	fclose (f);

	const char *cc = getenv ("CC");
	if (!cc || !*cc) {
		cc = have_cmd ("cc")? "cc": have_cmd ("clang")? "clang": "gcc";
	}
	char *argv[] = {
		(char *)cc, "-O0", "-w", "-fno-strict-aliasing", "-shared",
		"-fPIC", "-o", sopath, cpath, "-lm", NULL
	};
	if (run_cmd (argv, ahc_verbose) != 0) {
		error ("#exe: failed to build %s (kept for inspection)", cpath);
	}
	void *h = dlopen (sopath, RTLD_NOW | RTLD_LOCAL);
	if (!h) {
		error ("#exe: dlopen: %s (is ahc linked with -rdynamic?)", dlerror ());
	}
	void (*entry)(void) = (void (*)(void))(intptr_t)dlsym (h, "__hc_start");
	if (!entry) {
		error ("#exe: no __hc_start in %s", sopath);
	}
	entry ();
	dlclose (h);
	if (!ahc_keep) {
		unlink (cpath);
		unlink (sopath);
	}
	*rest = stream;
	return sbuf? sbuf: (char *)"";
}
