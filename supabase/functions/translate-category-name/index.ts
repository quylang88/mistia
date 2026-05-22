const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

type TranslationRequest = {
  name?: string
  source_language?: string
}

const translationResponseSchema = {
  type: "OBJECT",
  properties: {
    name_vietnamese: { type: "STRING" },
    name_english: { type: "STRING" },
    name_japanese: { type: "STRING" },
  },
  required: ["name_vietnamese", "name_english", "name_japanese"],
  propertyOrdering: ["name_vietnamese", "name_english", "name_japanese"],
}

function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  })
}

function trimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function extractModelText(payload: Record<string, unknown>): string {
  const candidates = Array.isArray(payload.candidates) ? payload.candidates : []
  const parts = candidates.flatMap((candidate) => {
    const content = typeof candidate === "object" && candidate !== null
      ? (candidate as Record<string, unknown>).content
      : null
    const rawParts = typeof content === "object" && content !== null
      ? (content as Record<string, unknown>).parts
      : null
    return Array.isArray(rawParts) ? rawParts : []
  })

  return parts
    .map((part) => typeof part === "object" && part !== null ? (part as Record<string, unknown>).text : null)
    .filter((text): text is string => typeof text === "string")
    .join("\n")
    .trim()
}

function parseModelJSON(text: string): Record<string, unknown> {
  const trimmed = text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim()
  try {
    return JSON.parse(trimmed) as Record<string, unknown>
  } catch {
    const start = trimmed.indexOf("{")
    const end = trimmed.lastIndexOf("}")
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1)) as Record<string, unknown>
    }
    throw new Error("Model response did not contain a JSON object.")
  }
}

function fallbackTranslation(name: string, sourceLanguage: string): Record<string, string> {
  return {
    name_vietnamese: sourceLanguage === "vi" ? name : name,
    name_english: sourceLanguage === "en" ? name : name,
    name_japanese: sourceLanguage === "ja" ? name : name,
  }
}

function sanitizeTranslation(
  modelResult: Record<string, unknown>,
  name: string,
  sourceLanguage: string
): Record<string, string> {
  const result = fallbackTranslation(name, sourceLanguage)
  const vietnamese = trimmedString(modelResult.name_vietnamese)
  const english = trimmedString(modelResult.name_english)
  const japanese = trimmedString(modelResult.name_japanese)

  if (vietnamese) result.name_vietnamese = vietnamese
  if (english) result.name_english = english
  if (japanese) result.name_japanese = japanese

  if (sourceLanguage === "vi") result.name_vietnamese = name
  if (sourceLanguage === "en") result.name_english = name
  if (sourceLanguage === "ja") result.name_japanese = name

  return result
}

function buildPrompt(name: string, sourceLanguage: string): string {
  return [
    "Translate one personal finance category label into Vietnamese, English, and Japanese.",
    "Return only JSON with snake_case keys: name_vietnamese, name_english, name_japanese.",
    "The label is a short category name, not a sentence. Use concise finance-app category wording.",
    "Preserve brand names and product names when translation would be unnatural.",
    "Do not add explanations, punctuation, quotes, or parenthetical notes.",
    "Keep the user's original text exactly in the matching source language field.",
    `Source language: ${sourceLanguage}.`,
    `Category label: ${name}`,
  ].join("\n")
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return jsonResponse({ message: "Method not allowed." }, 405)
  }

  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")
  const geminiAPIKey = Deno.env.get("GEMINI_API_KEY")
  const geminiModel = Deno.env.get("GEMINI_CATEGORY_TRANSLATION_MODEL") ?? "gemini-2.5-flash"
  const apiKey = request.headers.get("apikey")

  if (!supabaseAnonKey || !geminiAPIKey) {
    return jsonResponse({ message: "Category translation environment is incomplete." }, 500)
  }

  if (apiKey !== supabaseAnonKey) {
    return jsonResponse({ message: "Invalid API key." }, 401)
  }

  let payload: TranslationRequest
  try {
    payload = await request.json()
  } catch {
    return jsonResponse({ message: "Invalid JSON body." }, 400)
  }

  const name = trimmedString(payload.name)
  const sourceLanguage = payload.source_language
  if (!name) {
    return jsonResponse({ message: "Missing category name." }, 400)
  }
  if (sourceLanguage !== "vi" && sourceLanguage !== "en" && sourceLanguage !== "ja") {
    return jsonResponse({ message: "Unsupported source language." }, 400)
  }

  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${geminiAPIKey}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [{ text: buildPrompt(name, sourceLanguage) }],
          },
        ],
        generationConfig: {
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: translationResponseSchema,
        },
      }),
    }
  )

  const geminiBody = await geminiResponse.json().catch(() => ({}))
  if (!geminiResponse.ok) {
    const message = typeof geminiBody.error === "object" && geminiBody.error !== null
      ? (geminiBody.error as Record<string, unknown>).message
      : null
    return jsonResponse(
      { message: typeof message === "string" ? message : "Gemini category translation failed." },
      502
    )
  }

  try {
    const modelText = extractModelText(geminiBody as Record<string, unknown>)
    if (!modelText) {
      return jsonResponse(fallbackTranslation(name, sourceLanguage))
    }
    const modelResult = parseModelJSON(modelText)
    return jsonResponse(sanitizeTranslation(modelResult, name, sourceLanguage))
  } catch {
    return jsonResponse(fallbackTranslation(name, sourceLanguage))
  }
})
