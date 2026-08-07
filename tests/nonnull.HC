/* @nonnull */ U8 *Identity(/* @nonnull */ U8 *p)
{
	if (p == NULL)
		"unreachable\n";
	return p;
}

U0 Main()
{
	U8 text[3] = "ok";
	/* @nonnull */ U8 *p = text;
	"%s\n", Identity(p);
}

Main;
