#!/usr/bin/env python3
"""Resolve a persona's dashboard display fields (family name + home address).

These aren't transactional data, so they don't flow through dbt. Like
`data_root`, they reach the Evidence dashboard as EVIDENCE_VAR__* values that
persona.sh writes into dashboard/.env.local; a source query (sources/pfc_bank/
persona.sql) then exposes them to the page.

Both fields are configurable in persona.yaml under `identity`:

    identity:
      family_name: "Rivera"              # optional; else derived from display_name
      home_address: "742 Sagebrush Ln"   # optional; else generated from `seed`

If `home_address` is omitted, a realistic — but entirely invented — street
address is generated deterministically from the persona's `seed`, so a fresh
persona gets a plausible address for free and re-running is stable.

    uv run python synthetic/persona_meta.py --persona jordan-rivera --field home_address
    uv run python synthetic/persona_meta.py --persona jordan-rivera --env
"""
from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
PERSONAS = HERE / "personas"

# Invented street-name parts. None are real streets; combined they read like a
# plausible suburban address without naming any real place.
STREET_NAMES = [
    "Sagebrush", "Willow", "Cedar Hollow", "Juniper", "Aspen Grove", "Meadowlark",
    "Copperline", "Granite Ridge", "Riverstone", "Prairie Rose", "Hawthorn",
    "Birchwood", "Foxglen", "Larkspur", "Elkhorn", "Silverpine", "Windrow",
    "Thornapple", "Marigold", "Quailwood", "Stonegate", "Brookline", "Cottonwood",
    "Amberfield", "Hollyhock",
]
STREET_TYPES = ["Ln", "Dr", "Ct", "Way", "Rd", "Ave", "Cir", "Pl", "Trl", "Loop", "Ter"]


def generate_home_address(seed) -> str:
    """A deterministic, invented street address seeded off the persona `seed`."""
    rng = random.Random(seed)
    number = rng.randint(100, 9989)
    return f"{number} {rng.choice(STREET_NAMES)} {rng.choice(STREET_TYPES)}"


def derive_family_name(display_name: str) -> str:
    """Last whitespace-separated token of the display name, title-cased.

    "JORDAN A RIVERA" -> "Rivera".
    """
    parts = str(display_name).split()
    return parts[-1].title() if parts else ""


def resolve_identity(persona: dict) -> dict:
    """Return {'family_name', 'home_address'} for a loaded persona dict.

    Uses explicit `identity` overrides when present, else derives/generates.
    """
    identity = persona.get("identity", {}) or {}
    family = identity.get("family_name") or derive_family_name(identity.get("display_name", ""))
    address = identity.get("home_address") or generate_home_address(persona.get("seed"))
    return {"family_name": family, "home_address": address}


def resolve_persona_dir(persona_dir: Path) -> dict:
    with open(persona_dir / "persona.yaml") as f:
        persona = yaml.safe_load(f)
    return resolve_identity(persona)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--persona", default="jordan-rivera")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--field", choices=["family_name", "home_address"],
                   help="print a single resolved field")
    g.add_argument("--env", action="store_true",
                   help="print EVIDENCE_VAR__* lines for dashboard/.env.local")
    args = ap.parse_args()

    persona_dir = PERSONAS / args.persona
    if not persona_dir.is_dir():
        print(f"error: no persona '{args.persona}' under {PERSONAS}", file=sys.stderr)
        return 2

    info = resolve_persona_dir(persona_dir)
    if args.field:
        print(info[args.field])
    else:
        print(f"EVIDENCE_VAR__family_name={info['family_name']}")
        print(f"EVIDENCE_VAR__home_address={info['home_address']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
