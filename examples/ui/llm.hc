// llm.hc — chat with LLMs from HolyC: every window is one conversation with
// its own endpoint, model and settings; requests run on a worker thread so
// the UI never blocks.
//
//   ./aholyc run examples/ui/llm.hc                (native backend)
//   ./aholyc run -DUI_HTK examples/ui/llm.hc       (terminal backend)
//
// Chat menu: new window, clear, save transcript. Settings menu: provider and
// URL (http or https), model, API key, reasoning effort, temperature and
// system prompt. New windows start from LLM_URL, LLM_MODEL and
// OPENAI_API_KEY when those environment variables are set.

#include "../../lib/ui/ui.hc"
#include "../../lib/llm/llm.hc"
#include "../../lib/io/file.hc"
#include "../../lib/thread/thread.hc"

extern U8 *getenv(U8 *name);

#define REASONING_COUNT 4
U8 *reasoning_names[REASONING_COUNT] = {"none", "low", "medium", "high"};

#define PROVIDER_COUNT 5
U8 *provider_names[PROVIDER_COUNT] = {"OpenAI", "OpenAI Responses", "Ollama",
    "llama.cpp", "OpenRouter"};
U8 *provider_urls[PROVIDER_COUNT] = {
  "https://api.openai.com/v1/chat/completions",
  "https://api.openai.com/v1/responses",
  "http://127.0.0.1:11434/v1/chat/completions",
  "http://127.0.0.1:8080/v1/chat/completions",
  "https://openrouter.ai/api/v1/chat/completions"};
U8 *provider_models[PROVIDER_COUNT] = {"gpt-4o-mini", "gpt-4o-mini",
    "gpt-oss:20b", "default", "openai/gpt-4o-mini"};

#define MODEL_COUNT 8
U8 *model_names[MODEL_COUNT] = {"gpt-4o-mini", "gpt-4o", "gpt-4.1", "o4-mini",
    "gpt-5", "gpt-oss:20b", "llama3.1", "qwen2.5"};

class Chat
{
  Chat *next;
  CLlm llm;
  U8 *url, *model, *key, *system;  // heap; CLlm borrows url and model
  I64 reasoning, temperature;      // index into reasoning_names, tenths
  CStrBuf transcript;
  UiCtl *win, *log, *entry, *send, *status;
  // settings window
  UiCtl *dlg, *provider, *url_entry, *preset, *model_entry, *key_entry;
  UiCtl *reasoning_combo, *temperature_spin, *system_entry;
  // worker thread
  CThread thread;
  Bool busy, done;
  U8 *reply;
};

Chat *chats;

U0 ChatStatus(Chat *chat, U8 *text)
{
  UiStatusSet(chat->status, text);
}

U0 ChatAppend(Chat *chat, U8 *who, U8 *text)
{
  StrBufPrintf(&chat->transcript, "%s: %s\n\n", who, text);
  UiMultilineSetText(chat->log, chat->transcript.a);
}

// (Re)configure the client from the settings; starts a fresh conversation.
U0 ChatConfigure(Chat *chat)
{
  U8 *json;

  LlmFini(&chat->llm);
  LlmInit(&chat->llm, chat->url, chat->model, chat->key);
  LlmSystem(&chat->llm, chat->system);
  json = MStrPrint("%d.%d", chat->temperature / 10, chat->temperature % 10);
  LlmSet(&chat->llm, "temperature", json);
  Free(json);
  if (chat->reasoning) {
    if (chat->llm.responses)
      json = MStrPrint("{\"effort\":\"%s\"}", reasoning_names[chat->reasoning]);
    else
      json = MStrPrint("\"%s\"", reasoning_names[chat->reasoning]);
    if (chat->llm.responses)
      LlmSet(&chat->llm, "reasoning", json);
    else
      LlmSet(&chat->llm, "reasoning_effort", json);
    Free(json);
  }
  json = MStrPrint("%s @ %s", chat->model, chat->url);
  ChatStatus(chat, json);
  Free(json);
}

// Worker thread: the only code touching chat->llm while chat->busy is set.
U0 ChatWorker(U8 *data)
{
  Chat *chat = data;

  chat->reply = LlmSend(&chat->llm);
  chat->done = TRUE;
}

