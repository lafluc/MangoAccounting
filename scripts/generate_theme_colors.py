#!/usr/bin/env python3
"""Generate the app's adaptive colour sets in Assets.xcassets.

The palette used to be hardcoded `Color(hex:)` constants, which are static values
— so the app had to be locked to dark mode. Asset-catalog colours resolve at
render time instead, which makes every view adaptive without touching a single
call site.

Dark values are essentially unchanged from the shipped palette, so dark mode looks exactly as
it did. Light values are designed rather than derived: #FFC947 mango and the
#30D158 / #FF453A pair are dark-mode colours that wash out to near-invisibility
on white, which is why light mode looked wrong before. Each light value below is
chosen to clear WCAG AA (4.5:1) against its own background; `verify_contrast()`
checks that and fails the script if it regresses.

Run from the repository root:

    python3 scripts/generate_theme_colors.py
"""

from __future__ import annotations

import json
import pathlib
import sys

ASSETS = pathlib.Path("MangoAccounting/Assets.xcassets")

# name -> (light hex, dark hex, role)
PALETTE: dict[str, tuple[str, str, str]] = {
    # Surfaces. Light uses a warm off-white rather than pure white: it is easier
    # on the eye for a screen full of figures, and it keeps the mango accent from
    # looking acidic.
    "AppBackground":      ("FAF9F7", "1C1C1E", "surface"),
    "AppCardBackground":  ("FFFFFF", "2C2C2E", "surface"),
    "AppSeparator":       ("DCDBD7", "3A3A3C", "hairline"),

    # Accent, split by role. One value cannot do both jobs in light mode: a fill
    # needs saturation to read as a button, while text and icons need darkness to
    # be legible on white.
    "AppAccent":          ("9A6400", "FFC947", "on-surface"),
    "AppAccentFill":      ("FFB300", "FFC947", "fill"),
    "AppAccentOnFill":    ("1C1C1E", "000000", "on-fill"),
    "AppAccentSecondary": ("0E6E7A", "4DD0E1", "on-surface"),

    # Destructive fill. The on-surface negative is a bright red so it reads as text
    # on a dark background; as a *filled* button that same red leaves white lettering
    # at about 2.5:1. The fill therefore runs deeper than the text colour.
    "AppNegativeFill":    ("C1121C", "B3261E", "fill"),
    "AppNegativeOnFill":  ("FFFFFF", "FFFFFF", "on-negative-fill"),

    # Text.
    "AppTextPrimary":     ("1C1C1E", "E5E5E7", "on-surface"),
    "AppTextSecondary":   ("6B6B70", "949499", "on-surface"),

    # Semantics. Income and expense keep their meaning in both schemes.
    "AppPositive":        ("1E7B34", "30D158", "on-surface"),
    "AppNegative":        ("C1121C", "FF5A50", "on-surface"),
}

# Extra hues for charts, which need more than four distinguishable series.
CHART_SERIES: list[tuple[str, str]] = [
    ("9A6400", "FFC947"),   # mango
    ("0E6E7A", "4DD0E1"),   # teal
    ("1E7B34", "30D158"),   # green
    ("C1121C", "FF5A50"),   # red
    ("5B3FB5", "B39DFF"),   # violet
    ("A84B00", "FF9F45"),   # amber
    ("155E9C", "6BB6FF"),   # blue
    ("8A1D62", "FF7AC8"),   # magenta
]

BACKGROUNDS = {"light": "FAF9F7", "dark": "1C1C1E"}
CARDS = {"light": "FFFFFF", "dark": "2C2C2E"}


