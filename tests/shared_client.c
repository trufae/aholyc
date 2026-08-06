#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef int64_t (*SharedAddFn)(int64_t);

int main(int argc, char **argv) {
	if (argc != 2) {
		return 1;
	}
	void *lib = dlopen (argv[1], RTLD_NOW | RTLD_LOCAL);
	if (!lib) {
		fprintf (stderr, "%s\n", dlerror ());
		return 1;
	}
	SharedAddFn add = (SharedAddFn)(intptr_t)dlsym (lib, "SharedAdd");
	if (!add) {
		fprintf (stderr, "%s\n", dlerror ());
		dlclose (lib);
		return 1;
	}
	printf ("SharedAdd(2)=%lld\n", (long long)add (2));
	dlclose (lib);
	return 0;
}
