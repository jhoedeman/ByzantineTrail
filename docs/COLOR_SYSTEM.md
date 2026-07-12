# Byzantine Trail — Color System

**Version:** 1.1 (reconciled with build spec) · Place in repo as `docs/COLOR_SYSTEM.md`

**App profile:** Image-heavy mobile app, Byzantine heritage. Palette draws from imperial gold, crimson red, warm stone, and mosaic-inspired accents.

---

## 1. Tonal Scales

### Imperial Gold — "Chrysos" (Primary)
Warm Byzantine gold. References mosaic tesserae and the imperial standard.

| Step | Hex | RGB | Use |
|------|-----|-----|-----|
| Gold-50 | `#FDF8E8` | 253 248 232 | Tinted backgrounds, pressed states |
| Gold-100 | `#FAF0C7` | 250 240 199 | Subtle fills |
| Gold-200 | `#F5DC86` | 245 220 134 | Decorative borders |
| Gold-300 | `#EEC845` | 238 200 69 | Illustrative / decorative |
| Gold-400 | `#E0B022` | 224 176 34 | **Dark mode accent text** |
| Gold-500 | `#C9A020` | 201 160 32 | Brand illustrations |
| Gold-600 | `#A88018` | 168 128 24 | Large UI labels (light mode) |
| Gold-700 | `#856412` | 133 100 18 | **Light mode accent text (AA ✓)** |
| Gold-800 | `#62480C` | 98 72 12 | **Body accent text (AAA ✓)** |
| Gold-900 | `#3F2E07` | 63 46 7 | Deep tones |
| Gold-950 | `#201703` | 32 23 3 | Near-black gold |

### Byzantine Crimson — "Kókkinos" (Secondary)
Imperial crimson-red. The color of the flag, imperial vestments, and power.

| Step | Hex | RGB | Use |
|------|-----|-----|-----|
| Red-50 | `#FDF0EF` | 253 240 239 | Error backgrounds |
| Red-100 | `#FAD4D2` | 250 212 210 | Error tints |
| Red-200 | `#F4A9A5` | 244 169 165 | Illustrative |
| Red-300 | `#E87470` | 232 116 112 | **Dark mode secondary text (AA ✓)** |
| Red-400 | `#D44040` | 212 64 64 | Dark mode large elements |
| Red-500 | `#B82020` | 184 32 32 | Mid-tone |
| Red-600 | `#9B1B1B` | 155 27 27 | **Light mode secondary (AAA ✓)** |
| Red-700 | `#7A1414` | 122 20 20 | Dark emphasis |
| Red-800 | `#5A0F0F` | 90 15 15 | Deep crimson |
| Red-900 | `#3B0808` | 59 8 8 | Near-black red |
| Red-950 | `#1E0404` | 30 4 4 | Shadow tones |

### Warm Stone — "Lithos" (Neutral)
Aged parchment and ancient stone. Warm undertone complements gold without competing with images.

| Step | Hex | RGB | Use |
|------|-----|-----|-----|
| Stone-0 | `#FFFFFF` | 255 255 255 | Pure white |
| Stone-50 | `#FAF8F3` | 250 248 243 | App background (light) |
| Stone-100 | `#F2EDE3` | 242 237 227 | Card surfaces (light) |
| Stone-200 | `#E5DDD0` | 229 221 208 | Borders (light) |
| Stone-300 | `#D0C1AC` | 208 193 172 | Subtle borders |
| Stone-400 | `#B5A289` | 181 162 137 | Placeholder text; minor-tier pins |
| Stone-500 | `#97816A` | 151 129 106 | Disabled text |
| Stone-600 | `#7B6554` | 123 101 84 | Secondary text (dark mode) |
| Stone-700 | `#5F4E40` | 95 78 64 | Muted text (light mode) |
| Stone-800 | `#3E322A` | 62 50 42 | Elevated surface (dark) |
| Stone-900 | `#251D17` | 37 29 23 | Card surface (dark) |
| Stone-950 | `#130F0B` | 19 15 11 | App background (dark) |

---

## 2. Semantic Token Mapping

These tokens map 1:1 to the app's `Theme` struct (Swift-cased, e.g. `bg-card-alt` → `bgCardAlt`). No feature code uses raw hex.

### Light Mode

| Token | Value | Hex |
|-------|-------|-----|
| `bg-app` | Stone-50 | `#FAF8F3` |
| `bg-card` | Stone-0 | `#FFFFFF` |
| `bg-card-alt` | Stone-100 | `#F2EDE3` |
| `bg-image-overlay` | Stone-950 @ 50% | — |
| `border-subtle` | Stone-200 | `#E5DDD0` |
| `border-default` | Stone-300 | `#D0C1AC` |
| `text-primary` | Stone-900 | `#251D17` |
| `text-secondary` | Stone-700 | `#5F4E40` |
| `text-disabled` | Stone-500 | `#97816A` |
| `text-on-image` | Stone-0 | `#FFFFFF` |
| `accent-primary` | Gold-700 | `#856412` |
| `accent-primary-subtle` | Gold-50 | `#FDF8E8` |
| `accent-secondary` | Red-600 | `#9B1B1B` |
| `interactive-cta-bg` | Gold-700 | `#856412` |
| `interactive-cta-text` | Stone-0 | `#FFFFFF` |
| `interactive-cta-pressed` | Gold-800 | `#62480C` |

