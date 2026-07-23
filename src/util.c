/* aholyc utilities: diagnostics, memory, process spawning */
#include "aholyc.h"
#include <unistd.h>
#include <sys/wait.h>
#include <spawn.h>

extern char **environ;

const char *aholyc_error(const Aholyc *cc) {
	return cc->error;
}

static void report(Aholyc *cc, Token *tok, const char *level,
		const char *fmt, va_list ap) {
	char msg[768];
	vsnprintf (msg, sizeof(msg), fmt, ap);
	if (tok) {
		snprintf (cc->error, sizeof(cc->error), "%s:%d: %s: %s",
			tok->file? tok->file: "?", tok->line, level, msg);
	} else {
		snprintf (cc->error, sizeof(cc->error), "aholyc: %s: %s", level, msg);
	}
	if (cc->diagnostics) {
		fprintf (cc->diagnostics, "%s\n", cc->error);
	}
}

static void cleanup_all(Aholyc *cc) {
	while (cc->ncleanups) {
		AholyCleanup *c = &cc->cleanups[--cc->ncleanups];
		c->fn (c->arg);
	}
}

static void halt(Aholyc *cc) {
	cleanup_all (cc);
	if (cc->error_active) longjmp (cc->error_jmp, 1);
	exit (1);
}

void error(Aholyc *cc, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	report (cc, NULL, "error", fmt, ap);
	va_end (ap);
	halt (cc);
}

void error_tok(Aholyc *cc, Token *tok, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	report (cc, tok, "error", fmt, ap);
	va_end (ap);
	halt (cc);
}

typedef union AholyAlloc AholyAlloc;
union AholyAlloc { struct { AholyAlloc *next; } h; long double align; };

void *xmalloc(Aholyc *cc, size_t n) {
	size_t size = n? n: 1;
	if (size > SIZE_MAX - sizeof(AholyAlloc)) error (cc, "out of memory");
	AholyAlloc *a = malloc (sizeof(*a) + size);
	if (!a) error (cc, "out of memory");
	a->h.next = cc->allocs;
	cc->allocs = a;
	return a + 1;
}

void *xcalloc(Aholyc *cc, size_t n, size_t m) {
	if (m && n > SIZE_MAX / m) error (cc, "out of memory");
	size_t size = n * m;
	return memset (xmalloc (cc, size), 0, size);
}

char *xstrdup(Aholyc *cc, const char *s) {
	size_t n = strlen (s) + 1;
	return memcpy (xmalloc (cc, n), s, n);
}

char *xasprintf(Aholyc *cc, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	int n = vsnprintf (NULL, 0, fmt, ap);
	va_end (ap);
	if (n < 0) {
		error (cc, "string formatting failed");
	}
	char *buf = xmalloc (cc, (size_t)n + 1);
	va_start (ap, fmt);
	vsnprintf (buf, (size_t)n + 1, fmt, ap);
	va_end (ap);
	return buf;
}

void xfree_to(Aholyc *cc, void *mark) {
	while (cc->allocs != mark) {
		AholyAlloc *a = cc->allocs;
		cc->allocs = a->h.next;
		free (a);
	}
}

void cleanup_push(Aholyc *cc, void (*fn)(void *), void *arg) {
	if (cc->ncleanups == 8) {
		fn (arg);
		error (cc, "too many pending cleanups");
	}
	cc->cleanups[cc->ncleanups++] = (AholyCleanup){ fn, arg };
}

/* slurp an entire source: a file path, or stdin when path is "-".
 * fread-based so pipes work too; returns NULL if the file cannot be opened. */
char *read_source(Aholyc *cc, const char *path) {
	FILE *f = strcmp (path, "-")? fopen (path, "rb"): stdin;
	if (!f) {
		return NULL;
	}
	if (f != stdin) cleanup_push (cc, cleanup_file, f);
	size_t cap = 1 << 16, len = 0;
	char *buf = xmalloc (cc, cap);
	size_t n;
	while ((n = fread (buf + len, 1, cap - len - 1, f)) > 0) {
		len += n;
		if (cap - len < 2) {
			if (cap > SIZE_MAX / 2) error (cc, "source is too large");
			cap *= 2;
			char *p = xmalloc (cc, cap);
			memcpy (p, buf, len);
			buf = p;
		}
	}
	buf[len] = 0;
	if (f != stdin) {
		cleanup_pop (cc);
		fclose (f);
	}
	return buf;
}

