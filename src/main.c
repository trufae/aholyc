/* aholyc — another Holy-C compiler driver.
 * Usage mirrors a normal C compiler: aholyc [options] file.HC ...
 */
#include "aholyc.h"
#include "getopt.h"
#include <unistd.h>
#include <sys/stat.h>

#define AHOLYC_VERSION "0.1.0"

bool aholyc_obj_mode = false;
bool aholyc_ctor_mode = false;
bool aholyc_verbose = false;
bool aholyc_keep = false;
bool aholyc_use_hints = true;
char *aholyc_ccflags[64];
int aholyc_nccflags = 0;

static void add_ccflag(char *flag) {
	if (aholyc_nccflags >= 64) {
		error ("too many -I/-L/-l flags");
	}
	aholyc_ccflags[aholyc_nccflags++] = flag;
}

static const Backend *backends[] = {
	&backend_ll,
	&backend_c,
	&backend_js,
	NULL
};

static void usage(int code) {
	printf ("usage: aholyc [options] [file.HC ... | -] [file.o ...]\n"
		"       aholyc run [options] <file.HC | -> [args...]   build and run\n"
		"       aholyc fmt [-w | -q] [file.HC ... | -]   format sources (doc/format.md)\n"
		"\n"
		"options:\n"
		"  -o <file>     output executable (default: a.out)\n"
		"  -b <backend>  code generator to use (default: llvm, fallback: c)\n"
		"  -c            compile into a relocatable object (.o), do not link\n"
		"  -S            emit backend source only, do not build an executable\n"
		"  -O<level>     optimization level passed to the toolchain (default -Os)\n"
		"  -I <dir>      add #include search directory (also passed to cc)\n"
		"  -L <dir>      add library search directory for the linker\n"
		"  -l <name>     link against a library (e.g. -lz)\n"
		"  -D name[=v]   predefine a macro\n"
		"  -fno-hints    ignore all source hints\n"
		"  -k            keep intermediate files\n"
		"  -V            verbose: show toolchain commands\n"
		"  -h            show this help\n"
		"  -v            show version\n"
		"\n"
		"stdin: '-' reads HolyC source from stdin; 'run' with no -o builds a\n"
		"scratch ./.a.out removed after the run; with -S, '-o -' writes the\n"
		"artifact to stdout\n"
		"\n"
		"backends:\n");
	for (int i = 0; backends[i]; i++) {
		printf ("  %-6s %s\n", backends[i]->name, backends[i]->descr);
	}
	exit (code);
}

static const Backend *find_backend(const char *name) {
	for (int i = 0; backends[i]; i++) {
		if (!strcmp (backends[i]->name, name)) {
			return backends[i];
		}
	}
	/* aliases */
	if (!strcmp (name, "llvm") || !strcmp (name, "ll") || !strcmp (name, "llvm-ir")) {
		return &backend_ll;
	}
	if (!strcmp (name, "javascript")) {
		return &backend_js;
	}
	return NULL;
}

