/* ahc utilities: diagnostics, memory, process spawning */
#include "ahc.h"
#include <unistd.h>
#include <sys/wait.h>

void error(const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	fprintf (stderr, "ahc: error: ");
	vfprintf (stderr, fmt, ap);
	fputc ('\n', stderr);
	va_end (ap);
	exit (1);
}

void error_tok(Token *tok, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	if (tok) {
		fprintf (stderr, "%s:%d: error: ", tok->file? tok->file: "?", tok->line);
	} else {
		fprintf (stderr, "ahc: error: ");
	}
	vfprintf (stderr, fmt, ap);
	fputc ('\n', stderr);
	va_end (ap);
	exit (1);
}

void warn_tok(Token *tok, const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	if (tok) {
		fprintf (stderr, "%s:%d: warning: ", tok->file? tok->file: "?", tok->line);
	} else {
		fprintf (stderr, "ahc: warning: ");
	}
	vfprintf (stderr, fmt, ap);
	fputc ('\n', stderr);
	va_end (ap);
}

void *xmalloc(size_t n) {
	void *p = malloc (n? n: 1);
	if (!p) {
		error ("out of memory");
	}
	return p;
}

void *xcalloc(size_t n, size_t m) {
	void *p = calloc (n? n: 1, m? m: 1);
	if (!p) {
		error ("out of memory");
	}
	return p;
}

char *xstrdup(const char *s) {
	char *p = xmalloc (strlen (s) + 1);
	strcpy (p, s);
	return p;
}

char *xasprintf(const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	char buf[4096];
	vsnprintf (buf, sizeof(buf), fmt, ap);
	va_end (ap);
	return xstrdup (buf);
}

/* slurp an entire source: a file path, or stdin when path is "-".
 * fread-based so pipes work too; returns NULL if the file cannot be opened. */
char *read_source(const char *path) {
	FILE *f = strcmp (path, "-")? fopen (path, "rb"): stdin;
	if (!f) {
		return NULL;
	}
	size_t cap = 1 << 16, len = 0;
	char *buf = xmalloc (cap);
	size_t n;
	while ((n = fread (buf + len, 1, cap - len - 1, f)) > 0) {
		len += n;
		if (cap - len < 2) {
			cap *= 2;
			buf = realloc (buf, cap);
			if (!buf) {
				error ("out of memory");
			}
		}
	}
	buf[len] = 0;
	if (f != stdin) {
		fclose (f);
	}
	return buf;
}

int run_cmd(char *const argv[], bool verbose) {
	if (verbose) {
		fprintf (stderr, "ahc: exec:");
		for (int i = 0; argv[i]; i++) {
			fprintf (stderr, " %s", argv[i]);
		}
		fputc ('\n', stderr);
	}
	pid_t pid = fork ();
	if (pid < 0) {
		error ("fork failed");
	}
	if (pid == 0) {
		execvp (argv[0], argv);
		fprintf (stderr, "ahc: cannot exec %s\n", argv[0]);
		_exit (127);
	}
	int st = 0;
	waitpid (pid, &st, 0);
	return WIFEXITED (st)? WEXITSTATUS (st): 1;
}

bool have_cmd(const char *name) {
	char *path = getenv ("PATH");
	if (!path) {
		return false;
	}
	char *copy = xstrdup (path);
	bool found = false;
	for (char *dir = strtok (copy, ":"); dir; dir = strtok (NULL, ":")) {
		char buf[1024];
		snprintf (buf, sizeof(buf), "%s/%s", dir, name);
		if (access (buf, X_OK) == 0) {
			found = true;
			break;
		}
	}
	free (copy);
	return found;
}
