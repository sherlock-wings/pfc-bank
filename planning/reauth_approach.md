# Re-auth approach

Supersedes the "Frictionless re-link (SHELL PLAN)" stub in `plan.md` — same goal, concrete design.

## Goal

When NFCU kicks SimpleFIN and forces re-auth, recover with the fewest possible taps,
entirely from a phone, no laptop required.

## The irreducible manual step

Re-authenticating NFCU is an interactive MX MFA flow at bridge.simplefin.org. That's the
security boundary — it cannot be automated and shouldn't be. The target isn't "zero taps,"
it's "one MFA flow + one button," with everything else automated.

## Key simplification: don't branch on whether the access URL rotates

`plan.md` treats "does the access URL survive re-auth?" as the fork that decides the whole
design, and defers building anything until that's observed. That's unnecessary — build for
the "it rotates" case unconditionally:

- Every re-auth produces a new **setup token** at bridge.simplefin.org regardless of
  whether the resulting access URL turns out to be identical or different.
- If we always take that setup token, exchange it, and overwrite the `SIMPLEFIN_ACCESS_URL`
  secret, the operation is a no-op when the URL happens to survive, and the fix when it
  doesn't. Same one button either way.
- This also means the capability is useful for the *first-ever* link and for any future
  re-link, not just a hypothetical rotation case — no wasted work if it turns out URLs
  never rotate.

So there's no need to "wait for it to break once and observe" before building this.

## Design

### 1. Detection (already exists)
`extract.py`'s alerting (email if no successful fetch by `ALERT_CUTOFF_HOUR_UTC`) is the
notification trigger. No change needed here.

### 2. New workflow: `.github/workflows/reauth.yml`

A `workflow_dispatch` workflow with one required text input, runnable from the GitHub
mobile app or mobile browser:

```yaml
name: nfcu-pipe reauth

on:
  workflow_dispatch:
    inputs:
      setup_token:
        description: "Setup token from bridge.simplefin.org (Connect an app)"
        required: true

permissions:
  contents: read

jobs:
  update-secret:
    runs-on: ubuntu-latest
    steps:
      - name: Exchange setup token for access URL
        id: exchange
        run: |
          CLAIM_URL=$(echo "${{ inputs.setup_token }}" | base64 -d)
          ACCESS_URL=$(curl -sf -X POST "$CLAIM_URL")
          echo "::add-mask::$ACCESS_URL"
          echo "access_url=$ACCESS_URL" >> "$GITHUB_OUTPUT"

      - name: Update SIMPLEFIN_ACCESS_URL secret
        env:
          GH_TOKEN: ${{ secrets.SECRETS_ADMIN_PAT }}
        run: |
          gh secret set SIMPLEFIN_ACCESS_URL \
            --repo sherlock-wings/nfcu-pipe \
            --env dev \
            --body "${{ steps.exchange.outputs.access_url }}"

      - name: Trigger a verification pull
        env:
          GH_TOKEN: ${{ secrets.SECRETS_ADMIN_PAT }}
        run: gh workflow run extract.yml --repo sherlock-wings/nfcu-pipe
```

Notes on this workflow:
- `::add-mask::` before the value is ever echoed/used keeps it out of logs, same as any
  other secret.
- Setup tokens are single-use and short-lived, so pasting a stale one just fails loudly
  (curl `-f`) — safe to retry by grabbing a fresh token.
- The final step immediately re-runs `extract.yml` so the phone flow ends with proof the
  fix worked, instead of waiting up to 90 min for the next scheduled slot.

### 3. Why a PAT, not the default `GITHUB_TOKEN`

The default `GITHUB_TOKEN` cannot write repo/environment secrets — GitHub deliberately
excludes secrets-management from Actions token permissions. This requires a **fine-grained
PAT**, scoped as tightly as possible:
- Repository access: `sherlock-wings/nfcu-pipe` only.
- Permissions: **Secrets: write**, **Actions: write** (the latter to trigger `extract.yml`
  via `gh workflow run`). Nothing else.
- Set the shortest expiration GitHub allows that you're willing to renew (fine-grained PATs
  cap at 1 year); put a calendar reminder to rotate it before expiry, since an expired PAT
  silently breaks the reauth flow, not the daily pull.
- Store it as repo secret `SECRETS_ADMIN_PAT` (repo-level, not environment-scoped — it
  must be usable without the `dev` environment's protection rules gating it, since this
  workflow's whole job is to unblock things).

This is the one piece of the design that's a stored, semi-privileged credential rather than
OIDC. It's unavoidable — GitHub's API requires it for secret writes — but it's scoped to a
single repo and two permissions, so the blast radius of it leaking is "someone can edit
this repo's secrets/workflows," not account-wide.

### 4. End-to-end mobile flow

1. Get the failure email (existing alerting).
2. Phone browser → bridge.simplefin.org → tap the broken NFCU connection → complete MX
   MFA (the one irreducible step) → copy the new setup token.
3. GitHub mobile app (or mobile browser) → Actions → `nfcu-pipe reauth` → Run workflow →
   paste the token → Run.
4. Watch the run finish (~30–60s): secret updated, `extract.yml` triggered and green.

Two screens, one paste, done. No terminal, no editing secrets by hand.

### 5. Mobile ergonomics

- Add a home-screen bookmark straight to bridge.simplefin.org's connections page (skips
  the login-then-navigate hop).
- Confirm the GitHub mobile app actually renders the `setup_token` input field for
  `workflow_dispatch` — it's supported, but if the app version in use lags, mobile Safari/
  Chrome to `github.com/sherlock-wings/nfcu-pipe/actions/workflows/reauth.yml` → "Run
  workflow" is the fallback and works fine as a mobile-web form.

## Implementation steps

1. Create the fine-grained PAT (Secrets: write, Actions: write, repo-scoped) at
   github.com/settings/personal-access-tokens.
2. Add it as repo secret `SECRETS_ADMIN_PAT`.
3. Add `.github/workflows/reauth.yml` as above.
4. Dry-run it once with a real setup token (either a fresh NFCU re-link or the demo token
   flow) to confirm `gh secret set --env dev` actually reaches the environment secret and
   the follow-up `extract.yml` run picks it up.
5. Bookmark both the SimpleFIN connections page and the reauth workflow's mobile-web URL.

## Open items

- Confirm `gh secret set --env dev` with only "Secrets: write" repo permission can target
  an *environment* secret, not just a repo secret — environment secrets have historically
  needed slightly different API permissions. If it can't, the fallback is moving
  `SIMPLEFIN_ACCESS_URL` from the `dev` environment to a plain repo secret (loses
  environment protection rules, which currently don't do much for a solo pipeline anyway).
- Decide PAT rotation cadence and put it somewhere you'll actually see it (not just this
  doc) — e.g. a recurring calendar reminder, since PAT expiry is a silent failure mode.

## Nice-to-haves (deferred)

- Fold the "verification pull" step's result back into the mobile flow more visibly (e.g.
  a job summary with balance-date) so success/failure is legible without tapping into logs.
- If `reauth.yml` itself is ever hard to reach from a locked-down phone, a Siri
  Shortcut/Android equivalent that just opens the workflow's mobile-web URL removes one
  more tap — not worth building until the GitHub-app flow proves annoying in practice.
