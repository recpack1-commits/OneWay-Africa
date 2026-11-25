import Link from "next/link";

export default function AuthLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-7xl flex-col px-5 py-5 sm:px-8 sm:py-8 lg:px-12">
      <header className="flex items-center justify-between">
        <Link href="/sign-in" className="flex items-center gap-3" aria-label="OneWay Africa home">
          <span className="flex size-11 items-center justify-center rounded-2xl bg-forest text-white shadow-card">
            <span className="text-lg font-bold tracking-tight">OA</span>
          </span>
          <span className="text-sm font-bold tracking-wide text-ink">ONEWAY AFRICA</span>
        </Link>
        <span className="hidden text-xs font-semibold uppercase tracking-[0.18em] text-forest/70 sm:block">
          Ministry platform
        </span>
      </header>

      <div className="grid flex-1 items-center gap-12 py-12 lg:grid-cols-[1fr_0.85fr] lg:gap-20">
        <section className="mx-auto w-full max-w-md lg:mx-0">
          <p className="mb-3 text-xs font-bold uppercase tracking-[0.2em] text-leaf">
            One mission. Many communities.
          </p>
          <h1 className="max-w-xl text-4xl font-semibold leading-tight tracking-tight text-ink sm:text-5xl">
            Welcome to a more connected ministry.
          </h1>
          <p className="mt-5 max-w-lg text-base leading-7 text-ink/70">
            Sign in to continue to the OneWay Africa and BiblePlus ministry platform.
          </p>
        </section>
        <section className="mx-auto w-full max-w-md rounded-3xl border border-white/80 bg-white/90 p-6 shadow-card backdrop-blur sm:p-9">
          {children}
        </section>
      </div>

      <footer className="flex flex-col gap-2 border-t border-ink/10 py-5 text-xs text-ink/55 sm:flex-row sm:items-center sm:justify-between">
        <span>OneWay Africa &amp; BiblePlus</span>
        <span>Secure access for authorized ministry team members</span>
      </footer>
    </main>
  );
}
