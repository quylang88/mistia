import {
  geminiModelNames,
  GeminiModelRequestError,
  isGeminiTransientFailure,
  requestGeminiModelJSON,
} from "./gemini-model-request.ts";

Deno.test("geminiModelNames keeps primary first and adds flash lite fallback", () => {
  const names = geminiModelNames("gemini-2.5-flash");

  if (names.join(",") !== "gemini-2.5-flash,gemini-2.5-flash-lite") {
    throw new Error(`Unexpected model order: ${names.join(",")}`);
  }
});

Deno.test("isGeminiTransientFailure treats high demand responses as retryable", () => {
  const retryable = isGeminiTransientFailure(503, {
    error: {
      message: "The model is experiencing high demand. Please try again later.",
    },
  });

  if (!retryable) {
    throw new Error("Expected high demand response to be retryable");
  }
});

Deno.test("requestGeminiModelJSON falls back after high demand response", async () => {
  const calls: string[] = [];
  const fetcher: typeof fetch = async (input) => {
    const url = String(input);
    calls.push(url);
    if (calls.length <= 2) {
      return new Response(
        JSON.stringify({
          error: { message: "The model is experiencing high demand." },
        }),
        { status: 503, headers: { "Content-Type": "application/json" } },
      );
    }
    return new Response(JSON.stringify({ candidates: [] }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };

  const result = await requestGeminiModelJSON({
    apiKey: "test-key",
    models: ["gemini-2.5-flash", "gemini-2.5-flash-lite"],
    body: { contents: [] },
    fetcher,
    retryDelayMs: 0,
  });

  if (result.model !== "gemini-2.5-flash-lite") {
    throw new Error(`Expected fallback model, got ${result.model}`);
  }
  if (calls.length !== 3) {
    throw new Error(`Expected 3 model calls, got ${calls.length}`);
  }
  if (!calls[2].includes("/models/gemini-2.5-flash-lite:generateContent")) {
    throw new Error(`Unexpected fallback URL: ${calls[2]}`);
  }
});

Deno.test("requestGeminiModelJSON surfaces final nonretryable model error", async () => {
  const fetcher: typeof fetch = async () =>
    new Response(JSON.stringify({ error: { message: "Invalid request" } }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });

  let error: unknown;
  try {
    await requestGeminiModelJSON({
      apiKey: "test-key",
      models: ["gemini-2.5-flash"],
      body: { contents: [] },
      fetcher,
      retryDelayMs: 0,
    });
  } catch (caught) {
    error = caught;
  }

  if (!(error instanceof GeminiModelRequestError)) {
    throw new Error("Expected GeminiModelRequestError");
  }
  if (error.message !== "Invalid request") {
    throw new Error(`Unexpected error message: ${error.message}`);
  }
});
