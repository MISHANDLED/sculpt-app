# Dock Design System

The visual + interaction system that powers **Blinkit** (Grofers) internal tools and operator-facing surfaces. Built and maintained by the Grofers/Blinkit design team and shipped as the npm package `@grofers/dock-design-kit`.

> Blinkit is a quick-commerce platform (10-minute grocery delivery in India). **Dock** is the design system — a set of React components, design tokens, and an icon font that backs every Blinkit ops & B2B web product (admin consoles, dashboards, fulfillment tools, partner portals, etc).

---

## Sources consulted

| What | Where |
|------|-------|
| Component source code, tokens, stories | Local codebase `dock-design-kit/` (npm package `@grofers/dock-design-kit` v2.8.0) |
| Repo origin | `git://github.com:grofers/design-kit-web.git` (monorepo, `packages/dock-design-kit`) |
| Custom icon font | `dock-design-kit/public/icons/Dockit.ttf` — 2,090 glyphs (Material-style, drawn in-house) |
| Lexend font files | Uploaded TTFs (Light / Regular / Medium / SemiBold / Bold) |
| Brand logo | `https://cdn.grofers.com/da/consumer-web-assets/blinkit logo.webp` (Grofers CDN — referenced live in `assets/`) |

The reader will not have access to the source codebase. Assume everything you need has been distilled into this folder.

---

## Index

```
.
├── README.md                  ← this file
├── SKILL.md                   ← skill entry-point (cross-compatible with Claude Code)
├── colors_and_type.css        ← every token: colors, type, spacing, radii, shadows + semantic L/D themes
├── fonts/
│   ├── Lexend-{Light,Regular,Medium,SemiBold,Bold}.ttf
│   └── Dockit.ttf             ← icon font (2,090 glyphs)
├── assets/
│   ├── dockit-icons.css       ← class definitions for every glyph (.--dock-icon-search etc.)
│   ├── icon-mappings.json     ← name → codepoint map (1,800+ entries)
│   └── blinkit-logo.url       ← canonical CDN URL for the live Blinkit wordmark
├── preview/                   ← Design System tab cards (registered as assets)
├── ui_kits/
│   └── blinkit-ops-console/   ← internal-tool UI kit (Navbar + GlobalHeader + table workflow)
```

---

## CONTENT FUNDAMENTALS

Dock content is for **operators, partners, and internal staff** — not consumer-facing marketing. Tone is **direct, factual, and short**.

- **Tone**: instructive, neutral. Skip cleverness. The component README opens with `A versatile and reusable Button component based on the Dock Design System` — descriptive, then a feature checklist. No exclamation marks, no taglines.
- **Casing**: Sentence case for everything user-facing (labels, button text, headers, section titles). Title Case only for proper nouns ("Raise Ticket", "Sign Out"). Filterable values like `userID` keep their dev-correct casing.
- **Voice**: You/yours. Imperative for actions ("Save changes", "Delete account", "Continue"). Never "Please …". Never "Click here".
- **Button copy**: One verb, two max. `Save`, `Cancel`, `Delete`, `Continue`, `Raise Ticket`, `Add to home screen`. Destructive actions name the thing: `Delete Account`, never `Yes`.
- **Search placeholders**: include the keyboard hint: `⌘+K to Search` (from `GlobalHeader.tsx` default).
- **Form helper text**: present-tense, no period if a single phrase. `Required field`, `Must be 8 characters`, `Email is invalid`.
- **Numbers, currency**: Indian conventions where shown — `₹`, lakh/crore in finance views; otherwise western 1,234.
- **Emoji**: **No.** Never used in product surfaces. Status is communicated by tinted Tag/Pill chips, not 🟢 dots.
- **Empty states**: state the fact, then offer the action. `No alerts right now. Configure thresholds.`
- **The vibe**: Stripe-meets-Linear, calibrated for an Indian quick-commerce ops team. Spreadsheet-dense when it needs to be, breathable elsewhere. No flourish, no marketing energy.

**Example copy you'll see in real product:**

