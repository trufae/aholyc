/* aholyc repl — line-at-a-time loop over a growing session file.
 * Each line is appended to the session source and the whole file is rebuilt
 * and re-run via 'aholyc run'; since earlier statements replay on every run,
 * only the output past the previous run is shown.  A line that fails to
 * build or run is reported and not appended. */
#include "aholyc.h"
#include <spawn.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/wait.h>

extern char **environ;

/* run argv with stdout and stderr redirected into outpath */
static int run_capture(Aholyc *cc, char *const argv[], const char *outpath) {
	posix_spawn_file_actions_t fa;
	posix_spawn_file_actions_init (&fa);
	posix_spawn_file_actions_addopen (&fa, 1, outpath,
		O_WRONLY | O_CREAT | O_TRUNC, 0600);
	posix_spawn_file_actions_adddup2 (&fa, 1, 2);
	pid_t pid;
	int e = posix_spawnp (&pid, argv[0], &fa, NULL, argv, environ);
	posix_spawn_file_actions_destroy (&fa);
	if (e) {
		error (cc, "cannot execute %s: %s", argv[0], strerror (e));
	}
	int st = 0;
	if (waitpid (pid, &st, 0) < 0) {
		error (cc, "waitpid failed");
	}
	if (WIFEXITED (st)) {
		return WEXITSTATUS (st);
	}
	return WIFSIGNALED (st)? 128 + WTERMSIG (st): 1;
}

/* build and run the current session source; *out gets the combined output */
static int run_trial(Aholyc *cc, const char *argv0, StrBuf *src,
		const char *trial, const char *outfile, char **out) {
	write_file (cc, trial, src->data, src->len);
	char *rargv[] = { (char *)argv0, "run", (char *)trial, NULL };
	int rc = run_capture (cc, rargv, outfile);
	*out = read_source (cc, outfile);
	if (!*out) {
		*out = "";
	}
	return rc;
}

int repl_main(Aholyc *cc, const char *argv0, int argc, char **argv) {
	const char *path = NULL;
	for (int i = 0; i < argc; i++) {
		if (argv[i][0] == '-' || path) {
			error (cc, "usage: aholyc repl [file.HC]");
		}
		path = argv[i];
	}
	bool scratch = !path;
	if (scratch) {
		path = ".repl.HC";
	}
	StrBuf src;
	sb_init (&src, cc);
	char *trial = xasprintf (cc, "%s.tmp", path);
	char *outfile = xasprintf (cc, "%s.out", path);
	const char *lastout = "";
	size_t lastlen = 0;
	if (!scratch) {
		/* resume an existing session: its output is the new baseline */
		char *old = read_source (cc, path);
		if (old && *old) {
			sb_puts (&src, old);
			char *out;
			if (run_trial (cc, argv0, &src, trial, outfile, &out) == 0) {
				lastout = out;
				lastlen = strlen (out);
			} else {
				fprintf (stderr, "aholyc: warning: %s does not run cleanly:\n%s",
					path, out);
			}
		}
	}
	bool tty = isatty (0);
	if (tty) {
		printf ("aholyc repl: statements append to %s; Ctrl-D exits\n", path);
	}
	char *line = NULL;
	size_t lcap = 0;
	for (;;) {
		if (tty) {
			fputs ("HC> ", stdout);
			fflush (stdout);
		}
		ssize_t n = getline (&line, &lcap, stdin);
		if (n < 0) {
			break;
		}
		while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
			line[--n] = 0;
		}
		if (!line[strspn (line, " \t")]) {
			continue;
		}
		size_t keep = src.len;
		sb_puts (&src, line);
		sb_putc (&src, '\n');
		char *out;
		if (run_trial (cc, argv0, &src, trial, outfile, &out) == 0) {
			write_file (cc, path, src.data, src.len);
			/* earlier statements replayed: show only what this line added */
			fputs (strncmp (out, lastout, lastlen)? out: out + lastlen, stdout);
			lastout = out;
			lastlen = strlen (out);
		} else {
			src.len = keep;
			src.data[keep] = 0;
			fputs (out, stdout);
		}
	}
	free (line);
	if (tty) {
		putchar ('\n');
	}
	unlink (trial);
	unlink (outfile);
	if (scratch) {
		unlink (path);
	}
	return 0;
}
