export function getSupabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !publishableKey) {
    throw new Error(
      "Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY before using Supabase.",
    );
  }

  return { url, publishableKey };
}

export type SiteOriginResult =
  | { ok: true; origin: string }
  | { ok: false; error: string };

export function getConfiguredSiteOrigin(): SiteOriginResult {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL?.trim();

  if (!siteUrl) {
    return {
      ok: false,
      error:
        "Set NEXT_PUBLIC_SITE_URL to your app's public URL, such as https://your-app.example.com.",
    };
  }

  let parsedUrl: URL;
  try {
    parsedUrl = new URL(siteUrl);
  } catch {
    return {
      ok: false,
      error: "NEXT_PUBLIC_SITE_URL must be a valid absolute http:// or https:// URL.",
    };
  }

  if (
    (parsedUrl.protocol !== "http:" && parsedUrl.protocol !== "https:") ||
    !parsedUrl.hostname ||
    parsedUrl.username ||
    parsedUrl.password
  ) {
    return {
      ok: false,
      error: "NEXT_PUBLIC_SITE_URL must be a valid absolute http:// or https:// URL.",
    };
  }

  return { ok: true, origin: parsedUrl.origin };
}