| Surface | Copy |
|---|---|
| Header search | `⌘+K to Search` |
| Profile menu | `Sign Out` |
| Destructive confirm | `Are you sure you want to delete this item?` / `Delete` |
| Header CTA | `Raise Ticket` |
| Toast (success) | `Changes saved` |
| Toast (error) | `Couldn't save. Try again.` |
| Tag values | `Site`, `VALUE`, `ACTIVE`, `PENDING` (often ALL-CAPS when used as a system-state badge) |

---

## VISUAL FOUNDATIONS

Dock's visual identity is **monochrome-first with a colorful Tag/Pill vocabulary**. The brand green (`#318616`) is a *reserved* accent, almost never used as a primary action color — primary buttons are **black** (`#0D121C`). This is intentional: it lets the dense operator surfaces stay calm while letting the Blinkit green show up only on attribution, location chips, and the logo.

### Colors

- **Brand absolutes**: Blinkit Green `#318616`, Blinkit Yellow `#F8CB46`, Blinkit Black `#1F1F1F`. Green/yellow are used for branding moments only.
- **Hue families** (each with 11 stops, 50→950): red, green, yellow, blue, orange, teal, brown, pink, lime, cider, purple, indigo. Reds for destructive, blues for "discover/info", greens for success, oranges for warning.
- **Neutrals**: two distinct grey ramps — `grey` (cool, used in light mode) and `grey-dark` (warmer/neutral, used in dark mode) — both 50→950. This avoids the common bug where one grey scale looks washed out in the inverted theme.
- **Alpha ramps**: `alpha-light` (white-over-X) and `alpha-dark` (near-black `#17171C`-over-X) at 5/10/25/50/100/200/300/400/450/500 — used for hover states, overlays, focus rings.
- **Semantic tokens are the contract**: app code never writes raw `#hex` — it writes `var(--dock-surface-primary)`, `var(--dock-text-error)`, `var(--dock-border-primary)`. Light and dark each map the same token to a different primitive.

### Typography

- **Single family**: `Lexend` (a rounded, slightly humanist geometric sans designed for readability). Weights ship 300/400/500/600/700.
- **Two scales**:
  - **size** 50→900 (10/12/14/18/20/24/28/32/36 px) — UI text, body, headings.
  - **display** 50→300 (44/52/64/96 px) — hero/marketing moments. Operator screens rarely go past display-50.
- **Default body** is `size-200` (14px, 18px line-height). UI controls use `size-100` (sm), `size-200` (md), `size-400` (lg).
- **Weight conventions**: regular for body, **medium** for button labels and active nav items, semibold for section headers, bold for display-only. Light (300) is reserved for large display numbers and never below 24px.

### Spacing & layout

- **Spacing tokens**: `0/1/2/4/6/8/10/12/16/20/24/28/32/36/40/48/56/64/96/128`. The compact end (1/2/4/6) exists for fine icon padding inside dense tables.
- **Component heights are pegged to spacing**: button sm=`28`, md=`36`, lg=`48`. Input sm=`36`, lg=`48`. Header height=`53`. Collapsed navbar=`52`, expanded=`256`.
- **Borders**: 0.5px / 1px / 1.5px / 2px — Dock uses *hairline* 0.5px borders frequently (e.g. focus rings, table dividers) which gives that crisp Stripe/Linear feel.
- **Radii**: 0/2/4/6/8/10/12/16/20/24/28/32/`max` (=9999). Button sm uses `4`, md uses `6`, lg uses `8`. Cards usually 8–12. Pills/Tags use `max` (full pill) or `4` (square chips).

### Backgrounds

- **No gradients** in production UI. Surfaces are flat solids.
- **No background imagery** in product (illustrations belong on marketing/empty-state surfaces — out of scope for Dock).
- **No textures or patterns.**
- Light-mode page background is `grey-100` (`#F3F4F6`) — *not* pure white. Cards sit on it as `white` to create a paper-on-table elevation effect without needing heavy shadows.
- Dark-mode page background is `black-dark` (`#0D0D11`) with surfaces stepping up to `grey-dark-900` / `-800`.

### Elevation & shadows

