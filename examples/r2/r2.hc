// Minimal reusable radare2 core-plugin bindings for AHolyC.
//
// radare2's public plugin ABI is declared here because AHolyC cannot include
// its C headers. Keep the fields in the same order as RPluginMeta,
// RCorePlugin, RCorePluginSession, and RLibStruct. @align is important: C
// inserts padding after 32-bit fields, while ordinary HolyC classes are packed.

#ifndef AHOLYC_R2_HC
#define AHOLYC_R2_HC

#ifndef R2_VERSION
#error R2_VERSION must be supplied by the Makefile
#endif

#ifndef R2_ABIVERSION
#error R2_ABIVERSION must be supplied by the Makefile
#endif

#define R_LIB_TYPE_CORE 12
#define R_PLUGIN_STATUS_GOOD 4

/* @align */ class RPluginMeta
{
  U8 *name;
  U8 *desc;
  U8 *author;
  U8 *version;
  U8 *license;
  U8 *contact;
  U8 *copyright;
  I32 status;
};

/* @align */ class RCorePlugin
{
  RPluginMeta meta;
  U0 *init;
  U0 *fini;
  U0 *call;
};

// Prefix of RCore through the console pointer. Fields after cons are not
// needed by these bindings.
/* @align */ class RCore
{
  U0 *bin;
  U0 *config;
  U0 *prj;
  U64 addr;
  U64 prompt_addr;
  U32 blocksize;
  U32 blocksize_max;
  U8 *block;
  U0 *yank_buf;
  U64 yank_addr;
  Bool tmpseek;
  Bool vmode;
  /* @align */ U0 *cons;
};

/* @align */ class RCorePluginSession
{
  RCore *core;
  RCorePlugin *plugin;
  U0 *data;
};

/* @align */ class RLibStruct
{
  I32 type;
  U0 *data;
  U8 *version;
  U0 *free;
  U8 *pkgname;
  U32 abiversion;
};

extern U0 r_cons_println(U0 *cons, U8 *text);

public RLibStruct radare_plugin;

U0 R2CorePluginRegister(RCorePlugin *plugin, U8 *pkgname)
{
  radare_plugin.type = R_LIB_TYPE_CORE;
  radare_plugin.data = plugin;
  radare_plugin.version = R2_VERSION;
  radare_plugin.pkgname = pkgname;
  radare_plugin.abiversion = R2_ABIVERSION;
}

U0 R2ConsPrintln(RCorePluginSession *session, U8 *text)
{
  r_cons_println(session->core->cons, text);
}

#endif
