import type { Metadata } from "next";
import Link from "next/link";
import { PasswordResetForm } from "@/components/auth/password-reset-form";

export const metadata: Metadata = {
  title: "Recover password",
};

export default function ForgotPasswordPage() {
  return (
    <div>
      <h2 className="text-2xl font-semibold tracking-tight text-ink">Recover your password</h2>
      <p className="mt-2 text-sm leading-6 text-ink/65">
        Enter your account email and we’ll send a secure recovery link if it matches an account.
      </p>
      <PasswordResetForm />
      <p className="mt-6 text-center text-sm text-ink/65">
        Remembered your password?{" "}
        <Link href="/sign-in" className="font-semibold text-forest underline-offset-4 hover:underline">
          Return to sign in
        </Link>
      </p>
    </div>
  );
}