- 6 shadow rungs: `xs / sm / md / lg / xl / 2xl`. Each comes in 5 directional variants: omnidirectional + bias to `t-/b-/l-/r-` (top/bottom/left/right).
- Shadows use `rgba(16,24,40,…)` (very slight cool tint) at 6–18% opacity. Never warm. Never colored.
- **Buttons have no shadow** — flatness is the convention. Shadows appear on: dropdown menus (`md`/`lg`), modals (`xl`/`2xl`), toasts (`lg`).
- **Inner shadow**: only used for the focus ring — `inset` is not part of the elevation system.

### Borders & dividers

- Almost every container uses `1px var(--dock-border-secondary)` (grey-100). It's nearly invisible in light mode but defines the structure.
- High-stakes containers (modals, focused inputs) bump to `var(--dock-border-primary)` (grey-200) or `var(--dock-border-dark)` (near-black).
- Tables divide rows with `0.5px var(--dock-border-secondary)`.

### Hover, focus, press

- **Hover** is *background change only* (never a transform/scale). Ghost buttons: bg shifts from transparent → `grey-50`. Primary buttons: bg shifts from `black-light` → `grey-800`. Pills: `surface-quaternary` → `surface-quinary`.
- **Press/active** is *text/border darken* — e.g. ghost button text shifts black → `grey-800`; secondary button border shifts `black-light` → `grey-800`. **No shrink, no scale**.
- **Focus ring** is always **double**: 1px white inner ring + 2–3px `alpha-dark-10` outer ring (`0 0 0 1px var(--dock-border-light), 0 0 0 3px var(--dock-border-alpha-dark-normal)`). Works in both themes because both layers are alpha-defined.
- All transitions: `200ms` for state changes (hover/press), `300ms ease-in-out` for layout changes (navbar expand/collapse).

### Animation

- **No bounces, no spring physics, no scale-in.** The system is restrained.
- Property transitions only: opacity, background-color, border-color, color, transform-translate for nav collapse.
- Skeleton loaders use a horizontal opacity sweep, not a shimmer.
- Toasts slide-in from a corner over 200ms.

### Transparency & blur

- Backdrop blur is **not used**. The `surface-overlay` for modals is just `alpha-dark-300` (~63% black) flat.
- Alpha is used for hover surfaces (`alpha-dark-5` to `alpha-dark-25`) so the same color works on any background.

### Cards

- Default card: `bg: surface-primary (white)` / `border: 1px border-secondary` / `radius: 8–12` / **no shadow**.
- Floating card (dropdowns, popovers): `shadow-lg` + `radius: 8` + `border: 1px border-primary`.
- Press-state card: bg → `surface-secondary` (grey-50). No transform.

### Imagery

- **Cool, daylight**, no grain. Product photos for Blinkit are bright on white. Internal Dock UIs don't lean on hero imagery at all.

### Layout rules

- **Sticky header** at top, `53px` tall. Border-bottom `1px border-secondary`.
- **Sidebar nav** at left: 52px collapsed, 256px expanded. Border-right `1px border-secondary`. Default state is *collapsed* to maximise content area.
- **Page padding**: 16/24/32 horizontally depending on viewport; 24 vertically.
- **Density**: Tables run at 14px text + 12px row vertical padding by default (compact). Forms run looser, 16px text + 12px input padding.

### Protection gradients vs capsules

- **Capsules win.** Dock prefers a solid-fill pill (`surface-quaternary`) over a gradient/scrim for status badging.

---

## ICONOGRAPHY

Dock ships its own icon font — **Dockit** — at `fonts/Dockit.ttf`, with **2,090 glyphs** mapped in `assets/icon-mappings.json` and class-rendered via `assets/dockit-icons.css`.

### How icons work

```html
<!-- include once -->
<link rel="stylesheet" href="assets/dockit-icons.css">

<!-- use anywhere -->
<i class="--dock-icon-search-1"></i>
<i class="--dock-icon-notifications" style="color: var(--dock-icon-secondary)"></i>
```

Every glyph is a class on the pattern `.--dock-icon-{name}::before` that drops the Unicode codepoint into a `font-family: 'Dockit'` element. Size with `font-size`, color with `color`. No SVG markup, no React Icon component is needed for static use — the React `<Icon>` wrapper in the source just sets sizes/aria from these primitives.

### Style of the set

