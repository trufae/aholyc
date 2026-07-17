/* file2c: embed a file as a C char array. Usage: file2c symbol infile >> out.c */
#include <stdio.h>

int main(int argc, char **argv) {
	if (argc != 3) {
		fprintf (stderr, "usage: file2c <symbol> <file>\n");
		return 1;
	}
	FILE *f = fopen (argv[2], "rb");
	if (!f) {
		fprintf (stderr, "file2c: cannot open %s\n", argv[2]);
		return 1;
	}
	printf ("const char %s[] = {\n", argv[1]);
	int c, n = 0;
	while ((c = fgetc (f)) != EOF) {
		printf ("%d,", c);
		if (++n % 24 == 0) {
			printf ("\n");
		}
	}
	printf ("0};\n");
	fclose (f);
	return 0;
}
