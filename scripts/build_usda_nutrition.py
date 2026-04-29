#!/usr/bin/env python3
"""
Build GlycoTrack/Resources/usda_nutrition.json from two sources:

  1. (optional) USDA FoodData Central SR Legacy CSV bundle.
     Pass --fdc-dir /path/to/sr_legacy_csv (the directory containing
     food.csv, food_nutrient.csv, nutrient.csv).
     Download from https://fdc.nal.usda.gov/download-datasets

  2. scripts/usda_supplement.json — curated additions for foods that
     either aren't in SR Legacy under a common name (e.g. composite
     dishes, regional foods) or that we want to override.

The supplement always wins on name conflicts, since it's hand-curated
to match the GI-database name exactly (matters because the iOS seed
code joins the two databases on lowercased food name).

Output schema, one object per food:
    {"name": str, "carbs": float, "sfa": float, "tfa": float,
     "fiber": float, "pufa": float, "mufa": float}

All values are grams per 100 g edible portion.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Dict, Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "GlycoTrack" / "Resources" / "usda_nutrition.json"
DEFAULT_SUPPLEMENT = Path(__file__).resolve().parent / "usda_supplement.json"
DEFAULT_GI_DB = REPO_ROOT / "GlycoTrack" / "Resources" / "gi_database.json"

# Standard FoodData Central nutrient IDs.
NUTRIENT_IDS = {
    "carbs": 1005,  # Carbohydrate, by difference (g)
    "fiber": 1079,  # Fiber, total dietary (g)
    "sfa":   1258,  # Fatty acids, total saturated (g)
    "tfa":   1257,  # Fatty acids, total trans (g)
    "mufa":  1292,  # Fatty acids, total monounsaturated (g)
    "pufa":  1293,  # Fatty acids, total polyunsaturated (g)
}

# Words we strip from FDC descriptions before matching.
QUALIFIER_TOKENS = {
    "raw", "cooked", "boiled", "baked", "roasted", "broiled", "grilled",
    "stewed", "steamed", "canned", "frozen", "dried", "fresh",
    "with", "without", "skin", "skins", "pit", "pits", "drained",
    "solids", "liquids", "ns", "nfs", "all", "varieties",
    "commercial", "commercially", "prepared", "ready-to-eat", "ready-to-cook",
    "and", "or", "of", "in", "the",
}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--fdc-dir", type=Path, default=None,
                   help="Path to FDC SR Legacy CSV directory (optional)")
    p.add_argument("--supplement", type=Path, default=DEFAULT_SUPPLEMENT,
                   help=f"Curated supplement JSON (default: {DEFAULT_SUPPLEMENT})")
    p.add_argument("--gi-db", type=Path, default=DEFAULT_GI_DB,
                   help=f"GI database (used to filter FDC matches; default: {DEFAULT_GI_DB})")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT,
                   help=f"Output JSON path (default: {DEFAULT_OUT})")
    p.add_argument("--quiet", action="store_true", help="Suppress progress output")
    return p.parse_args(argv)


def log(quiet: bool, msg: str) -> None:
    if not quiet:
        print(msg, file=sys.stderr)


def normalize_name(raw: str) -> str:
    """Strip FDC-style qualifiers and produce a canonical lowercase name.

    'Apples, raw, with skin'              -> 'apples'
    'Beef, ground, 80% lean meat / 20% fat, cooked' -> 'beef ground'
    """
    parts = [p.strip() for p in raw.lower().split(",")]
    cleaned: list[str] = []
    for part in parts:
        tokens = [t for t in part.split() if t and t not in QUALIFIER_TOKENS]
        # Drop tokens that are pure percentages or numbers ('80%', '20%').
        tokens = [t for t in tokens if not t.endswith("%") and not t.replace(".", "").isdigit()]
        if tokens:
            cleaned.append(" ".join(tokens))
    if not cleaned:
        return raw.lower().strip()
    # Take just the first 1–2 cleaned segments — beyond that it's almost
    # always FDC's preparation noise.
    return " ".join(cleaned[:2]).strip()


def load_gi_names(path: Path) -> set[str]:
    if not path.exists():
        return set()
    data = json.loads(path.read_text())
    names: set[str] = set()
    for entry in data:
        names.add(entry["name"].lower())
        for alias in entry.get("aliases", []):
            names.add(alias.lower())
    return names


def parse_fdc(fdc_dir: Path, gi_names: set[str], quiet: bool) -> Dict[str, dict]:
    """Read FDC SR Legacy CSVs and emit one canonical entry per normalized name.

    Returns a {name: row} dict.
    """
    food_csv = fdc_dir / "food.csv"
    nutrient_csv = fdc_dir / "food_nutrient.csv"
    if not food_csv.exists() or not nutrient_csv.exists():
        raise FileNotFoundError(f"Missing food.csv or food_nutrient.csv in {fdc_dir}")

    log(quiet, f"Reading {food_csv}")
    fdc_id_to_name: Dict[int, str] = {}
    with food_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                fdc_id = int(row["fdc_id"])
            except (KeyError, ValueError):
                continue
            description = row.get("description", "")
            if not description:
                continue
            fdc_id_to_name[fdc_id] = description

    log(quiet, f"Read {len(fdc_id_to_name):,} foods")

    log(quiet, f"Reading {nutrient_csv} (this is the big one)")
    target_nutrients = {v: k for k, v in NUTRIENT_IDS.items()}
    fdc_nutrients: Dict[int, Dict[str, float]] = {}
    with nutrient_csv.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                fdc_id = int(row["fdc_id"])
                nid = int(row["nutrient_id"])
                amount = float(row["amount"])
            except (KeyError, ValueError):
                continue
            field = target_nutrients.get(nid)
            if field is None:
                continue
            fdc_nutrients.setdefault(fdc_id, {})[field] = amount

    log(quiet, f"Collected nutrient data for {len(fdc_nutrients):,} foods")

    # Pick the best entry per normalized name. Prefer GI-database matches.
    by_name: Dict[str, dict] = {}
    for fdc_id, description in fdc_id_to_name.items():
        nutrients = fdc_nutrients.get(fdc_id)
        if not nutrients:
            continue
        # Require carbs to be present (the headline number in our schema).
        # Some entries — pure oils, water — legitimately have no carbs row;
        # treat those as 0.0.
        canonical = normalize_name(description)
        if not canonical:
            continue
        # If the canonical name (or any prefix) matches a GI-database name,
        # prefer that exact form so the iOS seed code joins them.
        if canonical not in gi_names:
            # Try the first word as a fallback ("apples" matches "apple"? no — be strict).
            pass

        entry = {
            "name": canonical,
            "carbs": round(nutrients.get("carbs", 0.0), 2),
            "sfa":   round(nutrients.get("sfa", 0.0), 2),
            "tfa":   round(nutrients.get("tfa", 0.0), 2),
            "fiber": round(nutrients.get("fiber", 0.0), 2),
            "pufa":  round(nutrients.get("pufa", 0.0), 2),
            "mufa":  round(nutrients.get("mufa", 0.0), 2),
        }
        # Prefer the first one we see, but upgrade if the existing one was
        # auto-canonicalized to the same name without GI-DB membership.
        if canonical in by_name:
            existing = by_name[canonical]
            existing_in_gi = existing["name"] in gi_names
            new_in_gi = canonical in gi_names
            if new_in_gi and not existing_in_gi:
                by_name[canonical] = entry
        else:
            by_name[canonical] = entry

    log(quiet, f"Reduced FDC -> {len(by_name):,} canonical names")
    return by_name


def load_supplement(path: Path) -> Dict[str, dict]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError(f"{path} must be a JSON array")
    out: Dict[str, dict] = {}
    for entry in data:
        name = entry["name"].lower()
        out[name] = entry
    return out


def merge(fdc: Dict[str, dict], supplement: Dict[str, dict]) -> list[dict]:
    """Supplement always wins."""
    merged = dict(fdc)
    merged.update(supplement)
    # Deterministic order: alphabetical by name.
    return [merged[k] for k in sorted(merged.keys())]


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    gi_names = load_gi_names(args.gi_db)
    log(args.quiet, f"Loaded {len(gi_names):,} GI-database names (incl. aliases)")

    fdc_entries: Dict[str, dict] = {}
    if args.fdc_dir is not None:
        fdc_entries = parse_fdc(args.fdc_dir, gi_names, args.quiet)
    else:
        log(args.quiet, "No --fdc-dir provided; using supplement only.")

    supplement = load_supplement(args.supplement)
    log(args.quiet, f"Loaded {len(supplement):,} curated supplement entries from {args.supplement}")

    merged = merge(fdc_entries, supplement)
    log(args.quiet, f"Total merged entries: {len(merged):,}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(merged, indent=2, ensure_ascii=False))
    log(args.quiet, f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
