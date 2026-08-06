#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef int64_t (*SharedAddFn)(int64_t);
typedef int64_t (*SharedDoubleFn)(void);

static void *open_lib(const char *path) {
	void *lib = dlopen (path, RTLD_NOW | RTLD_GLOBAL);
	if (!lib) {
		fprintf (stderr, "%s\n", dlerror ());
		return NULL;
	}
	/* Every shared library owns a hidden, dead-strippable runtime. */
	if (dlsym (lib, "__hc_register_start") || dlsym (lib, "__hc_try_push") ||
	    dlsym (lib, "Print")) {
		fprintf (stderr, "HolyC runtime symbol was exported\n");
		dlclose (lib);
		return NULL;
	}
	return lib;
}

int main(int argc, char **argv) {
	if (argc != 2 && argc != 3) {
		return 1;
	}
	void *lib = open_lib (argv[1]);
	if (!lib) {
		return 1;
	}
	SharedAddFn add = (SharedAddFn)(intptr_t)dlsym (lib, "SharedAdd");
	if (!add) {
		fprintf (stderr, "%s\n", dlerror ());
		dlclose (lib);
		return 1;
	}
	printf ("SharedAdd(2)=%lld\n", (long long)add (2));
	if (argc == 3) {
		void *second = open_lib (argv[2]);
		if (!second) {
			dlclose (lib);
			return 1;
		}
		SharedDoubleFn twice =
			(SharedDoubleFn)(intptr_t)dlsym (second, "SharedDouble");
		if (!twice) {
			fprintf (stderr, "%s\n", dlerror ());
			dlclose (second);
			dlclose (lib);
			return 1;
		}
		printf ("SharedDouble()=%lld\n", (long long)twice ());
		dlclose (second);
	}
	dlclose (lib);
	return 0;
}
