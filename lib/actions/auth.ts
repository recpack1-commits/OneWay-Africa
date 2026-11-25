"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AuthActionState = {
  error?: string;
  message?: string;
};

function getEmail(formData: FormData) {
  const email = formData.get("email");
  return typeof email === "string" ? email.trim() : "";
}

export async function signInAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = getEmail(formData);
  const password = formData.get("password");

  if (!email || typeof password !== "string" || !password) {
    return { error: "Enter your email address and password." };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return { error: "Email or password is incorrect." };
  }

  redirect("/dashboard");
}

export async function requestPasswordResetAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = getEmail(formData);

  if (!email) {
    return { error: "Enter your email address." };
  }

  const requestHeaders = await headers();
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;

  if (!siteUrl) {
    return { error: "Password recovery is not configured. Contact your platform administrator." };
  }

  const configuredOrigin = new URL(siteUrl).origin;
  const requestOrigin = requestHeaders.get("origin");

  if (requestOrigin && new URL(requestOrigin).origin !== configuredOrigin) {
    return { error: "Unable to process this request. Reload the page and try again." };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${configuredOrigin}/auth/callback?next=/update-password`,
  });

  if (error) {
    return { error: "Unable to send a recovery email right now. Please try again later." };
  }

  return {
    message: "If an account matches that email, a secure recovery link will arrive shortly.",
  };
}

export async function updatePasswordAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const password = formData.get("password");
  const confirmPassword = formData.get("confirmPassword");

  if (typeof password !== "string" || password.length < 8) {
    return { error: "Choose a password with at least 8 characters." };
  }

  if (password !== confirmPassword) {
    return { error: "The passwords do not match." };
  }

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return { error: "This recovery session is invalid or expired. Request a new link." };
  }

  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    return { error: "Unable to update your password. Request a new recovery link and try again." };
  }

  redirect("/sign-in?notice=password-updated");
}

export async function signOutAction() {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signOut();

  if (error) {
    throw new Error("Unable to sign out. Please try again.");
  }

  redirect("/sign-in");
}
