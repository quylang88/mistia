import { createClient } from "npm:@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return jsonResponse({ message: "Method not allowed." }, 405)
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL")
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const authHeader = request.headers.get("Authorization")

  if (!supabaseURL || !supabaseAnonKey || !serviceRoleKey) {
    return jsonResponse({ message: "Supabase function environment is incomplete." }, 500)
  }

  if (!authHeader) {
    return jsonResponse({ message: "Missing Authorization header." }, 401)
  }

  const userClient = createClient(supabaseURL, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  })

  const {
    data: { user },
    error: getUserError,
  } = await userClient.auth.getUser()

  if (getUserError || !user) {
    return jsonResponse(
      { message: getUserError?.message ?? "Unable to validate the current user." },
      401
    )
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })

  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(user.id)

  if (deleteUserError) {
    return jsonResponse(
      { message: deleteUserError.message ?? "Failed to delete the current user." },
      500
    )
  }

  return jsonResponse({
    success: true,
    deletedUserID: user.id,
  })
})