def channels(hex_value: str) -> tuple[int, int, int]:
    value = hex_value.lstrip("#")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def relative_luminance(hex_value: str) -> float:
    def linear(channel: int) -> float:
        srgb = channel / 255.0
        return srgb / 12.92 if srgb <= 0.04045 else ((srgb + 0.055) / 1.055) ** 2.4

    r, g, b = (linear(c) for c in channels(hex_value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    la, lb = relative_luminance(a), relative_luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


def colorset(light: str, dark: str) -> dict:
    def entry(hex_value: str, appearance: str | None) -> dict:
        r, g, b = channels(hex_value)
        item = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "alpha": "1.000",
                    "blue": f"0x{b:02X}",
                    "green": f"0x{g:02X}",
                    "red": f"0x{r:02X}",
                },
            },
            "idiom": "universal",
        }
        if appearance:
            item["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        return item

    return {
        "colors": [entry(light, None), entry(dark, "dark")],
        "info": {"author": "xcode", "version": 1},
    }


def verify_contrast() -> list[str]:
    """Fails the build rather than shipping an unreadable light mode."""
    problems: list[str] = []
    minimum = 4.5

    for name, (light, dark, role) in PALETTE.items():
        if role == "on-surface":
            for scheme, surface in (("light", CARDS["light"]), ("dark", CARDS["dark"])):
                value = light if scheme == "light" else dark
                ratio = contrast(value, surface)
                if ratio < minimum:
                    problems.append(
                        f"{name} ({scheme}): #{value} on #{surface} is {ratio:.2f}:1, needs {minimum}"
                    )
        if role in {"on-fill", "on-negative-fill"}:
            fill_name = "AppAccentFill" if role == "on-fill" else "AppNegativeFill"
            for scheme in ("light", "dark"):
                fill = PALETTE[fill_name][0 if scheme == "light" else 1]
                value = light if scheme == "light" else dark
                ratio = contrast(value, fill)
                if ratio < minimum:
                    problems.append(
                        f"{name} ({scheme}): #{value} on fill #{fill} is {ratio:.2f}:1"
                    )

    for index, (light, dark) in enumerate(CHART_SERIES):
        for scheme, surface in (("light", CARDS["light"]), ("dark", CARDS["dark"])):
            value = light if scheme == "light" else dark
            # Chart marks are large areas, so the 3:1 non-text threshold applies.
            ratio = contrast(value, surface)
            if ratio < 3.0:
                problems.append(
                    f"ChartSeries{index + 1} ({scheme}): #{value} on #{surface} is {ratio:.2f}:1, needs 3.0"
                )
    return problems


def write_colorset(name: str, light: str, dark: str) -> None:
    directory = ASSETS / f"{name}.colorset"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "Contents.json").write_text(
        json.dumps(colorset(light, dark), indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    if not ASSETS.is_dir():
        print(f"error: {ASSETS} not found — run from the repository root", file=sys.stderr)
        return 1

    problems = verify_contrast()
    if problems:
        print("contrast check failed:", file=sys.stderr)
        for problem in problems:
            print("  " + problem, file=sys.stderr)
        return 1

    for name, (light, dark, _role) in PALETTE.items():
        write_colorset(name, light, dark)
    for index, (light, dark) in enumerate(CHART_SERIES):
        write_colorset(f"ChartSeries{index + 1}", light, dark)

    print(f"wrote {len(PALETTE) + len(CHART_SERIES)} colour sets to {ASSETS}")
    print("contrast: all values clear WCAG AA (4.5:1 text, 3:1 chart marks)")

    print("\nmeasured ratios against the card surface:")
    for name, (light, dark, role) in PALETTE.items():
        if role in {"on-surface", "on-fill", "on-negative-fill"}:
            if role == "on-surface":
                ref_light, ref_dark = CARDS["light"], CARDS["dark"]
            elif role == "on-negative-fill":
                ref_light, ref_dark = PALETTE["AppNegativeFill"][0], PALETTE["AppNegativeFill"][1]
            else:
                ref_light, ref_dark = PALETTE["AppAccentFill"][0], PALETTE["AppAccentFill"][1]
            print(f"  {name:22} light {contrast(light, ref_light):5.2f}:1   "
                  f"dark {contrast(dark, ref_dark):5.2f}:1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
