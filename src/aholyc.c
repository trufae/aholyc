/* aholyc — another Holy-C compiler driver.
 * Usage mirrors a normal C compiler: aholyc [options] file.HC ...
 */
#include "aholyc.h"
#include "getopt.h"
#include <unistd.h>
#include <sys/stat.h>

#define AHOLYC_VERSION "0.1.0"

static void add_ccflag(Aholyc *cc, char *flag) {
	if (cc->nccflags >= 64) {
		error (cc, "too many -I/-L/-l flags");
	}
	cc->ccflags[cc->nccflags++] = flag;
}

static void add_define(Aholyc *cc, const char *arg) {
	char *name = xstrdup (cc, arg);
	char *value = strchr (name, '=');
	if (value) {
		*value++ = 0;
	}
	lex_define (cc, name, value? value: "1");
}

static const Backend *const backends[] = {
#if AHOLYC_BACKEND_LLVM
	&aholyc_i_backend_ll,
#endif
#if AHOLYC_BACKEND_C
	&aholyc_i_backend_c,
#endif
#if AHOLYC_BACKEND_JS
	&aholyc_i_backend_js,
#endif
	NULL
};

static int usage(int code) {
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
	return code;
}

static const Backend *find_backend(const char *name) {
	for (int i = 0; backends[i]; i++) {
		if (!strcmp (backends[i]->name, name)) {
			return backends[i];
		}
	}
	/* aliases */
#if AHOLYC_BACKEND_LLVM
	if (!strcmp (name, "llvm") || !strcmp (name, "ll") || !strcmp (name, "llvm-ir")) {
		return &aholyc_i_backend_ll;
	}
#endif
#if AHOLYC_BACKEND_JS
	if (!strcmp (name, "javascript")) {
		return &aholyc_i_backend_js;
	}
#endif
	return NULL;
}

static const Backend *default_backend(Aholyc *cc) {
#if AHOLYC_BACKEND_LLVM
	if (have_cmd (cc, "clang") || have_cmd (cc, "llc")) {
		return &aholyc_i_backend_ll;
	}
#endif
#if AHOLYC_BACKEND_C
	return &aholyc_i_backend_c;
#elif AHOLYC_BACKEND_LLVM
	return &aholyc_i_backend_ll;
#elif AHOLYC_BACKEND_JS
	return &aholyc_i_backend_js;
#else
	(void)cc;
	return NULL;
#endif
}

static void emit_file(Aholyc *cc, const Backend *be, Program *prog,
		const char *path, bool object_mode, bool ctor_mode) {
	StrBuf out;
	sb_init (&out, cc);
	be->emit (cc, prog, &out, object_mode, ctor_mode);
	write_file (cc, path, out.data, out.len);
}

static void build_source(Aholyc *cc, const Backend *be, Program *prog,
		const char *artifact, const char *out, const char *opt,
		bool object_mode, bool ctor_mode) {
	emit_file (cc, be, prog, artifact, object_mode, ctor_mode);
	int rc = (object_mode? be->build_obj: be->build) (cc, artifact, out, opt);
	if (!cc->keep) {
		unlink (artifact);
	}
	if (rc) {
		error (cc, "backend '%s' failed to build %s", be->name, out);
	}
}

