/* radare - MIT - Copyright 2019-2026 - pancake */
/*
 * Copyright (c) 1987, 1993, 1994
 * The Regents of the University of California.  All rights reserved.
 * $Id: getopt.c,v 1.2 1998/01/21 22:27:05 billm Exp $ *
 */

#include "getopt.h"
#include <string.h>

#define	BADCH	(int)'?'
#define	BADARG	(int)':'
#define	EMSG	""

void r_getopt_init(RGetopt *opt, int argc, const char **argv, const char *ostr) {
	memset (opt, 0, sizeof (RGetopt));
	opt->ind = 1;
	opt->argc = argc;
	opt->argv = argv;
	opt->ostr = ostr;
}

int r_getopt_next(RGetopt *opt) {
	const char *oli;

	if (!opt->place) {
		opt->place = EMSG;
	}
	if (!*opt->place) {
		if (opt->ind >= opt->argc) {
			opt->place = EMSG;
			return -1;
		}
		opt->place = opt->argv[opt->ind];
		if (opt->done || *opt->place != '-' || !opt->place[1]) {
			opt->arg = opt->place;
			opt->place = EMSG;
			opt->ind++;
			return 1;
		}
		opt->place++;
		if (*opt->place == '-' && !opt->place[1]) {
			opt->ind++;
			opt->place = EMSG;
			opt->done = true;
			return r_getopt_next (opt);
		}
	}
	/* option letter okay? */
	if ((opt->opt = (int)*opt->place++) == (int)':' || !(oli = strchr (opt->ostr, opt->opt))) {
		if (!*opt->place) {
			opt->ind++;
		}
		return BADCH;
	}
	if (*++oli == ':') {
		if (*opt->place) {
			opt->arg = opt->place;
			opt->place = EMSG;
			opt->ind++;
		} else if (oli[1] == ':') {
			opt->arg = NULL;
			opt->place = EMSG;
			opt->ind++;
		} else {
			if (opt->argc <= ++opt->ind) {  /* no arg */
				opt->place = EMSG;
				return BADARG;
			}
			opt->arg = opt->argv[opt->ind];
			opt->place = EMSG;
			opt->ind++;
		}
	} else {
		opt->arg = NULL;
		if (!*opt->place) {
			opt->ind++;
		}
	}
	return opt->opt;
}
