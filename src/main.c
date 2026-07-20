#include "aholyc.h"

int main(int argc, char **argv) {
	Aholyc *cc = aholyc_init ();
	if (!cc) return 1;
	int rc = aholyc_parseargv (cc, argc, argv);
	aholyc_fini (cc);
	return rc;
}