static int parseargv(Aholyc *cc, int argc, char **argv) {
	if (argc >= 2 && !strcmp (argv[1], "fmt")) {
		return fmt_main (cc, argc - 2, argv + 2);
	}
	bool run = argc >= 2 && !strcmp (argv[1], "run");
	int argi = run? 2: 1;
	const char *outpath = NULL;
	const char *bname = NULL;
	const char *opt = "-Os";
	bool emit_only = false;
	bool compile_obj = false;
	const char *inputs[64];
	const char *defines[64];
	int ninputs = 0, ndefines = 0;
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
				error (cc, "too many input files");
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
		case 'o': outpath = go.arg; break;
		case 'b': bname = go.arg; break;
		case 'c': compile_obj = true; break;
		case 'S': emit_only = true; break;
		case 'O': opt = go.arg? xasprintf (cc, "-O%s", go.arg): "-O"; break;
		case 'I':
			lex_add_include_dir (cc, go.arg);
			add_ccflag (cc, xasprintf (cc, "-I%s", go.arg));
			break;
		case 'L':
		case 'l':
			add_ccflag (cc, xasprintf (cc, "-%c%s", c, go.arg));
			break;
		case 'D':
			if (ndefines >= 64) error (cc, "too many -D options");
			defines[ndefines++] = go.arg;
			break;
		case 'f':
			if (strcmp (go.arg, "no-hints")) {
				error (cc, "unknown option '-f%s' (try -h)", go.arg);
			}
			cc->use_hints = false;
			break;
		case 'k': cc->keep = true; break;
		case 'V': cc->verbose = true; break;
		case 'h': return usage (0);
		case 'v':
			printf ("aholyc %s — another Holy-C compiler\n", AHOLYC_VERSION);
			return 0;
		case ':':
			error (cc, "-%c needs an argument", go.opt);
			break;
		default:
			error (cc, "unknown option '-%c' (try -h)", go.opt);
		}
	}
	for (int i = 0; i < ndefines; i++) add_define (cc, defines[i]);
	if (ninputs == 0) {
		return usage (1);
	}
	if (run && (compile_obj || emit_only)) {
		error (cc, "run cannot be combined with %s", compile_obj? "-c": "-S");
	}
	/* classify inputs: HolyC sources vs objects/archives for the linker */
	const char *sources[64], *objects[64];
	int nsrc = 0, nobj = 0;
	bool src_stdin = false;
	for (int i = 0; i < ninputs; i++) {
		size_t l = strlen (inputs[i]);
		if ((l > 2 && !strcmp (inputs[i] + l - 2, ".o")) ||
		    (l > 2 && !strcmp (inputs[i] + l - 2, ".a"))) {
			objects[nobj++] = inputs[i];
		} else {
			sources[nsrc++] = inputs[i];
			src_stdin |= !strcmp (inputs[i], "-");
		}
	}

	const Backend *be;
	if (bname) {
		be = find_backend (bname);
		if (!be) {
			error (cc, "unknown backend '%s' (try -h)", bname);
		}
	} else {
		be = default_backend (cc);
		if (!be) {
			error (cc, "no compiler backends enabled; rebuild with AHOLYC_BACKEND_*=1");
		}
	}
	if (compile_obj && nobj > 0) {
		error (cc, "cannot mix object files with -c");
	}
	if ((compile_obj || nobj > 0) && !be->build_obj && !emit_only) {
		error (cc, "backend '%s' cannot produce object files", be->name);
	}
	if (nsrc == 0 && (compile_obj || emit_only)) {
		error (cc, "no source files");
	}
	if (outpath && !strcmp (outpath, "-") && !emit_only) {
		error (cc, "-o '-' (stdout) requires -S");
	}

	Program *prog = NULL;
	if (nsrc > 0) {
		/* prelude first so its macros exist, then user files in order */
		Token *toks = lex_string (cc, aholyc_i_prelude_hc, "<prelude>", NULL);
		for (int i = 0; i < nsrc; i++) {
			toks = token_join (toks, lex_file (cc, sources[i]));
		}
		prog = parse (cc, toks, strcmp (be->name, "js"));
	}

	/* stem of first source, for default -c/-S output names */
	char *stem = NULL;
	if (nsrc > 0) {
		const char *base = strrchr (sources[0], '/');
		base = base? base + 1: sources[0];
		if (!strcmp (base, "-")) {
			base = "stdin";
		}
		stem = xstrdup (cc, base);
		char *dot = strrchr (stem, '.');
		if (dot && dot != stem) {
			*dot = 0;
		}
	}

	if (emit_only) {
		if (outpath && !strcmp (outpath, "-")) {
			emit_file (cc, be, prog, "-", compile_obj || nobj > 0, compile_obj);
			return 0;
		}
		char *artifact = outpath? xstrdup (cc, outpath):
			xasprintf (cc, "%s%s", stem, be->ext);
		emit_file (cc, be, prog, artifact, compile_obj || nobj > 0, compile_obj);
		if (cc->verbose) {
			fprintf (stderr, "aholyc: wrote %s\n", artifact);
		}
		return 0;
	}

	if (compile_obj) {
		/* -c: one relocatable object from the source group */
		if (!outpath) {
			outpath = xasprintf (cc, "%s.o", stem);
		}
		char *artifact = xasprintf (cc, "%s.aholyc%s", outpath, be->ext);
		build_source (cc, be, prog, artifact, outpath, opt, true, true);
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
		char *artifact = xasprintf (cc, "%s.aholyc%s", outpath, be->ext);
		build_source (cc, be, prog, artifact, outpath, opt, false, false);
		r = 0;
	} else {
		/* link mode: compile sources (if any) to a temp object, then
		 * link everything with the runtime, like a C compiler would */
		if (nsrc > 0) {
			char *artifact = xasprintf (cc, "%s.aholyc%s", outpath, be->ext);
			tmpobj = xasprintf (cc, "%s.aholyc.o", outpath);
			build_source (cc, be, prog, artifact, tmpobj, opt, true, false);
		}
		/* write the runtime and link */
		char *rtpath = xasprintf (cc, "%s.aholycrt.c", outpath);
		StrBuf rt;
		sb_init (&rt, cc);
		sb_puts (&rt, "#define HC_OBJECT_RUNTIME 1\n");
		if (nsrc > 0) {
			sb_puts (&rt, "#define HC_EXTERNAL_START 1\n");
		}
		sb_puts (&rt, aholyc_i_rt_c_src);
		write_file (cc, rtpath, rt.data, rt.len);
		const char *link_inputs[66];
		int n = 0;
		if (tmpobj) link_inputs[n++] = tmpobj;
		for (int i = 0; i < nobj; i++) link_inputs[n++] = objects[i];
		link_inputs[n++] = rtpath;
		r = run_cc (cc, NULL, opt, outpath, link_inputs, n, false, false);
		if (!cc->keep) {
			unlink (rtpath);
			if (tmpobj) {
				unlink (tmpobj);
			}
		}
	}
	if (r != 0) {
		error (cc, "failed to build %s", outpath);
	}
	if (run) {
		char **rargv = xcalloc (cc, (size_t)nrunargs + 2, sizeof(char *));
		char *abspath = strchr (outpath, '/')? xstrdup (cc, outpath):
			xasprintf (cc, "./%s", outpath);
		rargv[0] = abspath;
		memcpy (rargv + 1, run_args, (size_t)nrunargs * sizeof(char *));
		r = run_cmd (cc, rargv);
		if (tmpout && !cc->keep) {
			unlink (outpath);
		}
		return r;
	}
	return 0;
}

int aholyc_parseargv(Aholyc *cc, int argc, char **argv) {
	cc->error[0] = 0;
	cc->error_active = true;
	int rc = 1;
	if (!setjmp (cc->error_jmp)) {
		lex_reset (cc);
		rc = parseargv (cc, argc, argv);
	}
	cc->error_active = false;
	return rc;
}
