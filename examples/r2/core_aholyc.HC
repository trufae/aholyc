#include "r2.hc"

Bool IsAholyCommand(U8 *input)
{
  if (!input || input[0] != 'a' || input[1] != 'h' || input[2] != 'c')
    return FALSE;
  return !input[3] || input[3] == '?' || input[3] == ' ' || input[3] == '\t';
}

Bool AholyCall(RCorePluginSession *session, U8 *input)
{
  if (!IsAholyCommand(input))
    return FALSE;
  if (input[3] == '?')
    R2ConsPrintln(session, "Usage: ahc   # say hello from AHolyC");
  else
    R2ConsPrintln(session, "Hello from a pure AHolyC core plugin!");
  return TRUE;
}

public RCorePlugin r_core_plugin_aholyc;

r_core_plugin_aholyc.meta.name = "core-aholyc";
r_core_plugin_aholyc.meta.desc = "AHolyC core plugin example";
r_core_plugin_aholyc.meta.author = "pancake";
r_core_plugin_aholyc.meta.license = "MIT";
r_core_plugin_aholyc.meta.status = R_PLUGIN_STATUS_GOOD;
r_core_plugin_aholyc.call = &AholyCall;

R2CorePluginRegister(&r_core_plugin_aholyc, "aholyc");