/* Write a complete buffer after its producer has succeeded. A path of "-"
 * denotes stdout, matching source input and -S output handling. */
void write_file(Aholyc *cc, const char *path,
		const char *data, size_t len) {
	bool to_stdout = !strcmp (path, "-");
	FILE *f = to_stdout? stdout: fopen (path, "wb");
	if (!f) {
		error (cc, "cannot write '%s'", path);
	}
	if (!to_stdout) {
		cleanup_push (cc, cleanup_file, f);
	}
	bool failed = fwrite (data, 1, len, f) != len;
	if (to_stdout) {
		failed |= fflush (f) != 0 || ferror (f);
	} else {
		cleanup_pop (cc);
		failed |= fclose (f) != 0;
	}
	if (failed) {
		if (to_stdout) {
			error (cc, "writing to stdout failed");
		}
		error (cc, "writing '%s' failed", path);
	}
}

int run_cmd(Aholyc *cc, char *const argv[]) {
	if (cc->verbose) {
		fprintf (stderr, "aholyc: exec:");
		for (int i = 0; argv[i]; i++) {
			fprintf (stderr, " %s", argv[i]);
		}
		fputc ('\n', stderr);
	}
	pid_t pid;
	int e = posix_spawnp (&pid, argv[0], NULL, NULL, argv, environ);
	if (e) {
		error (cc, "cannot execute %s: %s", argv[0], strerror (e));
	}
	int st = 0;
	if (waitpid (pid, &st, 0) < 0) {
		error (cc, "waitpid failed");
	}
	return WIFEXITED (st)? WEXITSTATUS (st): 1;
}

void arg_push(Aholyc *cc, Argv *a, const char *s) {
	if (a->n == a->cap) {
		char **v = xmalloc (cc, (a->cap += 32) * sizeof (char *));
		if (a->n) memcpy (v, a->v, (size_t)a->n * sizeof (char *));
		a->v = v;
	}
	a->v[a->n++] = (char *)s;
}

/* the space-separated words of $name (make-style CFLAGS/LDFLAGS) */
static void arg_push_env(Aholyc *cc, Argv *a, const char *name) {
	char *w = getenv (name);
	for (w = w? xstrdup (cc, w): NULL; w && *w; ) {
		if (*w == ' ') { w++; continue; }
		arg_push (cc, a, w);
		if ((w = strchr (w, ' '))) *w++ = 0;
	}
}

int run_cc(Aholyc *cc, const char *tool, const char *opt, const char *out,
		const char *const inputs[], int ninputs, bool object, bool gc) {
	if (!tool || !*tool) {
		tool = getenv ("CC");
	}
	if (!tool || !*tool) {
		tool = have_cmd (cc, "cc")? "cc": have_cmd (cc, "clang")? "clang": "gcc";
	}
	Argv a = { 0 };
	arg_push (cc, &a, tool); arg_push (cc, &a, opt);
	arg_push (cc, &a, "-w"); arg_push (cc, &a, "-fno-strict-aliasing");
	if (object) {
		arg_push (cc, &a, "-c");
	} else if (gc) {
		arg_push (cc, &a, "-ffunction-sections");
		arg_push (cc, &a, "-fdata-sections");
#ifdef __APPLE__
		arg_push (cc, &a, "-Wl,-dead_strip");
#else
		arg_push (cc, &a, "-Wl,--gc-sections");
#endif
	}
	arg_push_env (cc, &a, "CFLAGS");
	arg_push (cc, &a, "-o"); arg_push (cc, &a, out);
	for (int i = 0; i < ninputs; i++) arg_push (cc, &a, inputs[i]);
	for (int i = 0; i < cc->ccflags.n; i++) arg_push (cc, &a, cc->ccflags.v[i]);
	if (!object) {
		arg_push_env (cc, &a, "LDFLAGS");
		arg_push (cc, &a, "-lm");
	}
	arg_push (cc, &a, NULL);
	return run_cmd (cc, a.v);
}

bool have_cmd(Aholyc *cc, const char *name) {
	char *path = getenv ("PATH");
	if (!path) return false;
	char *copy = xstrdup (cc, path);
	char *save = NULL;
	for (char *dir = strtok_r (copy, ":", &save); dir;
		dir = strtok_r (NULL, ":", &save)) {
		char *file = xasprintf (cc, "%s/%s", dir, name);
		bool found = access (file, X_OK) == 0;
		if (found) return true;
	}
	return false;
}
