/* mhc — modern HolyC compiler driver.
 * Usage mirrors a normal C compiler: mhc [options] file.HC ...
 */
#include "mhc.h"
#include <unistd.h>
#include <sys/stat.h>

#define MHC_VERSION "0.1.0"

bool mhc_obj_mode = false;
bool mhc_verbose = false;
bool mhc_keep = false;
char *mhc_ccflags[64];
int mhc_nccflags = 0;

static void add_ccflag(char *flag) {
	if (mhc_nccflags >= 64) {
		error ("too many -I/-L/-l flags");
	}
	mhc_ccflags[mhc_nccflags++] = flag;
}

static const Backend *backends[] = {
	&backend_ll,
	&backend_c,
	&backend_js,
	NULL
};

static void usage(int code) {
	printf ("usage: mhc [options] file.HC ... [file.o ...]\n"
		"       mhc fmt [-w | -q] [file.HC ... | -]   format sources (doc/format.md)\n"
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
		"  -r            run the program after building it\n"
		"  -k            keep intermediate files\n"
		"  -v            verbose: show toolchain commands\n"
		"  -h            show this help\n"
		"  --version     show version\n"
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
	const char *outpath = NULL;
	const char *bname = NULL;
	const char *opt = "-Os";
	bool emit_only = false, keep = false, verbose = false, run = false;
	bool compile_obj = false;
	const char *inputs[64];
	int ninputs = 0;

	for (int i = 1; i < argc; i++) {
		char *a = argv[i];
		if (a[0] != '-') {
			if (ninputs >= 64) {
				error ("too many input files");
			}
			inputs[ninputs++] = a;
			continue;
		}
		if (!strcmp (a, "-o")) {
			if (++i >= argc) {
				error ("-o needs an argument");
			}
			outpath = argv[i];
		} else if (!strcmp (a, "-b")) {
			if (++i >= argc) {
				error ("-b needs an argument");
			}
			bname = argv[i];
		} else if (!strcmp (a, "-c")) {
			compile_obj = true;
		} else if (!strcmp (a, "-S")) {
			emit_only = true;
		} else if (!strncmp (a, "-O", 2)) {
			opt = a;
		} else if (!strcmp (a, "-I")) {
			if (++i >= argc) {
				error ("-I needs an argument");
			}
			lex_add_include_dir (argv[i]);
			add_ccflag (xasprintf ("-I%s", argv[i]));
		} else if (!strncmp (a, "-I", 2)) {
			lex_add_include_dir (a + 2);
			add_ccflag (a);
		} else if (!strcmp (a, "-L") || !strcmp (a, "-l")) {
			if (++i >= argc) {
				error ("%s needs an argument", a);
			}
			add_ccflag (xasprintf ("%s%s", a, argv[i]));
		} else if (!strncmp (a, "-L", 2) || !strncmp (a, "-l", 2)) {
			add_ccflag (a);
		} else if (!strcmp (a, "-D")) {
			if (++i >= argc) {
				error ("-D needs an argument");
			}
			a = argv[i];
			goto def;
		} else if (!strncmp (a, "-D", 2)) {
			a += 2;
def:		{
			char *eq = strchr (a, '=');
			if (eq) {
				char *name = xstrdup (a);
				name[eq - a] = 0;
				lex_define (name, eq + 1);
			} else {
				lex_define (a, "1");
			}
		}
		} else if (!strcmp (a, "-r") || !strcmp (a, "--run")) {
			run = true;
		} else if (!strcmp (a, "-k")) {
			keep = mhc_keep = true;
		} else if (!strcmp (a, "-v")) {
			verbose = mhc_verbose = true;
		} else if (!strcmp (a, "-h") || !strcmp (a, "--help")) {
			usage (0);
		} else if (!strcmp (a, "--version")) {
			printf ("mhc %s — modern HolyC compiler\n", MHC_VERSION);
			return 0;
		} else {
			error ("unknown option '%s' (try -h)", a);
		}
	}
	if (ninputs == 0) {
		usage (1);
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

	Program *prog = NULL;
	if (nsrc > 0) {
		/* prelude first so its macros exist, then user files in order */
		mhc_obj_mode = compile_obj || nobj > 0;
		Token *toks = lex_string (prelude_hc, "<prelude>", NULL);
		for (int i = 0; i < nsrc; i++) {
			toks = token_join (toks, lex_file (sources[i]));
		}
		prog = parse (toks);
	}

	/* stem of first source, for default -c/-S output names */
	char *stem = NULL;
	if (nsrc > 0) {
		const char *base = strrchr (sources[0], '/');
		base = base? base + 1: sources[0];
		stem = xstrdup (base);
		char *dot = strrchr (stem, '.');
		if (dot && dot != stem) {
			*dot = 0;
		}
	}

	if (emit_only) {
		char *artifact = outpath? xstrdup (outpath):
			xasprintf ("%s%s", stem, be->ext);
		FILE *f = fopen (artifact, "w");
		if (!f) {
			error ("cannot write '%s'", artifact);
		}
		be->emit (prog, f);
		fclose (f);
		if (verbose) {
			fprintf (stderr, "mhc: wrote %s\n", artifact);
		}
		return 0;
	}

	if (compile_obj) {
		/* -c: one relocatable object from the source group */
		if (!outpath) {
			outpath = xasprintf ("%s.o", stem);
		}
		char *artifact = xasprintf ("%s.mhc%s", outpath, be->ext);
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

	if (!outpath) {
		outpath = "a.out";
	}
	int r;
	char *tmpobj = NULL;
	if (nobj == 0) {
		/* whole-program build (single translation unit) */
		char *artifact = xasprintf ("%s.mhc%s", outpath, be->ext);
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
			char *artifact = xasprintf ("%s.mhc%s", outpath, be->ext);
			tmpobj = xasprintf ("%s.mhc.o", outpath);
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
		char *rtpath = xasprintf ("%s.mhcrt.c", outpath);
		FILE *f = fopen (rtpath, "w");
		if (!f) {
			error ("cannot write '%s'", rtpath);
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
		for (int i = 0; i < mhc_nccflags && n < 78; i++) {
			argv[n++] = mhc_ccflags[i];
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
		if (r == 0 && have_cmd ("strip")) {
			char *sargv[] = { "strip", (char *)outpath, NULL };
			run_cmd (sargv, verbose);
		}
	}
	if (r != 0) {
		error ("failed to build %s", outpath);
	}
	if (run) {
		char *rargv[3];
		char *abspath = strchr (outpath, '/')? xstrdup (outpath):
			xasprintf ("./%s", outpath);
		rargv[0] = abspath;
		rargv[1] = NULL;
		return run_cmd (rargv, verbose);
	}
	return 0;
}
