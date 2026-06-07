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
  primaryMaxAttempts?: number;
  retryDelayMs?: number;
  timeoutMs?: number;
  totalTimeoutMs?: number;
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
  const startedAt = Date.now();
  const timeoutMs = options.timeoutMs;
  const totalTimeoutMs = options.totalTimeoutMs;
  const primaryMaxAttempts = options.primaryMaxAttempts ?? 2;
  const retryDelayMs = options.retryDelayMs ?? 250;
  let lastError: GeminiModelRequestError | null = null;

  for (const model of options.models) {
    const maxAttempts = model === options.models[0] ? primaryMaxAttempts : 1;
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      const attemptTimeoutMs = boundedAttemptTimeoutMs(
        startedAt,
        timeoutMs,
        totalTimeoutMs,
      );
      if (attemptTimeoutMs !== undefined && attemptTimeoutMs <= 0) {
        throw lastError ??
          timeoutError(model, totalTimeoutMs ?? timeoutMs ?? 0);
      }

      let timeoutID: number | undefined;
      const abortController = attemptTimeoutMs !== undefined
        ? new AbortController()
        : undefined;
      if (
        abortController && attemptTimeoutMs !== undefined &&
        attemptTimeoutMs > 0
      ) {
        timeoutID = setTimeout(
          () => abortController.abort(),
          attemptTimeoutMs,
        );
      }

      try {
        const response = await fetcher(
          geminiGenerateContentURL(model, options.apiKey),
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify(options.body),
            signal: abortController?.signal,
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
      } catch (error) {
        if (error instanceof GeminiModelRequestError) {
          throw error;
        }

        lastError = timeoutLikeError(error, model, attemptTimeoutMs);
      } finally {
        if (timeoutID !== undefined) {
          clearTimeout(timeoutID);
        }
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

function boundedAttemptTimeoutMs(
  startedAt: number,
  timeoutMs?: number,
  totalTimeoutMs?: number,
): number | undefined {
  if (timeoutMs === undefined && totalTimeoutMs === undefined) {
    return undefined;
  }

  const remainingTotalMs = totalTimeoutMs === undefined
    ? Number.POSITIVE_INFINITY
    : totalTimeoutMs - (Date.now() - startedAt);
  const boundedTimeoutMs = timeoutMs === undefined
    ? remainingTotalMs
    : Math.min(timeoutMs, remainingTotalMs);

  return Math.max(0, Math.floor(boundedTimeoutMs));
}

function timeoutLikeError(
  error: unknown,
  model: string,
  timeoutMs?: number,
): GeminiModelRequestError {
  const isAbortError = typeof error === "object" && error !== null &&
    "name" in error && error.name === "AbortError";
  const message = isAbortError && timeoutMs !== undefined
    ? `Gemini bill item analysis timed out after ${timeoutMs} ms.`
    : error instanceof Error
    ? error.message
    : "Gemini bill item analysis request failed.";

  return new GeminiModelRequestError(
    message,
    isAbortError ? 504 : 502,
    model,
    {},
  );
}

function timeoutError(
  model: string,
  timeoutMs: number,
): GeminiModelRequestError {
  return new GeminiModelRequestError(
    `Gemini bill item analysis timed out after ${timeoutMs} ms.`,
    504,
    model,
    {},
  );
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