int main(int argc, char **argv) {
	if (argc >= 2 && !strcmp (argv[1], "fmt")) {
		return fmt_main (argc - 2, argv + 2);
	}
	bool run = argc >= 2 && !strcmp (argv[1], "run");
	int argi = run? 2: 1;
	const char *outpath = NULL;
	const char *bname = NULL;
	const char *opt = "-Os";
	bool emit_only = false, keep = false, verbose = false;
	bool compile_obj = false;
	const char *inputs[64];
	int ninputs = 0;
	const char **defines = xcalloc ((size_t)argc, sizeof(*defines));
	int ndefines = 0;
	char **run_args = NULL;
	int nrunargs = 0;

	RGetopt go;
	r_getopt_init (&go, argc, (const char **)argv, "o:b:cSO::I:L:l:D:f:kVhv");
	go.ind = argi;
	for (;;) {
		int c = r_getopt_next (&go);
		if (c < 0) {
			break;
		}
		if (c == 1) {
			if (ninputs >= 64) {
				error ("too many input files");
			}
			inputs[ninputs++] = go.arg;
			if (run) {
				run_args = argv + go.ind;
				nrunargs = argc - go.ind;
				break;
			}
			continue;
		}
		switch (c) {
		case 'o':
			outpath = go.arg;
			break;
		case 'b':
			bname = go.arg;
			break;
		case 'c':
			compile_obj = true;
			break;
		case 'S':
			emit_only = true;
			break;
		case 'O':
			opt = go.arg? xasprintf ("-O%s", go.arg): "-O";
			break;
		case 'I':
			lex_add_include_dir (go.arg);
			add_ccflag (xasprintf ("-I%s", go.arg));
			break;
		case 'L':
		case 'l':
			add_ccflag (xasprintf ("-%c%s", c, go.arg));
			break;
		case 'D':
			defines[ndefines++] = go.arg;
			break;
		case 'f':
			if (strcmp (go.arg, "no-hints")) {
				error ("unknown option '-f%s' (try -h)", go.arg);
			}
			aholyc_use_hints = false;
			break;
		case 'k':
			keep = aholyc_keep = true;
			break;
		case 'V':
			verbose = aholyc_verbose = true;
			break;
		case 'h':
			usage (0);
		case 'v':
			printf ("aholyc %s — another Holy-C compiler\n", AHOLYC_VERSION);
			return 0;
		case ':':
			error ("-%c needs an argument", go.opt);
		default:
			error ("unknown option '-%c' (try -h)", go.opt);
		}
	}
	for (int i = 0; i < ndefines; i++) {
		const char *a = defines[i];
		char *eq = strchr (a, '=');
		if (eq) {
			char *name = xstrdup (a);
			name[eq - a] = 0;
			lex_define (name, eq + 1);
		} else {
			lex_define (a, "1");
		}
	}
	if (ninputs == 0) {
		usage (1);
	}
	if (run && (compile_obj || emit_only)) {
		error ("run cannot be combined with %s", compile_obj? "-c": "-S");
	}
	/* classify inputs: HolyC sources vs objects/archives for the linker */
	const char *sources[64], *objects[64];
	int nsrc = 0, nobj = 0;
	for (int i = 0; i < ninputs; i++) {
		size_t l = strlen (inputs[i]);
		if ((l > 2 && !strcmp (inputs[i] + l - 2, ".o")) ||
		    (l > 2 && !strcmp (inputs[i] + l - 2, ".a"))) {
			objects[nobj++] = inputs[i];
		} else {
			sources[nsrc++] = inputs[i];
		}
	}

	const Backend *be;
	if (bname) {
		be = find_backend (bname);
		if (!be) {
			error ("unknown backend '%s' (try -h)", bname);
		}
	} else {
		/* default: LLVM toolchain if present, else system C compiler */
		be = (have_cmd ("clang") || have_cmd ("llc"))? &backend_ll: &backend_c;
	}
	if (compile_obj && nobj > 0) {
		error ("cannot mix object files with -c");
	}
	if ((compile_obj || nobj > 0) && !be->build_obj && !emit_only) {
		error ("backend '%s' cannot produce object files", be->name);
	}
	if (nsrc == 0 && (compile_obj || emit_only)) {
		error ("no source files");
	}
	if (outpath && !strcmp (outpath, "-") && !emit_only) {
		error ("-o '-' (stdout) requires -S");
	}

	Program *prog = NULL;
	if (nsrc > 0) {
		/* prelude first so its macros exist, then user files in order */
		aholyc_obj_mode = compile_obj || nobj > 0;
		aholyc_ctor_mode = compile_obj;
		Token *toks = lex_string (prelude_hc, "<prelude>", NULL);
		for (int i = 0; i < nsrc; i++) {
			toks = token_join (toks, lex_file (sources[i]));
		}
		prog = parse (toks);
	}

	bool src_stdin = false;
	for (int i = 0; i < nsrc; i++) {
		src_stdin |= !strcmp (sources[i], "-");
	}

	/* stem of first source, for default -c/-S output names */
	char *stem = NULL;
	if (nsrc > 0) {
		const char *base = strrchr (sources[0], '/');
		base = base? base + 1: sources[0];
		if (!strcmp (base, "-")) {
			base = "stdin";
		}
		stem = xstrdup (base);
		char *dot = strrchr (stem, '.');
		if (dot && dot != stem) {
			*dot = 0;
		}
	}

	if (emit_only) {
		if (outpath && !strcmp (outpath, "-")) {
			be->emit (prog, stdout);
			if (fflush (stdout) != 0 || ferror (stdout)) {
				error ("writing to stdout failed");
			}
			return 0;
		}
		char *artifact = outpath? xstrdup (outpath):
			xasprintf ("%s%s", stem, be->ext);
		FILE *f = fopen (artifact, "w");
		if (!f) {
			error ("cannot write '%s'", artifact);
		}
		be->emit (prog, f);
		fclose (f);
		if (verbose) {
			fprintf (stderr, "aholyc: wrote %s\n", artifact);
		}
		return 0;
	}

	if (compile_obj) {
		/* -c: one relocatable object from the source group */
		if (!outpath) {
			outpath = xasprintf ("%s.o", stem);
		}
		char *artifact = xasprintf ("%s.aholyc%s", outpath, be->ext);
		FILE *f = fopen (artifact, "w");
		if (!f) {
			error ("cannot write '%s'", artifact);
		}
		be->emit (prog, f);
		fclose (f);
		int r = be->build_obj (artifact, outpath, opt, verbose, keep);
		if (!keep) {
			unlink (artifact);
		}
		if (r != 0) {
			error ("backend '%s' failed to build %s", be->name, outpath);
		}
		return 0;
	}

	/* stdin + run: hidden scratch binary, removed after the run */
	bool tmpout = false;
	if (!outpath) {
		tmpout = run && src_stdin;
		outpath = tmpout? ".a.out": "a.out";
	}
	int r;
	char *tmpobj = NULL;
	if (nobj == 0) {
		/* whole-program build (single translation unit) */
		char *artifact = xasprintf ("%s.aholyc%s", outpath, be->ext);
		FILE *f = fopen (artifact, "w");
		if (!f) {
			error ("cannot write '%s'", artifact);
		}
		be->emit (prog, f);
		fclose (f);
		r = be->build (artifact, outpath, opt, verbose, keep);
		if (!keep) {
			unlink (artifact);
		}
	} else {
		/* link mode: compile sources (if any) to a temp object, then
		 * link everything with the runtime, like a C compiler would */
		if (nsrc > 0) {
			char *artifact = xasprintf ("%s.aholyc%s", outpath, be->ext);
			tmpobj = xasprintf ("%s.aholyc.o", outpath);
			FILE *f = fopen (artifact, "w");
			if (!f) {
				error ("cannot write '%s'", artifact);
			}
			be->emit (prog, f);
			fclose (f);
			r = be->build_obj (artifact, tmpobj, opt, verbose, keep);
			if (!keep) {
				unlink (artifact);
			}
			if (r != 0) {
				error ("backend '%s' failed to build %s", be->name, tmpobj);
			}
		}
		/* write the runtime and link */
		char *rtpath = xasprintf ("%s.aholycrt.c", outpath);
		FILE *f = fopen (rtpath, "w");
		if (!f) {
			error ("cannot write '%s'", rtpath);
		}
		fputs ("#define HC_OBJECT_RUNTIME 1\n", f);
		if (nsrc > 0) {
			fputs ("#define HC_EXTERNAL_START 1\n", f);
		}
		fputs (rt_c_src, f);
		fclose (f);
		const char *cc = getenv ("CC");
		if (!cc || !*cc) {
			cc = have_cmd ("cc")? "cc": have_cmd ("clang")? "clang": "gcc";
		}
		char *argv[80];
		int n = 0;
		argv[n++] = (char *)cc;
		argv[n++] = (char *)opt;
		argv[n++] = "-fno-strict-aliasing";
		argv[n++] = "-w";
		argv[n++] = "-o";
		argv[n++] = (char *)outpath;
		if (tmpobj) {
			argv[n++] = tmpobj;
		}
		for (int i = 0; i < nobj; i++) {
			argv[n++] = (char *)objects[i];
		}
		argv[n++] = rtpath;
		for (int i = 0; i < aholyc_nccflags && n < 78; i++) {
			argv[n++] = aholyc_ccflags[i];
		}
		argv[n++] = "-lm";
		argv[n] = NULL;
		r = run_cmd (argv, verbose);
		if (!keep) {
			unlink (rtpath);
			if (tmpobj) {
				unlink (tmpobj);
			}
		}
	}
	if (r != 0) {
		error ("failed to build %s", outpath);
	}
	if (run) {
		char **rargv = xcalloc ((size_t)nrunargs + 2, sizeof(char *));
		char *abspath = strchr (outpath, '/')? xstrdup (outpath):
			xasprintf ("./%s", outpath);
		rargv[0] = abspath;
		for (int i = 0; i < nrunargs; i++) {
			rargv[i + 1] = run_args[i];
		}
		r = run_cmd (rargv, verbose);
		if (tmpout && !keep) {
			unlink (outpath);
		}
		return r;
	}
	return 0;
}
