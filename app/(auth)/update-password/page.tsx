import type { Metadata } from "next";
import { UpdatePasswordForm } from "@/components/auth/update-password-form";

export const metadata: Metadata = {
  title: "Set a new password",
};

export default function UpdatePasswordPage() {
  return (
    <div>
      <h2 className="text-2xl font-semibold tracking-tight text-ink">Choose a new password</h2>
      <p className="mt-2 text-sm leading-6 text-ink/65">
        Use at least 8 characters. Your recovery link must still be valid.
      </p>
      <UpdatePasswordForm />
    </div>
  );
}
