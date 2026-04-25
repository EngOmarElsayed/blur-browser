import Image from "next/image";
import Link from "next/link";

export function Footer() {
  return (
    <footer className="border-t border-border/50 bg-chrome/30">
      <div className="flex w-full flex-col items-center justify-between gap-6 px-6 py-10 sm:flex-row sm:px-10">
        <Link href="/" className="flex items-center gap-2.5">
          <Image src="/logo.png" alt="Blur" width={24} height={24} className="rounded-md" />
          <span className="text-sm font-semibold text-foreground">Blur Browser</span>
        </Link>
        <div className="flex items-center gap-6 text-sm text-foreground/70">
          <Link href="/#how-it-works" className="hover:text-foreground transition">How it works</Link>
          <Link href="/about" className="hover:text-foreground transition">About</Link>
          <Link href="/contact" className="hover:text-foreground transition">Contact</Link>
        </div>
        <p className="text-xs text-foreground/50">
          © {new Date().getFullYear()} Blur Browser · Open source & free
        </p>
      </div>
    </footer>
  );
}
