import Link from "next/link";
import Image from "next/image";

export default function AuthLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-7xl flex-col px-5 py-5 sm:px-8 sm:py-8 lg:px-12">
      <header className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <Link href="/sign-in" className="flex items-center gap-3" aria-label="OneWay Africa home">
          <Image
            alt=""
            className="size-11 rounded-full"
            height={44}
            priority
            src="/icons/oneway-africa-mark.png"
            width={44}
          />
          <span className="text-lg font-extrabold uppercase tracking-[0.1em] text-ink sm:text-xl">
            ONEWAY AFRICA
          </span>
        </Link>
        <span className="pl-14 text-[0.65rem] font-semibold uppercase leading-tight tracking-[0.13em] text-forest/70 sm:pl-0 sm:text-right sm:text-xs">
          JFC &amp; BIBLEPLUS INVENTORY PLATFORM
        </span>
      </header>

      <div className="grid flex-1 items-center gap-12 py-12 lg:grid-cols-[1fr_0.85fr] lg:gap-20">
        <section className="mx-auto w-full max-w-md space-y-6 lg:mx-0">
          <div>
            <p className="mb-3 text-xs font-bold uppercase tracking-[0.2em] text-leaf">Who we are</p>
            <h1 className="max-w-xl text-4xl font-semibold leading-tight tracking-tight text-ink sm:text-5xl">
              Advancing the gospel among the unreached.
            </h1>
            <p className="mt-4 max-w-lg text-base leading-7 text-ink/70">
              OneWay Africa is a Christian, non-denominational, non-governmental, non-profit
              missions organisation.
            </p>
          </div>
          <article className="rounded-2xl border border-white/80 bg-white/70 p-5 shadow-card">
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-leaf">Our vision</h2>
            <p className="mt-2 text-sm leading-6 text-ink/80">
              A movement of Christlike Africans radically fulfilling the Great Commission.
            </p>
          </article>
          <article className="rounded-2xl border border-white/80 bg-white/70 p-5 shadow-card">
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-leaf">Our mission</h2>
            <p className="mt-2 text-sm leading-6 text-ink/80">
              To activate God&apos;s people in Africa and beyond to exalt Jesus Christ and together
              advance His gospel to the multitudes particularly among the unreached.
            </p>
          </article>
          <p className="text-sm leading-6 text-ink/65">
            Our work includes missions mobilization and training, BiblePlus, Jesus Film outreach,
            clean-water projects, and church planting.
          </p>
        </section>
        <section className="mx-auto w-full max-w-md rounded-3xl border border-white/80 bg-white/90 p-6 shadow-card backdrop-blur sm:p-9">
          {children}
        </section>
      </div>

      <footer className="flex flex-col gap-2 border-t border-ink/10 py-5 text-xs text-ink/55 sm:flex-row sm:items-center sm:justify-between">
        <span>OneWay Africa</span>
        <span>Secure access to outreach data and BiblePlus inventory</span>
      </footer>
    </main>
  );
}
