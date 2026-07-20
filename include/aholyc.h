#ifndef AHOLYC_PUBLIC_H
#define AHOLYC_PUBLIC_H
typedef struct Aholyc Aholyc;
Aholyc *aholyc_init(void);
void aholyc_fini(Aholyc *cc);
int aholyc_parseargv(Aholyc *cc, int argc, char **argv);
const char *aholyc_error(const Aholyc *cc);

#endif
