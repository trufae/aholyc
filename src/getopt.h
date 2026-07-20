#ifndef R_GETOPT_H
#define R_GETOPT_H 1

#include <stdbool.h>

typedef struct r_getopt_t {
	bool done;
	int ind;
	int opt;
	const char *arg;
	const char *place;
	int argc;
	const char **argv;
	const char *ostr;
} RGetopt;

void r_getopt_init(RGetopt *go, int argc, const char **argv, const char *ostr);
int r_getopt_next(RGetopt *opt);

#endif
