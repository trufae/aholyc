#include "lib/llm/llm.hc"

I64 failures = 0;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

U0 TestChatRequest()
{
  CLlm llm;
  U8 *request;
  U8 *expected =
    "{\"model\":\"test-model\",\"messages\":[{\"role\":\"system\",\"content\":\"Be concise.\"},{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"What is shown?\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,AQID\",\"detail\":\"auto\"}},{\"type\":\"file\",\"file\":{\"file_id\":\"file-1\"}}]},{\"role\":\"assistant\",\"content\":\"A \\\"cat\\\"\"},{\"role\":\"tool\",\"tool_call_id\":\"c1\",\"content\":\"3\"}],\"temperature\":0.25}";

  Check(LlmInit(&llm, "https://example.com/v1/chat/completions", "test-model",
      "sk-1", "X-Org: acme\r\n"), "init");
  Check(!llm.responses, "chat api detected");
  Check(!StrCmp(llm.headers, "Authorization: Bearer sk-1\r\nX-Org: acme\r\n"),
    "headers");
  LlmSystem(&llm, "Be concise.");
  LlmImage(&llm, "data:image/png;base64,AQID", "auto");
  LlmFile(&llm, "file-1");
  Check(LlmMessage(&llm, "user", "What is shown?"), "user message");
  Check(LlmMessage(&llm, "assistant", "A \"cat\""), "assistant message");
  Check(LlmRaw(&llm, "{\"role\":\"tool\",\"tool_call_id\":\"c1\",\"content\":\"3\"}"),
    "raw message");
  Check(!LlmRaw(&llm, "[1]"), "raw message must be an object");
  Check(LlmSet(&llm, "temperature", "0.25"), "set field");
  Check(!LlmSet(&llm, "bad", "{"), "set rejects invalid JSON");
  request = LlmRequest(&llm);
  Check(!StrCmp(request, expected), "chat request JSON");
  Free(request);
  LlmFini(&llm);
}

U0 TestResponsesRequest()
{
  CLlm llm;
  U8 *request;
  U8 *expected =
    "{\"model\":\"m\",\"instructions\":\"Use the sources.\",\"input\":[{\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Compare.\"},{\"type\":\"input_image\",\"image_url\":\"https://x/a.png\",\"detail\":\"high\"},{\"type\":\"input_file\",\"filename\":\"a.pdf\",\"file_data\":\"data:application/pdf;base64,AQID\"}]}]}";

  Check(LlmInit(&llm, "https://api.openai.com/v1/responses", "m"),
    "responses init");
  Check(llm.responses, "responses api detected");
  Check(!llm.headers, "no headers without key");
  LlmSystem(&llm, "Use the sources.");
  LlmImage(&llm, "https://x/a.png", "high");
  LlmFile(&llm, NULL, "a.pdf", "data:application/pdf;base64,AQID");
  LlmMessage(&llm, "user", "Compare.");
  request = LlmRequest(&llm);
  Check(!StrCmp(request, expected), "responses request JSON");
  Free(request);
  LlmFini(&llm);
}

U0 TestParse()
{
  CLlm llm;
  U8 *text;
  CJsonValue id;

  LlmInit(&llm, "http://localhost/v1/chat/completions", "m");

  text = LlmParse(&llm,
    "{\"id\":\"chat-1\",\"choices\":[{\"message\":{\"content\":\"hello \\u263a\"}}],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":3}}");
  Check(text && !StrCmp(text, "hello \xE2\x98\xBA"), "chat text");
  Check(llm.input_tokens == 2 && llm.output_tokens == 3, "usage");
  Check(JsonObjectGet(&llm.json, "id", &id) &&
    JsonValueStringEquals(&id, "chat-1"), "raw json access");
  Free(text);

  text = LlmParse(&llm,
    "{\"choices\":[{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"parts\"}]}}]}");
  Check(text && !StrCmp(text, "parts"), "chat content parts");
  Free(text);

  text = LlmParse(&llm,
    "{\"output\":[{\"type\":\"reasoning\",\"summary\":[]},{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"second\"}]}]}");
  Check(text && !StrCmp(text, "second"), "responses output items");
  Free(text);

  text = LlmParse(&llm, "{\"error\":{\"message\":\"bad key\"}}");
  Check(!text && !StrCmp(llm.error, "bad key"), "error message");
  text = LlmParse(&llm, "not json");
  Check(!text && llm.error, "invalid body");
  LlmFini(&llm);
}

TestChatRequest;
TestResponsesRequest;
TestParse;
if (failures)
  Exit(1);
"llm ok\n";
