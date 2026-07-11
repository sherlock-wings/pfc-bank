#!/usr/bin/env python3
"""Preflight validator for a synthetic persona.

Checks the persona.yaml <-> merchants.yaml contract that generate.py assumes,
*before* any data is generated, so a broken persona fails with a clear,
file-scoped message ("merchants.yaml: no merchant with token 'bozeman power'")
instead of a bare KeyError traceback -- or, worse, silently generating data the
dashboard can't render.

Run standalone:
    uv run python synthetic/validate.py --persona jordan-rivera

generate.py calls validate_persona_dir() first and refuses to run on any error;
persona.sh exposes it as `./persona.sh check <slug>` and runs it before the
S3 wipe in a `--reset`, so a broken persona never destroys good data.

Errors  = the persona cannot be demoed (generate.py would crash or emit garbage).
Warnings = it will run, but something is probably not what you intended.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
from difflib import get_close_matches
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
PERSONAS = HERE / "personas"

# --------------------------------------------------------------------------- #
# The contract generate.py hard-codes. Keep this in sync with generate.py.
# --------------------------------------------------------------------------- #
# Account roles the generator's cash-flow logic references by name (KeyError if
# absent): checking (card_last4 + most flows), money_market/share_savings
# (dividends + savings transfer), credit_card (card payments), mortgage.
REQUIRED_ROLES = ["checking", "money_market", "share_savings", "credit_card", "mortgage"]
# Merchant tokens generate.py looks up by literal string -> KeyError if renamed.
HARDCODED_TOKENS = ["streamly", "patronual"]
# Looked up only in an == guard -> renaming silently drops behavior, not a crash.
SOFT_TOKENS = ["zephyr rides"]
# Categories the dashboard taxonomy renders. A merchant outside this set will
# generate + categorize but may not surface correctly on the dashboard.
KNOWN_CATEGORIES = {
    "cost-of-living", "going-out", "vice", "entertainment", "discretional",
    "subscription", "home-goods", "pet-care", "travel", "debt", "fees",
    "payments", "transfers",
}
# Categories gen_irregular() draws its weight-0 one-off events from.
IRREGULAR_CATEGORIES = {"travel", "pet-care", "discretional"}
VALID_ACCOUNTS = {"checking", "credit"}
# Regex metacharacters that would corrupt the generated seed alternation.
RE_METACHARS = set(r"()[]{}+*?\^$|")

# Nested persona keys generate.py dereferences. "a.b" means persona["a"]["b"].
REQUIRED_PERSONA = [
    "seed",
    "identity.display_name",
    "identity.org.domain", "identity.org.name", "identity.org.sfin_url",
    "identity.org.url", "identity.org.id",
    "region.state", "region.towns",
    "timeline.start_date", "timeline.as_of_date",
    "timeline.snapshot_cadence_days", "timeline.pull_window_days",
    "income.employer_display", "income.peo_display", "income.net_paycheck",
    "income.paycheck_jitter", "income.first_payday", "income.period_days",
    "discretionary.purchases_per_week_mean", "discretionary.purchases_per_week_sd",
    "discretionary.irregular_events_per_year",
    "recurring.ach_bills", "recurring.card_bills", "recurring.car_payment",
    "recurring.hoa", "recurring.mortgage_transfer", "recurring.credit_card_payment",
    "recurring.savings_transfer", "recurring.dividends",
]
# (path in persona, merchants.yaml is single-value) recurring flows that name a
# merchant by token. generate.py does self.by_token[<token>] on each.
SINGLE_MERCHANT_REFS = ["recurring.car_payment", "recurring.hoa"]
LIST_MERCHANT_REFS = ["recurring.ach_bills", "recurring.card_bills"]


class Report:
    def __init__(self):
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


def _get(d, dotted: str):
    """Return (found, value) for a dotted path into nested dicts."""
    cur = d
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return False, None
        cur = cur[part]
    return True, cur


def _load_yaml(path: Path, tag: str, r: Report):
    """Parse one YAML file; append a friendly error and return None on failure."""
    if not path.exists():
        r.err(f"{tag}: file not found at {path}")
        return None
    try:
        with open(path) as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        where = ""
        mark = getattr(e, "problem_mark", None)
        if mark is not None:
            where = f" (line {mark.line + 1}, column {mark.column + 1})"
        r.err(f"{tag}: invalid YAML{where} -- {getattr(e, 'problem', e)}")
        return None


def _suggest(token, known: list[str]) -> str:
    m = get_close_matches(str(token), known, n=1, cutoff=0.6)
    return f" -- did you mean '{m[0]}'?" if m else ""


def validate_persona_dir(persona_dir: Path):
    """Validate one persona. Returns (errors, warnings) as lists of strings."""
    r = Report()
    persona = _load_yaml(persona_dir / "persona.yaml", "persona.yaml", r)
    catalog = _load_yaml(persona_dir / "merchants.yaml", "merchants.yaml", r)
    # Can't check the contract if either file failed to parse.
    if persona is None or catalog is None:
        return r.errors, r.warnings
    if not isinstance(persona, dict):
        r.err("persona.yaml: top level must be a mapping")
        return r.errors, r.warnings
    if not isinstance(catalog, dict):
        r.err("merchants.yaml: top level must be a mapping")
        return r.errors, r.warnings

    # -- required persona keys --------------------------------------------- #
    for path in REQUIRED_PERSONA:
        found, _ = _get(persona, path)
        if not found:
            r.err(f"persona.yaml: missing required key '{path}'")

    # -- dates parse as YYYY-MM-DD ----------------------------------------- #
    for path in ("timeline.start_date", "timeline.as_of_date", "income.first_payday"):
        found, val = _get(persona, path)
        if found:
            try:
                datetime.strptime(str(val), "%Y-%m-%d")
            except (ValueError, TypeError):
                r.err(f"persona.yaml: '{path}' must be YYYY-MM-DD, got {val!r}")
    s_ok, start = _get(persona, "timeline.start_date")
    a_ok, asof = _get(persona, "timeline.as_of_date")
    if s_ok and a_ok:
        try:
            if datetime.strptime(str(start), "%Y-%m-%d") > datetime.strptime(str(asof), "%Y-%m-%d"):
                r.err(f"persona.yaml: timeline.start_date ({start}) is after as_of_date ({asof})")
        except (ValueError, TypeError):
            pass  # already reported above

    # -- towns is a non-empty list ----------------------------------------- #
    found, towns = _get(persona, "region.towns")
    if found and (not isinstance(towns, list) or not towns):
        r.err("persona.yaml: region.towns must be a non-empty list")

    # -- optional dashboard display fields (family_name / home_address) ---- #
    # These are interpolated into persona.sql as '${...}', so a single quote
    # would produce invalid SQL at `npm run sources`.
    identity = persona.get("identity") if isinstance(persona.get("identity"), dict) else {}
    for field in ("family_name", "home_address"):
        val = identity.get(field)
        if val is None:
            continue
        if not isinstance(val, str) or not val.strip():
            r.err(f"persona.yaml: identity.{field}, if set, must be a non-empty string")
        elif "'" in val:
            r.err(f"persona.yaml: identity.{field} contains a single quote, which "
                  f"would break the dashboard's persona.sql interpolation")

    # -- catalog structure ------------------------------------------------- #
    merchants = catalog.get("merchants")
    structural = catalog.get("structural_seed_rows")
    if not isinstance(merchants, list) or not merchants:
        r.err("merchants.yaml: 'merchants' must be a non-empty list")
        merchants = []
    if not isinstance(structural, list):
        r.err("merchants.yaml: 'structural_seed_rows' must be a list")
        structural = []

    by_token: dict[str, dict] = {}
    tokens: list[str] = []
    for i, m in enumerate(merchants):
        where = f"merchants.yaml: merchant #{i + 1}"
        if not isinstance(m, dict):
            r.err(f"{where} is not a mapping")
            continue
        for field in ("name", "token", "category", "subcategory", "account", "amount"):
            if field not in m:
                r.err(f"{where} ({m.get('name', '?')}) missing '{field}'")
        token = m.get("token")
        if token:
            if token in by_token:
                r.warn(f"{where}: duplicate token '{token}' (later entry wins, "
                       f"seed collapses them)")
            by_token[token] = m
            tokens.append(token)
            bad = sorted(set(str(token)) & RE_METACHARS)
            if bad:
                r.err(f"{where}: token '{token}' contains regex metacharacter(s) "
                      f"{bad} -- it would corrupt the generated seed regex")
            else:
                try:
                    re.compile(str(token))
                except re.error as e:
                    r.err(f"{where}: token '{token}' is not a valid regex ({e})")
        acct = m.get("account")
        if acct is not None and acct not in VALID_ACCOUNTS:
            r.err(f"{where}: account '{acct}' must be one of {sorted(VALID_ACCOUNTS)}")
        cat = m.get("category")
        if cat is not None and cat not in KNOWN_CATEGORIES:
            r.warn(f"{where}: category '{cat}' is outside the known taxonomy "
                   f"{sorted(KNOWN_CATEGORIES)} -- the dashboard may not render it")
        amt = m.get("amount")
        if amt is not None:
            if (not isinstance(amt, list) or len(amt) != 2
                    or not all(isinstance(x, (int, float)) for x in amt)):
                r.err(f"{where}: amount must be [min, max] numbers, got {amt!r}")
            elif amt[0] > amt[1]:
                r.err(f"{where}: amount min ({amt[0]}) is greater than max ({amt[1]})")

    for i, row in enumerate(structural):
        where = f"merchants.yaml: structural_seed_rows #{i + 1}"
        if not isinstance(row, dict):
            r.err(f"{where} is not a mapping")
            continue
        for field in ("category", "subcategory", "regex", "priority"):
            if field not in row:
                r.err(f"{where} missing '{field}'")
        rx = row.get("regex")
        if rx is not None:
            try:
                re.compile(str(rx))
            except re.error as e:
                r.err(f"{where}: regex {rx!r} does not compile ({e})")

    # -- accounts: required roles + per-account fields --------------------- #
    accounts = persona.get("accounts")
    roles: list[str] = []
    if not isinstance(accounts, list) or not accounts:
        r.err("persona.yaml: 'accounts' must be a non-empty list")
    else:
        for i, a in enumerate(accounts):
            where = f"persona.yaml: account #{i + 1}"
            if not isinstance(a, dict):
                r.err(f"{where} is not a mapping")
                continue
            role = a.get("role")
            if not role:
                r.err(f"{where} missing 'role'")
            else:
                if role in roles:
                    r.err(f"{where}: duplicate role '{role}'")
                roles.append(role)
            if "name" not in a:
                r.err(f"{where} ({role or '?'}) missing 'name'")
            if role == "mortgage":
                if "end_balance" not in a:
                    r.err(f"{where} (mortgage) missing 'end_balance'")
            else:
                for field in ("end_balance", "end_available"):
                    if field not in a:
                        r.err(f"{where} ({role or '?'}) missing '{field}'")
            if role == "checking" and "card_last4" not in a:
                r.err(f"{where} (checking) missing 'card_last4' "
                      f"(used in POS descriptions)")
        for role in REQUIRED_ROLES:
            if role not in roles:
                r.err(f"persona.yaml: no account with role '{role}' -- the "
                      f"generator's cash-flow logic requires it")

    # -- dividend roles must be real accounts ------------------------------ #
    found, dividends = _get(persona, "recurring.dividends")
    if found and isinstance(dividends, dict):
        for role in dividends:
            if role not in roles:
                r.err(f"persona.yaml: recurring.dividends references account role "
                      f"'{role}', which has no matching account")

    # -- every recurring merchant token exists in the catalog -------------- #
    def check_ref(token, ctx):
        if token is None:
            return
        if token not in by_token:
            r.err(f"persona.yaml: {ctx} references merchant token '{token}', "
                  f"but merchants.yaml has no such merchant{_suggest(token, tokens)}")

    for path in SINGLE_MERCHANT_REFS:
        found, node = _get(persona, path)
        if found and isinstance(node, dict):
            check_ref(node.get("merchant"), path)
    for path in LIST_MERCHANT_REFS:
        found, node = _get(persona, path)
        if found and isinstance(node, list):
            for j, item in enumerate(node):
                if isinstance(item, dict):
                    check_ref(item.get("merchant"), f"{path}[{j}]")

    # -- generate.py's hard-coded tokens ----------------------------------- #
    for token in HARDCODED_TOKENS:
        if token not in by_token:
            r.err(f"merchants.yaml: generate.py hard-codes merchant token "
                  f"'{token}' -- it must exist in the catalog{_suggest(token, tokens)}")
    for token in SOFT_TOKENS:
        if token not in by_token:
            r.warn(f"merchants.yaml: generate.py references token '{token}'; it is "
                   f"missing, so that behavior is silently skipped{_suggest(token, tokens)}")

    # -- the random-draw pools must be non-empty --------------------------- #
    _, mean = _get(persona, "discretionary.purchases_per_week_mean")
    if isinstance(mean, (int, float)) and mean > 0:
        if not any(isinstance(m, dict) and (m.get("weight") or 0) > 0 for m in merchants):
            r.err("merchants.yaml: purchases_per_week_mean > 0 but no merchant has "
                  "weight > 0 -- gen_discretionary would draw from an empty pool")
    _, irr = _get(persona, "discretionary.irregular_events_per_year")
    if isinstance(irr, (int, float)) and irr > 0:
        pool = [m for m in merchants if isinstance(m, dict)
                and m.get("category") in IRREGULAR_CATEGORIES and (m.get("weight") or 0) == 0]
        if not pool:
            r.err("merchants.yaml: irregular_events_per_year > 0 but no weight-0 "
                  f"merchant in {sorted(IRREGULAR_CATEGORIES)} -- gen_irregular would "
                  "draw from an empty pool")

    return r.errors, r.warnings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--persona", default="jordan-rivera",
                    help="persona slug under synthetic/personas/ (default: jordan-rivera)")
    args = ap.parse_args()

    persona_dir = PERSONAS / args.persona
    if not persona_dir.is_dir():
        available = ", ".join(sorted(p.name for p in PERSONAS.iterdir() if p.is_dir())) or "(none)"
        print(f"error: no persona '{args.persona}' under {PERSONAS} -- "
              f"available: {available}", file=sys.stderr)
        return 2

    errors, warnings = validate_persona_dir(persona_dir)
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}", file=sys.stderr)

    if errors:
        print(f"\nFAIL: persona '{args.persona}' can't be demoed "
              f"({len(errors)} error(s), {len(warnings)} warning(s)). "
              f"Fix the errors above and re-run.", file=sys.stderr)
        return 1
    print(f"PASS: persona '{args.persona}' is valid "
          f"({len(warnings)} warning(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