U0 OnSend(UiCtl *c, U0 *data)
{
  Chat *chat = data;
  U8 *text = UiEntryText(chat->entry);

  if (chat->busy || !*text) {
    Free(text);
    return;
  }
  UiEntrySetText(chat->entry, "");
  ChatAppend(chat, "You", text);
  LlmMessage(&chat->llm, "user", text);
  Free(text);
  chat->busy = TRUE;
  chat->done = FALSE;
  UiEnable(chat->send, FALSE);
  ChatStatus(chat, "Thinking...");
  ThreadCreate(&chat->thread, &ChatWorker, chat);
}

// UI-thread poll: collect finished replies from every window's worker.
U0 ChatCollect(UiCtl *c, U0 *data)
{
  Chat *chat = chats;
  U8 *text;

  while (chat) {
    if (chat->busy && chat->done) {
      ThreadJoin(&chat->thread);
      chat->busy = FALSE;
      UiEnable(chat->send, TRUE);
      if (chat->reply) {
        ChatAppend(chat, "Assistant", chat->reply);
        text = MStrPrint("%d in / %d out tokens", chat->llm.input_tokens,
          chat->llm.output_tokens);
      } else {
        ChatAppend(chat, "Error", chat->llm.error);
        text = StrNew(chat->llm.error);
      }
      ChatStatus(chat, text);
      Free(text);
      Free(chat->reply);
      chat->reply = NULL;
    }
    chat = chat->next;
  }
}

U0 OnClear(UiCtl *c, U0 *data)
{
  Chat *chat = data;

  if (chat->busy)
    return;
  StrBufClear(&chat->transcript);
  UiMultilineSetText(chat->log, "");
  ChatConfigure(chat);
}

U0 OnSave(UiCtl *c, U0 *data)
{
  Chat *chat = data;
  U8 *path = UiPrompt("Save transcript", "File name:", "chat.txt");

  if (!path)
    return;
  if (FileWrite(path, chat->transcript.a))
    ChatStatus(chat, "Transcript saved");
  else
    UiWarnBox("Save transcript", "Could not write the file");
  Free(path);
}

U0 SetHeap(U8 **slot, U8 *text)
{
  Free(*slot);
  *slot = StrNew(text);
}

U0 OnProvider(UiCtl *c, U0 *data)
{
  Chat *chat = data;
  I64 i = UiComboSelected(chat->provider);

  if (i < 0)
    return;
  UiEntrySetText(chat->url_entry, provider_urls[i]);
  UiEntrySetText(chat->model_entry, provider_models[i]);
}

U0 OnPreset(UiCtl *c, U0 *data)
{
  Chat *chat = data;
  I64 i = UiComboSelected(chat->preset);

  if (i >= 0)
    UiEntrySetText(chat->model_entry, model_names[i]);
}

U0 OnApply(UiCtl *c, U0 *data)
{
  Chat *chat = data;
  U8 *text;

  if (chat->busy) {
    UiWarnBox("Settings", "Wait for the current reply first");
    return;
  }
  text = UiEntryText(chat->url_entry);
  SetHeap(&chat->url, text);
  Free(text);
  text = UiEntryText(chat->model_entry);
  SetHeap(&chat->model, text);
  Free(text);
  text = UiEntryText(chat->key_entry);
  SetHeap(&chat->key, text);
  Free(text);
  text = UiEntryText(chat->system_entry);
  SetHeap(&chat->system, text);
  Free(text);
  chat->reasoning = UiComboSelected(chat->reasoning_combo);
  if (chat->reasoning < 0)
    chat->reasoning = 0;
  chat->temperature = UiSpinValue(chat->temperature_spin);
  StrBufClear(&chat->transcript);
  UiMultilineSetText(chat->log, "");
  ChatConfigure(chat);
  UiWindowClose(chat->dlg);
  chat->dlg = NULL;
}

