#include <aholyc.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
	const char *backend;
	const char *src;
	const char *inc;
	const char *cwd;
	const char *out;
	int value;
	int rc;
	bool build;
} Job;

static void write_file(const char *path, const char *text) {
	FILE *f = fopen (path, "w");
	if (!f || fputs (text, f) < 0 || fclose (f)) {
		fprintf (stderr, "cannot write %s\n", path);
		exit (1);
	}
}

static void write_limit_file(const char *path) {
	FILE *f = fopen (path, "w");
	if (!f) exit (1);
	for (int i = 0; i < 513; i++) {
		fprintf (f, "L%d: goto L%d;\n", i, (i + 1) % 513);
	}
	fclose (f);
}

static char *slurp(const char *path, size_t *size) {
	FILE *f = fopen (path, "rb");
	if (!f || fseek (f, 0, SEEK_END)) {
		return NULL;
	}
	long n = ftell (f);
	rewind (f);
	char *s = malloc ((size_t)n + 1);
	if (!s || fread (s, 1, (size_t)n, f) != (size_t)n) {
		free (s);
		s = NULL;
	} else {
		s[n] = 0;
		*size = (size_t)n;
	}
	fclose (f);
	return s;
}

static int same_file(const char *a, const char *b) {
	size_t na = 0, nb = 0;
	char *sa = slurp (a, &na), *sb = slurp (b, &nb);
	int same = sa && sb && na == nb && !memcmp (sa, sb, na);
	free (sa);
	free (sb);
	return same;
}

static void *compile_job(void *arg) {
	Job *j = arg;
	char value[32], workdir[1024];
	snprintf (value, sizeof(value), "VALUE=%d", j->value);
	snprintf (workdir, sizeof(workdir), "WORKDIR=\"%s\"", j->cwd);
	char *argv[16] = { "aholyc", "-b", (char *)j->backend };
	int argc = 3;
	if (!j->build) argv[argc++] = "-S";
	argv[argc++] = "-o"; argv[argc++] = (char *)j->out;
	argv[argc++] = "-I"; argv[argc++] = (char *)j->inc;
	argv[argc++] = "-D"; argv[argc++] = value;
	argv[argc++] = "-D"; argv[argc++] = workdir;
	argv[argc++] = (char *)j->src;
	Aholyc *cc = aholyc_init ();
	j->rc = aholyc_parseargv (cc, argc, argv);
	if (j->rc) {
		fprintf (stderr, "library compile failed: %s\n", aholyc_error (cc));
	}
	aholyc_fini (cc);
	return NULL;
}

static void compile_pair(Job *a, Job *b) {
	pthread_t ta, tb;
	pthread_create (&ta, NULL, compile_job, a);
	pthread_create (&tb, NULL, compile_job, b);
	pthread_join (ta, NULL);
	pthread_join (tb, NULL);
}

static void path(char *out, size_t n, const char *dir, const char *name) {
	snprintf (out, n, "%s/%s", dir, name);
}

