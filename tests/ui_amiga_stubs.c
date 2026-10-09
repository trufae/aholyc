/* The model test must never invoke a native API without a live window. */
#include <stdlib.h>

void GT_SetGadgetAttrsA(void *gadget, void *window, void *requester, void *tags) {
	(void)gadget;
	(void)window;
	(void)requester;
	(void)tags;
	abort ();
}