### Dark Mode

| Token | Value | Hex |
|-------|-------|-----|
| `bg-app` | Stone-950 | `#130F0B` |
| `bg-card` | Stone-900 | `#251D17` |
| `bg-card-alt` | Stone-800 | `#3E322A` |
| `bg-image-overlay` | Stone-950 @ 60% | — |
| `border-subtle` | Stone-800 | `#3E322A` |
| `border-default` | Stone-700 | `#5F4E40` |
| `text-primary` | Stone-50 | `#FAF8F3` |
| `text-secondary` | Stone-300 | `#D0C1AC` |
| `text-disabled` | Stone-600 | `#7B6554` |
| `text-on-image` | Stone-0 | `#FFFFFF` |
| `accent-primary` | Gold-400 | `#E0B022` |
| `accent-primary-subtle` | Stone-800 | `#3E322A` |
| `accent-secondary` | Red-300 | `#E87470` |
| `interactive-cta-bg` | Gold-400 | `#E0B022` |
| `interactive-cta-text` | Stone-950 | `#130F0B` |
| `interactive-cta-pressed` | Gold-300 | `#EEC845` |

### App-Specific Tokens (Byzantine Trail)

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `tier-major` | Gold-500 `#C9A020` | Gold-400 `#E0B022` | Major-tier pins & badges |
| `tier-notable` | Terracotta `#C26940` | Terracotta `#FB923C` | Notable-tier pins & badges |
| `tier-minor` | Stone-400 `#B5A289` | Stone-400 `#B5A289` | Minor-tier pins & badges |
| `rating-display` | Gold-700 `#856412` | Gold-400 `#E0B022` | 1–10 rating numerals & average |
| `visited-check` | Jade `#2A7A4E` | Jade `#4AC480` | Visited checkmarks (rows, detail, pin badge) |

Tier colors come from the Mosaic categorical palette (§5) — Gold/Terracotta/Stone are well-separated for colorblind users. Tier *badges on text surfaces* pair the tier color with a `text-primary` label or use the tier color for the glyph only; never tier color as small text on white (Gold-500 fails contrast — see §3).

### Semantic States

| Role | Light | Dark | Notes |
|------|-------|------|-------|
| **Success** | `#2A7A4E` (Byzantine jade) | `#4AC480` | Visited checkmarks, confirmations |
| **Warning** | `#D97706` (amber) | `#F59E0B` | Closure alerts |
| **Error** | Red-600 `#9B1B1B` | Red-300 `#E87470` | Destructive actions |
| **Info** | `#2563A8` (lapis blue) | `#60A5FA` | Tips, notes |

---

## 3. Accessibility Contrast Matrix

WCAG 2.1 thresholds: **AA normal text** ≥ 4.5:1 · **AA large text / UI** ≥ 3:1 · **AAA** ≥ 7:1

### Light Mode

| Foreground | Background | Ratio | Rating |
|------------|-----------|-------|--------|
| Gold-700 `#856412` | White `#FFFFFF` | **5.4:1** | AA ✓ |
| Gold-800 `#62480C` | White `#FFFFFF` | **8.6:1** | AAA ✓ |
| Gold-600 `#A88018` | White `#FFFFFF` | 3.7:1 | Large only |
| Gold-500 `#C9A020` | White `#FFFFFF` | 2.4:1 | ✗ Decorative only |
| Red-600 `#9B1B1B` | White `#FFFFFF` | **8.2:1** | AAA ✓ |
| Stone-900 `#251D17` | Stone-50 `#FAF8F3` | **14.1:1** | AAA ✓ |
| Stone-700 `#5F4E40` | Stone-50 `#FAF8F3` | **6.8:1** | AA ✓ |
| White `#FFFFFF` | Stone-950 overlay @ 50% | ~5.5:1 | AA ✓ |

### Dark Mode

| Foreground | Background | Ratio | Rating |
|------------|-----------|-------|--------|
| Gold-400 `#E0B022` | Stone-950 `#130F0B` | **9.7:1** | AAA ✓ |
| Gold-300 `#EEC845` | Stone-950 `#130F0B` | **12.1:1** | AAA ✓ |
| Red-300 `#E87470` | Stone-950 `#130F0B` | **6.6:1** | AA ✓ |
| Stone-50 `#FAF8F3` | Stone-950 `#130F0B` | **16.4:1** | AAA ✓ |
| Stone-300 `#D0C1AC` | Stone-950 `#130F0B` | **9.3:1** | AAA ✓ |
| Stone-50 `#FAF8F3` | Stone-900 `#251D17` | **10.5:1** | AAA ✓ |
| Gold-400 `#E0B022` | Stone-900 `#251D17` | **6.2:1** | AA ✓ |

> **Key rule:** Never use Gold-500 or lighter for text on white. Use Gold-700+ in light mode, Gold-400 in dark mode.

---