int main(void) {
	char root[] = "/tmp/aholyc-instances-XXXXXX";
	if (!mkdtemp (root)) {
		return 1;
	}
	char dira[1024], dirb[1024], src[1024], invalid[1024], limit[1024];
	path (dira, sizeof(dira), root, "a");
	path (dirb, sizeof(dirb), root, "b");
	path (src, sizeof(src), root, "input.HC");
	path (invalid, sizeof(invalid), root, "invalid.HC");
	path (limit, sizeof(limit), root, "limit.HC");
	mkdir (dira, 0700);
	mkdir (dirb, 0700);
	char p[1024];
	path (p, sizeof(p), dira, "extra.HC");
	write_file (p, "I64 extra=101;\n");
	path (p, sizeof(p), dirb, "extra.HC");
	write_file (p, "I64 extra=202;\n");
	path (p, sizeof(p), dira, "chosen.HC");
	write_file (p, "I64 chosen=111;\n");
	path (p, sizeof(p), dirb, "chosen.HC");
	write_file (p, "I64 chosen=222;\n");
	write_file (src,
		"#ifdef STALE\nI64 = ;\n#endif\n"
		"#include \"extra.HC\"\n"
		"#exe {\n"
		"#exe { StreamPrint(\"I64 nested=7;\"); }\n"
		"Cd(WORKDIR); Token *t=ExeStream();\n"
		"StreamPrint(\"#include \\\"chosen.HC\\\"\");\n"
		"StreamPrint(\"I64 direct=%s+%d;\",t->next->str,nested);\n"
		"ExeStreamSet(t->next->next->next); }\n"
		"consume VALUE;\n");
	write_file (invalid, "#define STALE\nI64 = ;\n");
	write_limit_file (limit);

	char before[1024], after[1024];
	getcwd (before, sizeof(before));
	const char *backends[] = { "c", "llvm", "js" };
	for (int i = 0; i < 3; i++) {
		char ba[1024], bb[1024], oa[1024], ob[1024];
		snprintf (ba, sizeof(ba), "%s/base-a-%s", root, backends[i]);
		snprintf (bb, sizeof(bb), "%s/base-b-%s", root, backends[i]);
		snprintf (oa, sizeof(oa), "%s/out-a-%s", root, backends[i]);
		snprintf (ob, sizeof(ob), "%s/out-b-%s", root, backends[i]);
		Job a = { backends[i], src, dira, dira, ba, 11, 0, false };
		Job b = { backends[i], src, dirb, dirb, bb, 22, 0, false };
		compile_job (&a);
		compile_job (&b);
		a.out = oa;
		b.out = ob;
		compile_pair (&a, &b);
		if (a.rc || b.rc || !same_file (ba, oa) || !same_file (bb, ob)) {
			fprintf (stderr, "instance isolation failed for %s\n", backends[i]);
			return 1;
		}
	}
	char bina[1024], binb[1024];
	path (bina, sizeof(bina), root, "full-a");
	path (binb, sizeof(binb), root, "full-b");
	Job fulla = { "c", src, dira, dira, bina, 33, 0, true };
	Job fullb = { "c", src, dirb, dirb, binb, 44, 0, true };
	compile_pair (&fulla, &fullb);
	if (fulla.rc || fullb.rc || access (bina, X_OK) || access (binb, X_OK)) {
		fprintf (stderr, "concurrent full builds failed\n");
		return 1;
	}
	getcwd (after, sizeof(after));
	if (strcmp (before, after)) {
		fprintf (stderr, "#exe Cd changed the host working directory\n");
		return 1;
	}

	char badout[1024], limitout[1024], goodout[1024], goodbin[1024];
	path (badout, sizeof(badout), root, "bad.c");
	path (limitout, sizeof(limitout), root, "limit.js");
	path (goodout, sizeof(goodout), root, "good.c");
	path (goodbin, sizeof(goodbin), root, "good");
	char *badargv[] = { "aholyc", "-b", "c", "-S", "-o", badout, invalid };
	char *fmtargv[] = { "aholyc", "fmt", badout };
	char *limitargv[] = { "aholyc", "-b", "js", "-S", "-o", limitout, limit };
	char *goodargv[] = { "aholyc", "-b", "c", "-S", "-o", goodout, src,
		"-I", dira, "-D", "VALUE=11", "-D", "WORKDIR=\".\"",
		"-l", "__aholyc_missing" };
	char *buildargv[] = { "aholyc", "-b", "c", "-o", goodbin, src,
		"-I", dira, "-D", "VALUE=11", "-D", "WORKDIR=\".\"" };
	Aholyc *cc = aholyc_init ();
	int fmtbad = aholyc_parseargv (cc, 3, fmtargv);
	bool fmterr = fmtbad && strstr (aholyc_error (cc), "fmt: cannot open");
	int bad = aholyc_parseargv (cc, 7, badargv);
	int limited = aholyc_parseargv (cc, 7, limitargv);
	if (!fmterr || !bad || !limited || !strstr (aholyc_error (cc), "js backend: too many") ||
		aholyc_parseargv (cc, 15, goodargv)) {
		fprintf (stderr, "library error recovery failed\n");
		return 1;
	}
	if (aholyc_parseargv (cc, 12, buildargv) || system (goodbin)) {
		fprintf (stderr, "library success reset/full build failed: %s\n", aholyc_error (cc));
		return 1;
	}
	aholyc_fini (cc);
	puts ("ok   compiler instances/library");
	return 0;
}
