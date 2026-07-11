#!/usr/bin/env python3
"""Generate a synthetic, shareable clone of the real SimpleFIN dataset.

Reads persona.yaml + merchants.yaml and emits:
  * out/transactions/YYYY/MM/DD/<ts>Z_bd<bd>.json  — SimpleFIN snapshots,
    byte-compatible with workbench/*.json and the extract.py S3 layout.
  * out/seed_merchant_category_regex_mapping.csv    — a regex seed regenerated
    from the SAME merchant catalog, so the dbt categorizer matches 100% of the
    demo data (no **UNKNOWN**, assert_no_unknown_merchants stays green).

Everything is driven by one fixed RNG seed, so re-running produces identical
output. A single master ledger of transactions (with stable TRN ids) is built
once; each snapshot is just the trailing window of that ledger, so the dbt
dedup (partition by txn_id) sees real overlap to collapse.

Personas live under synthetic/personas/<slug>/{persona,merchants}.yaml. Pick one
with --persona; output defaults to synthetic/out/<slug>.

Usage:
    uv run python synthetic/generate.py                        # persona jordan-rivera
    uv run python synthetic/generate.py --persona casey-brooks # a different persona
    uv run python synthetic/generate.py --out /tmp/demo        # custom output dir
    uv run python synthetic/generate.py --write-dbt-seed       # also overwrite the
        # committed dbt seed (only do this when publishing the demo, NOT on the
        # machine that runs your real pipeline).
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import sys
import uuid
from calendar import monthrange
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
PERSONAS = HERE / "personas"
UTC = timezone.utc


# --------------------------------------------------------------------------- #
# config loading
# --------------------------------------------------------------------------- #
def load_configs(persona_dir: Path):
    with open(persona_dir / "persona.yaml") as f:
        persona = yaml.safe_load(f)
    with open(persona_dir / "merchants.yaml") as f:
        catalog = yaml.safe_load(f)
    return persona, catalog


def parse_date(s: str) -> datetime:
    return datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=UTC)


# ACH descriptor words keyed by merchant token (bank-style memo fragments).
ACH_DESCRIPTORS = {
    "bozeman power": "DRAFT",
    "nimbus fiber": "CABLE SVCS",
    "ironoak": "CLUB FEES",
    "aquacivic": "UTILITY DRAFT",
    "cascade auto": "AUTO PAY",
    "kestrel ridge": "ASSN DUES",
}
# Fake counterparties for peer-to-peer (never a real person).
P2P_NAMES = ["CASEY MORGAN", "DREW ELLIS", "SAM OKAFOR", "RILEY BROOKS", "TARA VOSS"]


class Generator:
    def __init__(self, persona, catalog):
        self.p = persona
        self.rng = random.Random(persona["seed"])
        self.merchants = catalog["merchants"]
        self.structural_rows = catalog["structural_seed_rows"]
        self.by_token = {m["token"]: m for m in self.merchants}
        self.towns = persona["region"]["towns"]
        self.state = persona["region"]["state"]
        self.name = persona["identity"]["display_name"]
        self.accounts = {a["role"]: a for a in persona["accounts"]}
        self.start = parse_date(persona["timeline"]["start_date"])
        self.as_of = parse_date(persona["timeline"]["as_of_date"])
        self.ledger: list[dict] = []  # master list of transaction dicts

    # -- small helpers ----------------------------------------------------- #
    def tid(self) -> str:
        return "TRN-" + str(uuid.UUID(int=self.rng.getrandbits(128)))

    def town(self) -> str:
        return self.rng.choice(self.towns)

    def digits(self, n: int) -> str:
        return "".join(self.rng.choice("0123456789") for _ in range(n))

    def money(self, lo: float, hi: float) -> float:
        return round(self.rng.uniform(lo, hi), 2)

    def add(self, role, dt, amount, description, payee, post_lag_days=None):
        """Append one transaction to the master ledger."""
        # merchants.yaml uses the short account label "credit"; the account
        # role is "credit_card". Normalise so ledger roles match self.accounts.
        role = "credit_card" if role == "credit" else role
        if post_lag_days is None:
            post_lag_days = self.rng.choice([0, 0, 0, 1, 1, 2])
        posted_dt = (dt + timedelta(days=post_lag_days)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        self.ledger.append(
            {
                "role": role,
                "id": self.tid(),
                "posted": int(posted_dt.timestamp()),
                "transacted_at": int(dt.timestamp()),
                "amount": round(amount, 2),
                "description": description,
                "payee": payee,
            }
        )

    # -- description formatting -------------------------------------------- #
    def describe(self, m, fmt=None):
        """Return (description, payee) for a purchase at merchant `m`."""
        token = m["token"]
        fmt = fmt or m.get("format") or (
            "cc_purchase" if m["account"] == "credit" else "pos_debit"
        )
        town = self.town()
        payee = m["name"]
        if fmt == "pos_debit":
            last4 = self.accounts["checking"]["card_last4"]
            desc = (
                f"POS Debit - Visa Check Card {last4} - "
                f"{token.upper()} {town} {self.name} POS TRANSACTION"
            )
        elif fmt == "pos_alt":
            last4 = self.accounts["checking"]["card_last4"]
            desc = f"Pos Debit-    XXXX {last4} {token.title()} {town.title()}  US"
        elif fmt == "ach":
            descriptor = ACH_DESCRIPTORS.get(token, "PAYMENT")
            desc = f"ACH Transaction - {token.upper()} {descriptor} {self.digits(10)} ACH DEBIT"
        elif fmt == "cc_tst":
            desc = f"TST*{token.upper()} {town.title()}{self.state}"
        else:  # cc_purchase
            desc = f"{token.title()}   {town.title()}  {self.state}"
        return desc, payee

    # -- month iteration --------------------------------------------------- #
    def months(self):
        """Yield the first-of-month datetime for every month in range."""
        y, mo = self.start.year, self.start.month
        while True:
            dt = datetime(y, mo, 1, tzinfo=UTC)
            if dt > self.as_of:
                break
            yield dt
            mo += 1
            if mo > 12:
                mo = 1
                y += 1

    def on_day(self, month_dt, day, hour=None):
        """A datetime on `day` of month_dt's month, clamped to month length."""
        last = monthrange(month_dt.year, month_dt.month)[1]
        d = min(day, last)
        h = hour if hour is not None else self.rng.randint(8, 21)
        return month_dt.replace(day=d, hour=h, minute=self.rng.randint(0, 59), second=self.rng.randint(0, 59))

    def in_range(self, dt):
        return self.start <= dt <= self.as_of

    # -- transaction streams ---------------------------------------------- #
    def gen_income(self):
        inc = self.p["income"]
        pay = parse_date(inc["first_payday"])
        while pay <= self.as_of:
            if pay >= self.start:
                amt = round(inc["net_paycheck"] + self.rng.uniform(-1, 1) * inc["paycheck_jitter"], 2)
                emp = self.rng.choice([inc["employer_display"], inc["peo_display"]])
                desc = f"Deposit - {emp} {emp} DEPOSIT"
                self.add("checking", pay.replace(hour=6), amt, desc, inc["employer_display"].title())
            pay += timedelta(days=inc["period_days"])

    def gen_recurring(self):
        rec = self.p["recurring"]
        for month_dt in self.months():
            # ACH bills (checking debits)
            for bill in rec["ach_bills"]:
                m = self.by_token[bill["merchant"]]
                dt = self.on_day(month_dt, bill["day"])
                if not self.in_range(dt):
                    continue
                amt = -round(bill["amount"] + self.rng.uniform(-1, 1) * bill["jitter"], 2)
                desc, payee = self.describe(m, "ach")
                self.add("checking", dt, amt, desc, payee)
            # card bills (debit POS)
            for bill in rec["card_bills"]:
                m = self.by_token[bill["merchant"]]
                dt = self.on_day(month_dt, bill["day"])
                if not self.in_range(dt):
                    continue
                amt = -round(bill["amount"] + self.rng.uniform(-1, 1) * bill["jitter"], 2)
                desc, payee = self.describe(m, m.get("format"))
                self.add("checking", dt, amt, desc, payee)
            # car payment (ACH from checking)
            cp = rec["car_payment"]
            dt = self.on_day(month_dt, cp["day"])
            if self.in_range(dt):
                m = self.by_token[cp["merchant"]]
                desc, payee = self.describe(m, "ach")
                self.add("checking", dt, -cp["amount"], desc, payee)
            # HOA (ACH from checking)
            hoa = rec["hoa"]
            dt = self.on_day(month_dt, hoa["day"])
            if self.in_range(dt):
                m = self.by_token[hoa["merchant"]]
                desc, payee = self.describe(m, "ach")
                self.add("checking", dt, -hoa["amount"], desc, payee)
            # mortgage transfer (checking -> mortgage; mortgage acct stays empty)
            mt = rec["mortgage_transfer"]
            dt = self.on_day(month_dt, mt["day"])
            if self.in_range(dt):
                self.add("checking", dt, -mt["amount"],
                         "Transfer to Mortgage TRF TO OTHER", "Transfer to Other")
            # savings transfer (both legs)
            st = rec["savings_transfer"]
            dt = self.on_day(month_dt, st["day"])
            if self.in_range(dt):
                self.add("checking", dt, -st["amount"],
                         "Transfer to Savings TRF TO OTHER", "Transfer to Other")
                self.add("money_market", dt, st["amount"],
                         "Transfer from Checking TRF FR OTHER", "Transfer From Checking")
            # dividends + fed tax withholding on savings accounts
            for role, dv in rec["dividends"].items():
                dt = self.on_day(month_dt, dv["day"])
                if not self.in_range(dt):
                    continue
                amt = round(dv["amount"] + self.rng.uniform(-1, 1) * dv["jitter"], 2)
                amt = max(amt, 0.1)
                self.add(role, dt, amt, "Dividend (GT20)DIVIDEND", "Dividend")
                tax = -round(amt * self.rng.uniform(0.02, 0.24), 2)
                if tax < 0:
                    self.add(role, dt, tax,
                             "Federal Tax Withholding (GT21)FED TAX WITHLD",
                             "Federal Tax Withholding")

    def gen_discretionary(self):
        pool = [m for m in self.merchants if m.get("weight", 0) > 0]
        weights = [m["weight"] for m in pool]
        disc = self.p["discretionary"]
        week = self.start
        while week <= self.as_of:
            n = max(0, int(round(self.rng.gauss(
                disc["purchases_per_week_mean"], disc["purchases_per_week_sd"]))))
            for _ in range(n):
                m = self.rng.choices(pool, weights=weights, k=1)[0]
                dt = week + timedelta(days=self.rng.uniform(0, 7),
                                      hours=self.rng.uniform(0, 12))
                if not self.in_range(dt):
                    continue
                amt = -self.money(*m["amount"])
                desc, payee = self.describe(m)
                self.add(m["account"], dt, amt, desc, payee)
                # rideshare/subscription-style international fee, occasionally
                if m["token"] == "zephyr rides" and self.rng.random() < 0.12:
                    self.add(m["account"], dt, -round(abs(amt) * 0.03, 2),
                             f"International Transaction fee {payee} Ride IE INTL TRANSACTION FEE",
                             "International Transaction Fee")
            week += timedelta(days=7)

    def gen_subscriptions(self):
        # Monthly streaming (credit) + a content-creator sub (checking) that
        # carries an international transaction fee, mirroring the real profile.
        for month_dt in self.months():
            streamly = self.by_token["streamly"]
            dt = self.on_day(month_dt, 12)
            if self.in_range(dt):
                desc, payee = self.describe(streamly)
                self.add("credit", dt, -streamly["amount"][0], desc, payee)
            patronual = self.by_token["patronual"]
            dt = self.on_day(month_dt, 18)
            if self.in_range(dt):
                amt = -self.money(*patronual["amount"])
                desc, payee = self.describe(patronual)
                self.add("checking", dt, amt, desc, payee)
                fee = -round(abs(amt) * 0.02, 2)
                self.add("checking", dt, fee,
                         "International Transaction fee Patronual Membership IE INTL TRANSACTION FEE",
                         "International Transaction Fee")

    def gen_card_payments_and_interest(self):
        """Monthly checking->card payment sized to recent card spend, plus a
        small revolving interest charge on the card."""
        rec = self.p["recurring"]
        pay_day = rec["credit_card_payment"]["day"]
        for month_dt in self.months():
            dt = self.on_day(month_dt, pay_day, hour=9)
            if not self.in_range(dt):
                continue
            lo = dt - timedelta(days=32)
            hi = dt - timedelta(days=2)
            spend = sum(-t["amount"] for t in self.ledger
                        if t["role"] == "credit_card" and t["amount"] < 0
                        and lo.timestamp() <= t["posted"] <= hi.timestamp())
            if spend <= 0:
                continue
            # checking side: labeled transfer (debt/credit card payment)
            self.add("checking", dt, -round(spend, 2),
                     "Transfer to Credit Card TRF TO OTHER", "Transfer to Other")
            # card side: payment received (payments/online payment)
            self.add("credit", dt + timedelta(days=1), round(spend, 2),
                     "NFO PAYMENT RECEIVED", "Nfo Payment")
            # revolving interest charge (debt/credit card interest)
            interest = round(self.rng.uniform(0, 26), 2)
            if interest > 0:
                self.add("credit", dt, -interest,
                         "Interest Charge on Purchases", "Interest Charge")

    def gen_structural_extras(self):
        # ATM withdrawals (~monthly), p2p (~2x/month), rewards + refunds (rare).
        for month_dt in self.months():
            if self.rng.random() < 0.8:
                dt = self.on_day(month_dt, self.rng.randint(1, 27))
                if self.in_range(dt):
                    amt = -float(self.rng.choice([40, 60, 80, 100, 120]))
                    self.add("checking", dt, amt,
                             f"ATM Withdrawal {self.town().title()} {self.digits(4)}", "Atm Withdrawal")
            for _ in range(self.rng.randint(0, 3)):
                dt = self.on_day(month_dt, self.rng.randint(1, 27))
                if not self.in_range(dt):
                    continue
                other = self.rng.choice(P2P_NAMES)
                if self.rng.random() < 0.5:
                    amt = -self.money(10, 120)
                    self.add("checking", dt, amt,
                             f"ZELLE HARD POST - ZELLE DB {other} ZELLE DB {other} ZELLE DEBIT",
                             f"Zelle {other.title()}")
                else:
                    amt = self.money(10, 90)
                    self.add("checking", dt, amt,
                             f"VENMO CASHOUT {other} VENMO PAYMENT", f"Venmo {other.title()}")
            if self.rng.random() < 0.3:
                dt = self.on_day(month_dt, self.rng.randint(1, 27))
                if self.in_range(dt):
                    self.add("credit", dt, self.money(0.5, 35),
                             "REWARD REDEMPTION JVS REWARD REDEMPTION ADJUSTMENT CR",
                             "Reward Redemption")
            if self.rng.random() < 0.2:
                dt = self.on_day(month_dt, self.rng.randint(1, 27))
                if self.in_range(dt):
                    self.add("credit", dt, self.money(5, 80),
                             "POS Adjustment Refund Credit", "Pos Adjustment")

    def gen_irregular(self):
        events = [m for m in self.merchants
                  if m["category"] in ("travel", "pet-care", "discretional")
                  and m.get("weight", 0) == 0]
        years = (self.as_of - self.start).days / 365.25
        count = int(self.p["discretionary"]["irregular_events_per_year"] * years)
        for _ in range(count):
            m = self.rng.choice(events)
            dt = self.start + timedelta(days=self.rng.uniform(0, (self.as_of - self.start).days))
            amt = -self.money(*m["amount"])
            desc, payee = self.describe(m)
            self.add(m["account"], dt, amt, desc, payee)

    # -- build + emit ------------------------------------------------------ #
    def build_ledger(self):
        self.gen_income()
        self.gen_recurring()
        self.gen_subscriptions()
        self.gen_discretionary()
        self.gen_irregular()
        self.gen_card_payments_and_interest()  # depends on discretionary card spend
        self.gen_structural_extras()
        self.ledger.sort(key=lambda t: t["posted"])

    def account_balance(self, role, snap_dt):
        """Balance for `role` as of snap_dt, consistent with the ledger."""
        acct = self.accounts[role]
        if role == "mortgage":
            months_after = 0
            probe = snap_dt.replace(day=1)
            while probe < self.as_of.replace(day=1):
                months_after += 1
                y, mo = probe.year, probe.month + 1
                if mo > 12:
                    mo, y = 1, y + 1
                probe = probe.replace(year=y, month=mo)
            bal = acct["end_balance"] + acct.get("monthly_principal", 0) * months_after
            return round(bal, 2), 0.0
        later = sum(t["amount"] for t in self.ledger
                    if t["role"] == role and t["posted"] > int(snap_dt.timestamp()))
        bal = round(acct["end_balance"] - later, 2)
        avail = round(bal + (acct["end_available"] - acct["end_balance"]), 2)
        return bal, avail

    def snapshot_dates(self):
        cadence = self.p["timeline"]["snapshot_cadence_days"]
        dates, d = [], self.as_of
        while d >= self.start:
            dates.append(d)
            d = d - timedelta(days=cadence)
        return sorted(dates)

    def txn_json(self, t):
        return {
            "id": t["id"],
            "posted": t["posted"],
            "amount": f"{t['amount']:.2f}",
            "description": t["description"],
            "payee": t["payee"],
            "memo": "",
            "transacted_at": t["transacted_at"],
            "mcc": None,
        }

    def emit_snapshots(self, out_dir: Path):
        window = self.p["timeline"]["pull_window_days"]
        org = self.p["identity"]["org"]
        org_block = {
            "domain": org["domain"], "name": org["name"],
            "sfin-url": org["sfin_url"], "url": org["url"], "id": org["id"],
        }
        files, total_rows = 0, 0
        for snap in self.snapshot_dates():
            snap_ts = snap.replace(hour=23, minute=self.rng.randint(0, 59),
                                   second=self.rng.randint(0, 59))
            bd = int(snap_ts.timestamp())
            lo = int((snap - timedelta(days=window)).timestamp())
            accounts_out = []
            for role, acct in self.accounts.items():
                bal, avail = self.account_balance(role, snap)
                txns = [self.txn_json(t) for t in self.ledger
                        if t["role"] == role and lo <= t["posted"] <= bd]
                txns.sort(key=lambda x: x["posted"], reverse=True)
                total_rows += len(txns)
                accounts_out.append({
                    "id": "ACT-" + str(uuid.UUID(int=self.rng.getrandbits(128))),
                    "name": acct["name"],
                    "currency": "USD",
                    "balance": f"{bal:.2f}",
                    "available-balance": f"{avail:.2f}",
                    "balance-date": bd,
                    "transactions": txns,
                    "holdings": [],
                    "org": org_block,
                })
            doc = {"errors": [], "accounts": accounts_out}
            day_dir = out_dir / "transactions" / f"{snap:%Y/%m/%d}"
            day_dir.mkdir(parents=True, exist_ok=True)
            fname = f"{snap_ts:%Y-%m-%dT%H%M%S}Z_bd{bd}.json"
            with open(day_dir / fname, "w") as f:
                json.dump(doc, f, indent=4)
            files += 1
        return files, total_rows

    def emit_seed(self, path: Path):
        """Regenerate the regex seed from the catalog + structural rows."""
        groups: dict[tuple, dict] = {}
        for m in self.merchants:
            key = (m["category"], m["subcategory"])
            g = groups.setdefault(key, {"tokens": [], "priority": 10})
            g["tokens"].append(m["token"])
            g["priority"] = min(g["priority"], m.get("priority", 10))
        rows = []
        for (cat, sub), g in groups.items():
            alts = "|".join(sorted(set(g["tokens"])))
            rows.append((cat, sub, f"^.*({alts}).*$", g["priority"]))
        for r in self.structural_rows:
            rows.append((r["category"], r["subcategory"], f"^.*({r['regex']}).*$", r["priority"]))
        rows.sort(key=lambda x: (x[3], x[0], x[1]))
        with open(path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["merchant_category", "merchant_subcategory",
                        "regex_match_pat", "match_priority"])
            w.writerows(rows)
        return len(rows)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--persona", default="jordan-rivera",
                    help="persona slug under synthetic/personas/ (default: jordan-rivera)")
    ap.add_argument("--out", default=None,
                    help="output directory (default: synthetic/out/<persona>)")
    ap.add_argument("--write-dbt-seed", action="store_true",
                    help="also overwrite dbt_code/seeds/seed_merchant_category_regex_mapping.csv "
                         "(only when publishing the demo, never on the real-pipeline machine)")
    args = ap.parse_args()

    persona_dir = PERSONAS / args.persona
    if not persona_dir.is_dir():
        available = ", ".join(sorted(p.name for p in PERSONAS.iterdir() if p.is_dir())) or "(none)"
        ap.error(f"no persona '{args.persona}' under {PERSONAS} — available: {available}")

    # Preflight: fail with a clear, file-scoped message instead of a KeyError
    # traceback (or silently emitting undemoable data) if the YAML contract is
    # broken. See validate.py for the full contract.
    from validate import validate_persona_dir
    errors, warnings = validate_persona_dir(persona_dir)
    for w in warnings:
        print(f"warning: {w}")
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        ap.error(f"persona '{args.persona}' can't be demoed — fix the "
                 f"{len(errors)} error(s) above (run: uv run python "
                 f"synthetic/validate.py --persona {args.persona})")

    persona, catalog = load_configs(persona_dir)
    gen = Generator(persona, catalog)
    gen.build_ledger()

    out_dir = Path(args.out) if args.out else HERE / "out" / args.persona
    out_dir.mkdir(parents=True, exist_ok=True)
    files, rows = gen.emit_snapshots(out_dir)
    seed_rows = gen.emit_seed(out_dir / "seed_merchant_category_regex_mapping.csv")
    if args.write_dbt_seed:
        gen.emit_seed(HERE.parent / "dbt_code" / "seeds" / "seed_merchant_category_regex_mapping.csv")

    print(f"persona       : {args.persona}")
    print(f"master ledger : {len(gen.ledger):,} unique transactions")
    print(f"snapshots     : {files} files, {rows:,} transaction rows total")
    print(f"regex seed    : {seed_rows} rows -> {out_dir / 'seed_merchant_category_regex_mapping.csv'}")
    print(f"output dir    : {out_dir}")


if __name__ == "__main__":
    main()