## 4. Dark Mode Design Notes

Dark mode is the **aesthetic showcase** for this app — Byzantine mosaics and church interiors are famously dark; deep backgrounds make gold accents luminous and let photographs breathe. (The app still defaults to the system appearance setting per iOS convention; this section describes how good dark mode should look, not a forced default.)

**Surface elevation model (dark mode):**

```
Stone-950  bg-app         #130F0B   ← deepest: navigation chrome
Stone-900  bg-card        #251D17   ← content cards, list items
Stone-800  bg-card-alt    #3E322A   ← modals, bottom sheets, map UI
Stone-700  border          #5F4E40  ← dividers
```

**Image treatment:**
- Full-bleed hero images: no overlay unless text sits on top
- Text-over-image: `Stone-950 @ 55%` gradient scrim from bottom
- Thumbnail cards: `Stone-900` background, `1px Stone-700` border

**Gold behavior in dark mode:**
Gold-400/300 "glows" against the near-black stone backgrounds — this is intentional. Use it for:
- Major-tier map pins
- Section headers / category labels
- CTA buttons
- Decorative divider lines

---

## 5. Data Visualization Colors

Data viz appears in: maps (cluster counts), profile progress stats (visited counts, Gilded progress bar), and future charts/timelines.

### Categorical Palette — "Mosaic" (7 colors)

| # | Name | Light Hex | Dark Hex | Meaning |
|---|------|-----------|----------|---------|
| 1 | Imperial Gold | `#C9A020` | `#E0B022` | Primary metric, selected state; **tier: major** |
| 2 | Byzantine Crimson | `#9B1B1B` | `#E87470` | Secondary metric, alerts |
| 3 | Lapis Blue | `#2563A8` | `#60A5FA` | Info, water, distance |
| 4 | Mosaic Jade | `#2A7A4E` | `#4ADE80` | **Visited / completed** |
| 5 | Tyrian Violet | `#6B3FA0` | `#C084FC` | Imperial era, highlights (e.g., UNESCO badge) |
| 6 | Terracotta | `#C26940` | `#FB923C` | **Tier: notable**; architecture, earthen |
| 7 | Parchment | `#B8A880` | `#D4C5A0` | Inactive, background category |

> **Contrast-safe on dark bg `#130F0B`:** All 7 dark-mode swatches exceed 3:1 against Stone-950. Lapis, Jade, Violet meet 4.5:1. For data labels, use Stone-50 or the dark-mode swatch itself.

### Sequential Scale — "Gilded" (density / progress)

```
Low ──────────────────────────────────── High
#F2EDE3  #F5DC86  #E0B022  #A88018  #3F2E07
Stone-100  Gold-200  Gold-400  Gold-600  Gold-900
```

### Diverging Scale — "Byzantine"

```
Negative ──────────── Neutral ──────────── Positive
#9B1B1B  #D44040  #FAF8F3  #A88018  #3F2E07
Red-600   Red-400  Stone-50  Gold-600  Gold-900
```

---

## 6. Usage Guidelines

### Do
- Use **gold as the primary accent** for interactive elements, not as a background fill — reserve large gold areas for decorative/illustrative moments
- Let **full-bleed photography** dominate; color tokens exist to frame it, not compete
- In dark mode, lean into the **glowing gold on deep stone** aesthetic — this is authentic to the subject matter
- Use **Tyrian Violet** sparingly — only for the most iconic/featured content (e.g., "UNESCO Site" badges from the `unesco` tag)
- Apply **Stone-950 @ 50–60%** overlays on image cards where text must appear — never pure black

### Don't
- Don't use Gold-500 or lighter for text on light backgrounds — it fails WCAG contrast
- Don't combine Crimson and Lapis Blue as adjacent categorical colors — low chroma differentiation for colorblind users; separate them with Gold or Jade
- Don't use the Crimson scale for anything other than error states, the `accent-secondary` role, and decorative Byzantine-themed elements — it reads as destructive/urgent at higher saturations
- Don't render historical timeline labels in Gold on white cards — use Stone-800 for legibility

### Map UI specifics (tier-based, per build spec §5.3)
- **Pin fill by importance tier:** Major = `tier-major` (Gold-500 light / Gold-400 dark) · Notable = `tier-notable` (Terracotta) · Minor = `tier-minor` (Stone-400). All pins: Stone-950 stroke.
- **Visited sites:** keep tier fill, add a small `visited-check` jade checkmark badge on the pin.
- **Selected pin:** tier fill, Gold-300 stroke, drop shadow Gold-900 @ 30%, slightly enlarged.
- **Cluster badges:** Stone-950 bg, Gold-400 text.

---

## 7. Implementation Notes

- Implement tokens as an asset catalog (light/dark variants per color) or computed `Theme` pairs; the `Theme` struct in `Core/Theme/` is the single source of truth in code (build spec §5.5).
- "Pressed" states replace web hover; on iPad, pointer-hover may reuse the pressed color at reduced opacity.
- This palette is the launch theme ("Chrysos"). Future alternate palettes are additional `Theme` instances (potential paywall item) and must define every token in §2, including the app-specific tokens.
