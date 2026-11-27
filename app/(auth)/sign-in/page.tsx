import type { Metadata } from "next";
import Link from "next/link";
import { SignInForm } from "@/components/auth/sign-in-form";

export const metadata: Metadata = {
  title: "Sign in",
};

type SignInPageProps = {
  searchParams: Promise<{ notice?: string }>;
};

export default async function SignInPage({ searchParams }: SignInPageProps) {
  const { notice } = await searchParams;

  return (
    <div>
      <h2 className="text-2xl font-semibold tracking-tight text-ink">Sign in</h2>
      <p className="mt-2 text-sm leading-6 text-ink/65">
        Use your authorized account to access outreach and inventory data.
      </p>
      {notice === "password-updated" && (
        <p role="status" className="mt-5 rounded-xl bg-emerald-50 px-4 py-3 text-sm text-forest">
          Your password has been updated. Sign in with your new password.
        </p>
      )}
      {notice === "recovery-error" && (
        <p role="alert" className="mt-5 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800">
          This password-recovery link is invalid or expired. Request a new one.
        </p>
      )}
      <SignInForm />
      <p className="mt-6 text-center text-sm text-ink/65">
        Forgot your password?{" "}
        <Link href="/forgot-password" className="font-semibold text-forest underline-offset-4 hover:underline">
          Recover access
        </Link>
      </p>
    </div>
  );
}
