/**
 * Ported by hand from Shui/Sources/Theme/ThemePalettes.swift and
 * Shui/Sources/Theme/Theme.swift — every hex value here must match its
 * Swift source exactly, since the whole point is that the two surfaces
 * (phone app, this dashboard) read as one product. If a value changes on
 * the Swift side, update it here too; there is no automated sync between
 * them, this is the single point where that has to happen by hand.
 *
 * Only light mode is wired up in `index.css`'s `@theme` block for now —
 * the dashboard doesn't yet offer a dark-mode toggle. Both palettes are
 * kept here so that toggle is a matter of switching which object
 * `index.css` reads from, not re-deriving the colors.
 */

export const lightPalette = {
  canvas: "#F4F3EF",
  surface: "#FFFFFF",
  surfaceSubtle: "#EAE8E1",

  textPrimary: "#1A1A1A",
  textSecondary: "#57534E",
  textTertiary: "#78716C",
  textOnAccent: "#FFFFFF",

  accent: "#B4530A",
  accentGradientStops: ["#B4530A", "#9A4A6B", "#4338CA"] as const,

  border: "#928B7C",
  borderSubtle: "#DDD9D0",

  success: "#15803D",
  warning: "#9A5B0A",
  error: "#B91C1C",
  info: "#1D4ED8",
} as const;

export const darkPalette = {
  canvas: "#18140F",
  surface: "#241E17",
  surfaceSubtle: "#2E271D",

  textPrimary: "#F5F1EA",
  textSecondary: "#B8AFA1",
  textTertiary: "#8C8375",
  textOnAccent: "#18140F",

  accent: "#F0A94E",
  accentGradientStops: ["#F0A94E", "#E08FA8", "#9CA3F5"] as const,

  border: "#827664",
  borderSubtle: "#3A3226",

  success: "#4ADE80",
  warning: "#F3B13C",
  error: "#F87171",
  info: "#60A5FA",
} as const;

/** Theme.swift's non-color layout tokens. */
export const radius = {
  card: "20px",
  large: "32px",
} as const;

export type Palette = typeof lightPalette;
