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

void aholyc_i_error(Aholyc *cc, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	report (cc, NULL, "error", fmt, ap);
	va_end (ap);
	halt (cc);
}

void aholyc_i_error_tok(Aholyc *cc, Token *tok, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	report (cc, tok, "error", fmt, ap);
	va_end (ap);
	halt (cc);
}

typedef union AholyAlloc AholyAlloc;
union AholyAlloc { struct { AholyAlloc *next; } h; long double align; };

void *aholyc_i_xmalloc(Aholyc *cc, size_t n) {
	size_t size = n? n: 1;
	if (size > SIZE_MAX - sizeof(AholyAlloc)) aholyc_i_error (cc, "out of memory");
	AholyAlloc *a = malloc (sizeof(*a) + size);
	if (!a) aholyc_i_error (cc, "out of memory");
	a->h.next = cc->allocs;
	cc->allocs = a;
	return a + 1;
}

void *aholyc_i_xcalloc(Aholyc *cc, size_t n, size_t m) {
	if (m && n > SIZE_MAX / m) aholyc_i_error (cc, "out of memory");
	size_t size = n * m;
	return memset (aholyc_i_xmalloc (cc, size), 0, size);
}

char *aholyc_i_xstrdup(Aholyc *cc, const char *s) {
	size_t n = strlen (s) + 1;
	return memcpy (aholyc_i_xmalloc (cc, n), s, n);
}

char *aholyc_i_xasprintf(Aholyc *cc, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	int n = vsnprintf (NULL, 0, fmt, ap);
	va_end (ap);
	if (n < 0) {
		aholyc_i_error (cc, "string formatting failed");
	}
	char *buf = aholyc_i_xmalloc (cc, (size_t)n + 1);
	va_start (ap, fmt);
	vsnprintf (buf, (size_t)n + 1, fmt, ap);
	va_end (ap);
	return buf;
}

void aholyc_i_xfree_to(Aholyc *cc, void *mark) {
	while (cc->allocs != mark) {
		AholyAlloc *a = cc->allocs;
		cc->allocs = a->h.next;
		free (a);
	}
}

void aholyc_i_cleanup_push(Aholyc *cc, void (*fn)(void *), void *arg) {
	if (cc->ncleanups == 8) {
		fn (arg);
		aholyc_i_error (cc, "too many pending cleanups");
	}
	cc->cleanups[cc->ncleanups++] = (AholyCleanup){ fn, arg };
}

/* slurp an entire source: a file path, or stdin when path is "-".
 * fread-based so pipes work too; returns NULL if the file cannot be opened. */
char *aholyc_i_read_source(Aholyc *cc, const char *path) {
	FILE *f = strcmp (path, "-")? fopen (path, "rb"): stdin;
	if (!f) {
		return NULL;
	}
	if (f != stdin) aholyc_i_cleanup_push (cc, aholyc_i_cleanup_file, f);
	size_t cap = 1 << 16, len = 0;
	char *buf = aholyc_i_xmalloc (cc, cap);
	size_t n;
	while ((n = fread (buf + len, 1, cap - len - 1, f)) > 0) {
		len += n;
		if (cap - len < 2) {
			if (cap > SIZE_MAX / 2) aholyc_i_error (cc, "source is too large");
			cap *= 2;
			char *p = aholyc_i_xmalloc (cc, cap);
			memcpy (p, buf, len);
			buf = p;
		}
	}
	buf[len] = 0;
	if (f != stdin) {
		aholyc_i_cleanup_pop (cc);
		fclose (f);
	}
	return buf;
}

int aholyc_i_run_cmd(Aholyc *cc, char *const argv[]) {
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
		aholyc_i_error (cc, "cannot execute %s: %s", argv[0], strerror (e));
	}
	int st = 0;
	if (waitpid (pid, &st, 0) < 0) {
		aholyc_i_error (cc, "waitpid failed");
	}
	return WIFEXITED (st)? WEXITSTATUS (st): 1;
}

int aholyc_i_run_cc(Aholyc *cc, const char *tool, const char *opt, const char *out,
		const char *const inputs[], int ninputs, bool object, bool gc) {
	if (!tool || !*tool) {
		tool = getenv ("CC");
	}
	if (!tool || !*tool) {
		tool = aholyc_i_have_cmd (cc, "cc")? "cc": aholyc_i_have_cmd (cc, "clang")? "clang": "gcc";
	}
	char *argv[160];
	int n = 0;
	argv[n++] = (char *)tool; argv[n++] = (char *)opt;
	argv[n++] = "-w"; argv[n++] = "-fno-strict-aliasing";
	if (object) {
		argv[n++] = "-c";
	} else if (gc) {
		argv[n++] = "-ffunction-sections"; argv[n++] = "-fdata-sections";
#ifdef __APPLE__
		argv[n++] = "-Wl,-dead_strip";
#else
		argv[n++] = "-Wl,--gc-sections";
#endif
	}
	argv[n++] = "-o";
	argv[n++] = (char *)out;
	for (int i = 0; i < ninputs; i++) argv[n++] = (char *)inputs[i];
	for (int i = 0; i < cc->nccflags; i++) argv[n++] = cc->ccflags[i];
	if (!object) argv[n++] = "-lm";
	argv[n] = NULL;
	return aholyc_i_run_cmd (cc, argv);
}

bool aholyc_i_have_cmd(Aholyc *cc, const char *name) {
	char *path = getenv ("PATH");
	if (!path) return false;
	char *copy = aholyc_i_xstrdup (cc, path);
	char *save = NULL;
	for (char *dir = strtok_r (copy, ":", &save); dir;
		dir = strtok_r (NULL, ":", &save)) {
		char *file = aholyc_i_xasprintf (cc, "%s/%s", dir, name);
		bool found = access (file, X_OK) == 0;
		if (found) return true;
	}
	return false;
}
