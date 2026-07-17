/* mhc utilities: diagnostics, memory, process spawning */
#include "mhc.h"
#include <unistd.h>
#include <sys/wait.h>

void error(const char *fmt, ...) {
	va_list ap;
	va_start (ap, fmt);
	fprintf (stderr, "mhc: error: ");
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
		fprintf (stderr, "mhc: error: ");
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
		fprintf (stderr, "mhc: warning: ");
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

int run_cmd(char *const argv[], bool verbose) {
	if (verbose) {
		fprintf (stderr, "mhc: exec:");
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
		fprintf (stderr, "mhc: cannot exec %s\n", argv[0]);
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