- **Material-influenced**, line + filled coexist (e.g. `search` vs `search-1`, `home` vs `home-1`). The `-1` suffix is the **filled** counterpart of the line/outline version.
- 1.5px–2px effective stroke at 24×24. Rounded line joins, mostly geometric.
- Black-on-transparent — color is applied via CSS `color` property at use time. There's no built-in colored icon.
- **Sizes** map to text scale: xs (12), sm (14), md (16), lg (20), xl (24).

### What's covered

The set is huge and operator-focused: filesystem (`folder`, `folder-1`, `file-pdf`), commerce/logistics (`shopping-cart`, `delivery-truck`, `inventory`, `barcode`), people/auth (`account-circle`, `logout`, `admin-panel-settings`), comms (`notifications`, `chat`, `whatsapp-logo`), navigation arrows (`chevron-right`, `arrow-back`), state (`check-circle`, `error`, `warning`, `info`), and brand-specific glyphs (`360`, `ad-group`, `apple-logo`). The line/filled pairing makes it easy to indicate selected nav state.

### When something isn't in Dockit

Dock owns the visual language — adding new icons happens upstream in the icon-font build pipeline. **No SVGs, no PNGs, no emoji** in product. Unicode is occasionally used for typography (e.g. `⌘` in keyboard hints) but never as an icon substitute. If a glyph is genuinely missing from the 2,090, the practice is to file a Dockit ticket and use the nearest existing glyph in the meantime.

### Logos

- The **Blinkit wordmark** is served from `https://cdn.grofers.com/da/consumer-web-assets/blinkit logo.webp` — the Navbar component references this URL by default. The local mock URL is recorded in `assets/blinkit-logo.url`.
- There is no separate "Dock" logo in product — Dock is internal-facing and identifies itself with its name in Lexend SemiBold next to the Blinkit mark.

---

## VISUAL DNA — quick checklist

When designing **for Blinkit/Dock**, prefer:

- ✅ Black primary actions, white background, hairline grey-100 borders
- ✅ Lexend at every weight, sentence case
- ✅ Dockit icon font with `--dock-icon-` classes
- ✅ Colorful Tag/Pill chips for status (red/green/blue/yellow/grey)
- ✅ Flat surfaces, no gradients, restrained shadows
- ✅ Compact spacing (8/12/16 horizontal, 6/8 vertical inside controls)
- ✅ Double focus ring (1px white inner + 2–3px alpha-dark outer)

Avoid:

- ❌ Green primary buttons (green is for *brand*, not for *action*)
- ❌ Drop shadows on resting cards/buttons
- ❌ Background gradients
- ❌ Emoji
- ❌ Hand-drawn or one-off SVG icons (use Dockit)
- ❌ Title Case on UI labels
- ❌ Bouncy/spring animations

---

## Quick start

```html
<link rel="stylesheet" href="colors_and_type.css">
<link rel="stylesheet" href="assets/dockit-icons.css">

<button style="
  height: var(--dock-spacing-36);
  padding: 0 var(--dock-spacing-10);
  border-radius: var(--dock-radius-6);
  background: var(--dock-surface-dark-intense);
  color: var(--dock-text-only-white);
  font: 500 14px/18px Lexend;
  border: none;
">
  <i class="--dock-icon-add" style="margin-right: 6px;"></i>
  Add product
</button>
```

---

## Caveats & TODOs

- ⚠️ **Lexend font substitution status:** the uploaded TTFs (Light/Regular/Medium/SemiBold/Bold) match the package's own `public/fonts/` exactly — no substitution needed. Lexend is also available on Google Fonts as fallback.
- ⚠️ **Logo asset is referenced via CDN** (`cdn.grofers.com`) — sandbox couldn't pre-cache it, so previews need internet access to render the wordmark. The URL is documented in `assets/blinkit-logo.url`.
- ⚠️ **Theme token coverage**: this kit ships ~600 semantic tokens; `colors_and_type.css` distills the core ~70 every app actually consumes (surface/text/icon/border × primary/secondary/tertiary × L/D + semantic states). The exhaustive `theme.json` is at `dock-design-kit/src/foundation/tokens/theme.json` if needed.
- ⚠️ **Icon font on file path**: the included `assets/dockit-icons.css` was rewritten to point at `../fonts/Dockit.ttf`. If you move files, update the `@font-face src`.
