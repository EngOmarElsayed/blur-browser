# Blur Browser — Website

Next.js 15 marketing site for the Blur Browser macOS app.

## Stack
- Next.js 15 (App Router) + React 19
- TypeScript
- Tailwind CSS 3
- Web3Forms for the contact form

## Setup

```bash
cd Website
npm install
cp .env.local.example .env.local  # fill in your Web3Forms access key
npm run dev
```

Open http://localhost:3000.

## Theme

The site mirrors the 7 themes in the macOS app — Periwinkle, Midnight, Sandstone,
Nordic, Rosewood, Verdant, Graphite — defined in `lib/themes.ts`. The theme
switcher (top-right) updates CSS custom properties on `:root` and persists the
choice to `localStorage`.

## Screenshots

Drop PNGs into `public/screenshots/` and replace the placeholder divs in
`components/Features.tsx` and `components/Hero.tsx` with `<Image>` tags.