U0 OnSettings(UiCtl *c, U0 *data)
{
  Chat *chat = data;
  UiCtl *grid, *row, *apply;
  I64 i;

  chat->dlg = UiWindowNew("LLM settings", 520, 420);
  grid = UiGridNew;
  UiGridAdd(grid, UiLabelNew("Provider"), 0, 0);
  chat->provider = UiComboNew;
  for (i = 0; i < PROVIDER_COUNT; i++)
    UiComboAdd(chat->provider, provider_names[i]);
  UiOnChange(chat->provider, &OnProvider, chat);
  UiGridAdd(grid, chat->provider, 1, 0);
  UiGridAdd(grid, UiLabelNew("URL"), 0, 1);
  chat->url_entry = UiEntryNew(chat->url);
  UiExpand(chat->url_entry, TRUE);
  UiGridAdd(grid, chat->url_entry, 1, 1);
  UiGridAdd(grid, UiLabelNew("Model preset"), 0, 2);
  chat->preset = UiComboNew;
  for (i = 0; i < MODEL_COUNT; i++)
    UiComboAdd(chat->preset, model_names[i]);
  UiOnChange(chat->preset, &OnPreset, chat);
  UiGridAdd(grid, chat->preset, 1, 2);
  UiGridAdd(grid, UiLabelNew("Model"), 0, 3);
  chat->model_entry = UiEntryNew(chat->model);
  UiGridAdd(grid, chat->model_entry, 1, 3);
  UiGridAdd(grid, UiLabelNew("API key"), 0, 4);
  chat->key_entry = UiPasswordNew(chat->key);
  UiGridAdd(grid, chat->key_entry, 1, 4);
  UiGridAdd(grid, UiLabelNew("Reasoning"), 0, 5);
  chat->reasoning_combo = UiComboNew;
  for (i = 0; i < REASONING_COUNT; i++)
    UiComboAdd(chat->reasoning_combo, reasoning_names[i]);
  UiComboSetSelected(chat->reasoning_combo, chat->reasoning);
  UiGridAdd(grid, chat->reasoning_combo, 1, 5);
  UiGridAdd(grid, UiLabelNew("Temperature (tenths)"), 0, 6);
  chat->temperature_spin = UiSpinNew(0, 20);
  UiSpinSetValue(chat->temperature_spin, chat->temperature);
  UiGridAdd(grid, chat->temperature_spin, 1, 6);
  UiGridAdd(grid, UiLabelNew("System prompt"), 0, 7);
  chat->system_entry = UiEntryNew(chat->system);
  UiGridAdd(grid, chat->system_entry, 1, 7);

  row = UiBoxNew;
  UiBoxAdd(row, grid);
  apply = UiButtonNew("Apply (starts a new conversation)");
  UiOnClick(apply, &OnApply, chat);
  UiBoxAdd(row, apply);
  UiWindowSetChild(chat->dlg, row);
  UiShow(chat->dlg);
}

U0 OnNewChat(UiCtl *c, U0 *data);

U0 ChatNew()
{
  Chat *chat = CAlloc(sizeof(Chat));
  UiCtl *root, *row, *menu;
  U8 *url = getenv("LLM_URL");
  U8 *model = getenv("LLM_MODEL");
  U8 *key = getenv("OPENAI_API_KEY");

  if (!url)
    url = provider_urls[0];
  if (!model)
    model = provider_models[0];
  if (!key)
    key = "";
  chat->url = StrNew(url);
  chat->model = StrNew(model);
  chat->key = StrNew(key);
  chat->system = StrNew("You are a helpful assistant.");
  chat->temperature = 7;
  StrBufInit(&chat->transcript);
  chat->next = chats;
  chats = chat;

  chat->win = UiWindowNew("LLM chat", 640, 480);
  menu = UiMenuNew("Chat");
  UiMenuItem(menu, "New chat window", &OnNewChat);
  UiMenuItem(menu, "Clear conversation", &OnClear, chat);
  UiMenuItem(menu, "Save transcript...", &OnSave, chat);
  menu = UiMenuNew("Settings");
  UiMenuItem(menu, "Model and endpoint...", &OnSettings, chat);

  root = UiBoxNew;
  chat->log = UiMultilineNew;
  UiMultilineSetEditable(chat->log, FALSE);
  UiExpand(chat->log, TRUE);
  UiBoxAdd(root, UiScrollNew(chat->log));
  row = UiBoxNew(FALSE);
  chat->entry = UiEntryNew;
  UiExpand(chat->entry, TRUE);
  UiOnSubmit(chat->entry, &OnSend, chat);
  UiBoxAdd(row, chat->entry);
  chat->send = UiButtonNew("Send");
  UiOnClick(chat->send, &OnSend, chat);
  UiBoxAdd(row, chat->send);
  UiBoxAdd(root, row);
  chat->status = UiStatusbarNew;
  UiBoxAdd(root, chat->status);
  UiWindowSetChild(chat->win, root);
  ChatConfigure(chat);
  UiShow(chat->win);
}

U0 OnNewChat(UiCtl *c, U0 *data)
{
  ChatNew;
}

UiInit;
ChatNew;
UiTimer(100, &ChatCollect);
UiMain;
