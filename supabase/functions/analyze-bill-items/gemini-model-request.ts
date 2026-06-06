type GeminiErrorBody = {
  error?: {
    message?: unknown;
    status?: unknown;
    code?: unknown;
  };
};

type RequestGeminiModelJSONOptions = {
  apiKey: string;
  models: string[];
  body: Record<string, unknown>;
  fetcher?: typeof fetch;
  retryDelayMs?: number;
};

type GeminiModelJSONResult = {
  body: Record<string, unknown>;
  model: string;
};

export class GeminiModelRequestError extends Error {
  readonly status: number;
  readonly model: string;
  readonly body: Record<string, unknown>;

  constructor(
    message: string,
    status: number,
    model: string,
    body: Record<string, unknown>,
  ) {
    super(message);
    this.name = "GeminiModelRequestError";
    this.status = status;
    this.model = model;
    this.body = body;
  }
}

export function geminiModelNames(
  primaryModel: string,
  fallbackModelsValue?: string,
): string[] {
  const fallbackModels =
    (fallbackModelsValue?.split(",") ?? ["gemini-2.5-flash-lite"])
      .map((model) => model.trim())
      .filter(Boolean);

  return Array.from(
    new Set([primaryModel.trim(), ...fallbackModels].filter(Boolean)),
  );
}

export function isGeminiTransientFailure(
  status: number,
  body: unknown,
): boolean {
  if ([429, 500, 502, 503, 504].includes(status)) {
    return true;
  }

  const message = geminiErrorMessage(body).toLowerCase();
  return [
    "high demand",
    "overloaded",
    "try again later",
    "temporarily unavailable",
    "unavailable",
    "capacity",
  ].some((pattern) => message.includes(pattern));
}

export async function requestGeminiModelJSON(
  options: RequestGeminiModelJSONOptions,
): Promise<GeminiModelJSONResult> {
  const fetcher = options.fetcher ?? fetch;
  const retryDelayMs = options.retryDelayMs ?? 250;
  let lastError: GeminiModelRequestError | null = null;

  for (const model of options.models) {
    const maxAttempts = model === options.models[0] ? 2 : 1;
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      const response = await fetcher(
        geminiGenerateContentURL(model, options.apiKey),
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(options.body),
        },
      );
      const responseBody = await response.json().catch(() => ({}));
      const body = typeof responseBody === "object" && responseBody !== null
        ? responseBody as Record<string, unknown>
        : {};

      if (response.ok) {
        return { body, model };
      }

      lastError = new GeminiModelRequestError(
        geminiErrorMessage(body) || "Gemini bill item analysis failed.",
        response.status,
        model,
        body,
      );

      if (!isGeminiTransientFailure(response.status, body)) {
        throw lastError;
      }

      if (attempt < maxAttempts - 1 && retryDelayMs > 0) {
        await delay(retryDelayMs);
      }
    }
  }

  throw lastError ??
    new GeminiModelRequestError(
      "Gemini bill item analysis failed.",
      502,
      "",
      {},
    );
}

function geminiGenerateContentURL(model: string, apiKey: string): string {
  return `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
}

function geminiErrorMessage(body: unknown): string {
  const raw = typeof body === "object" && body !== null
    ? body as GeminiErrorBody
    : {};
  return typeof raw.error?.message === "string" ? raw.error.message : "";
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
