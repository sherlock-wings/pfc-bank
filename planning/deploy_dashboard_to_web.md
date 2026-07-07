# Deploy the finance dashboard to the web, behind a passkey guard

Goal: serve the Evidence dashboard at `https://myfinance.patrick-f-callahan.net`, reachable only after you pass an email code **and** a passkey (Face ID / Touch ID) bound to your own devices.

## How the pieces fit

```
        you                    Cloudflare edge                     origin
  ┌───────────┐   HTTPS   ┌────────────────────────┐        ┌─────────────────┐
  │  browser  │─────────▶│  Access "guard page"   │──────▶│ Cloudflare Pages│
  │  / phone  │           │  email code + passkey  │        │  (static site)  │
  └───────────┘           └────────────────────────┘        └─────────────────┘
```

Plain-language terms used below:

- **Subdomain** — a prefix on your domain (`myfinance.` in front of `patrick-f-callahan.net`) that can point somewhere different from the root site. The landing page stays on GitHub Pages; only this subdomain is the dashboard.
- **DNS record** — the address-book entry that maps a hostname to where it lives. Cloudflare manages yours already.
- **Static site** — Evidence runs all SQL at *build* time and bakes the results into plain files. The built site therefore *contains your transactions as downloadable files*. Whatever serves those files must be guarded.
- **Origin** — the server actually holding the files (here, Cloudflare Pages).
- **Edge / Cloudflare Access** — a checkpoint Cloudflare runs in front of the origin. No valid login → the request never reaches the files. This is the "guard page."
- **Passkey** — a login secret stored in a device's secure hardware (phone Secure Enclave, laptop TPM). It cannot be copied off the device, so "has the passkey" ≈ "is holding my phone."

**Why Cloudflare Pages and not GitHub Pages:** GitHub Pages also serves the site at a public `*.github.io` URL that the edge guard cannot cover — anyone hitting it downloads your data. Cloudflare Pages has one comparable public URL (`*.pages.dev`), and Part C guards that too, leaving no unguarded path.

## Prerequisites

- Cloudflare account that already manages `patrick-f-callahan.net` (you have this).
- A phone and/or laptop with a biometric authenticator (Face ID, Touch ID, or Windows Hello).
- The AWS OIDC role already used by `.github/workflows/extract.yml` (`vars.AWS_ROLE_ARN`), which can read `s3://pfc-nfcu/dashboard_mart/`.
- Repo push access (to add a workflow + secrets).

---

## Part A — Host the built dashboard on Cloudflare Pages

The dashboard build needs AWS credentials to read the parquet files in S3. GitHub Actions already has that via OIDC, so we build **and** deploy from Actions. Cloudflare's own build system is *not* used (it has no AWS access).

### A1. Create the Pages project (one-time, no build)

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Pages** → **Direct Upload**.
2. Name it `pfc-finance`. Skip uploading files (the workflow does that).
3. Note the URL it creates: `pfc-finance.pages.dev`.

### A2. Create a Cloudflare API token for deploys

1. Cloudflare dashboard → **My Profile** → **API Tokens** → **Create Token** → **Custom token**.
2. Permission: **Account → Cloudflare Pages → Edit**. Scope it to your account.
3. Copy the token.
4. Find your **Account ID**: Workers & Pages → right sidebar.

### A3. Add secrets to GitHub

Repo → **Settings** → **Secrets and variables** → **Actions**. Under the existing `dev` environment (the workflows use `environment: dev`), add:

- `CLOUDFLARE_API_TOKEN` = the token from A2.
- `CLOUDFLARE_ACCOUNT_ID` = your account ID.

### A4. Add a build-and-deploy workflow

Create `.github/workflows/deploy_dashboard.yml`:

```yaml
name: deploy dashboard

on:
  workflow_dispatch:           # manual button
  workflow_run:                # auto-run after new data is built
    workflows: ["nfcu-pipe extract"]
    types: [completed]

permissions:
  id-token: write              # assume the AWS role
  contents: read

jobs:
  deploy:
    # only when the upstream run succeeded (skips the "no new data" path too)
    if: github.event_name == 'workflow_dispatch' || github.event.workflow_run.conclusion == 'success'
    runs-on: ubuntu-latest
    environment: dev
    defaults:
      run:
        working-directory: dashboard
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4   # gives DuckDB S3 read via env creds
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: us-east-2

      - uses: actions/setup-node@v4
        with:
          node-version: 20

      - run: npm ci
      - run: npm run sources      # runs SQL against S3, writes parquet into the build
      - run: npm run build        # produces dashboard/build/

      - name: Deploy to Cloudflare Pages
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          workingDirectory: dashboard
          command: pages deploy build --project-name=pfc-finance --branch=main
```

Notes:
- `--branch=main` marks this the **production** deploy (matters for the custom domain in A5).
- The AWS step exports credentials as env vars; DuckDB's `CREDENTIAL_CHAIN` in `sources/pfc_bank/initialize.sql` picks them up automatically. No extra config.

### A5. Point the subdomain at Pages

1. Pages project `pfc-finance` → **Custom domains** → **Set up a custom domain**.
2. Enter `myfinance.patrick-f-callahan.net`.
3. Because Cloudflare already manages the domain, it auto-creates the DNS record and TLS certificate. Wait for **Active** (usually minutes).

### A6. First deploy

Repo → Actions → **deploy dashboard** → **Run workflow**. When green, `https://myfinance.patrick-f-callahan.net` should load the dashboard — **still unguarded**. Do not share it yet; Part B locks it.

---

## Part B — Put the passkey guard in front (Cloudflare Access)

### B1. Turn on Zero Trust (one-time)

1. Cloudflare dashboard → **Zero Trust**.
2. Pick the **Free** plan. You must enter a payment card; the free tier (up to 50 users) is not charged.
3. Set a **team name** (e.g. `pfc`) → your team domain becomes `pfc.cloudflareaccess.com`.

### B2. Enable an org-level passkey requirement ("Independent MFA")

This makes Cloudflare enforce the passkey itself, so the login does not depend on Google or any outside account.

1. Zero Trust → **Settings** → **Authentication**.
2. Confirm **One-time PIN** is present under login methods (it is on by default — this emails you a code).
3. Enable **Independent MFA** and allow **WebAuthn / security keys & biometric authenticators** (Touch ID, Face ID, Windows Hello).
   - Reference for exact current UI: <https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/independent-mfa/>

### B3. Create the Access application

1. Zero Trust → **Access** → **Applications** → **Add an application** → **Self-hosted**.
2. **Application domain:** `myfinance.patrick-f-callahan.net`.
3. Session duration: pick something like **24 hours** (how long between re-logins).

### B4. Policy — only you, with a passkey

Add one policy on the application:

- **Action:** Allow.
- **Include:** *Emails* → your email address (only this address can request a code).
- **Require:** *Authentication method / MFA* → **passkey / WebAuthn** (the authenticator you enabled in B2). This rejects the email code alone — the passkey is mandatory.

Save.

### B5. Close the `*.pages.dev` bypass

The raw `pfc-finance.pages.dev` URL still serves the files. Guard it the same way:

1. Access → **Applications** → **Add an application** → **Self-hosted**.
2. **Application domain:** `pfc-finance.pages.dev` (add the wildcard `*.pages.dev` as a second domain to also cover preview builds).
3. Attach the **same** policy from B4 (Allow only your email + require passkey).

Now every route to the files — custom domain, production `pages.dev`, and preview `pages.dev` — sits behind the guard.

---

## Part C — Verify

1. Open an **incognito window** → `https://myfinance.patrick-f-callahan.net`.
   - You should be redirected to the Cloudflare login (`pfc.cloudflareaccess.com`), enter your email, get a code, then be prompted to **register a passkey** (first time) or **use** it. Register with Face ID / Touch ID on the device you want enrolled.
   - After the passkey, the dashboard loads.
2. In incognito, open `https://pfc-finance.pages.dev` → same guard appears (no direct file access).
3. From a device with **no** passkey registered, confirm the email code alone does **not** let you in.
4. Optional: `curl -I https://myfinance.patrick-f-callahan.net` → expect a redirect to the Access login, not the dashboard HTML.

Enroll each device you want (phone, laptop) by logging in once from it and registering its passkey.

---

## Part D — Operate & maintain

- **New data:** the `deploy dashboard` workflow auto-runs after `nfcu-pipe extract` succeeds and redeploys. Nothing to do. To force a rebuild: Actions → **deploy dashboard** → **Run workflow**.
- **Add a device:** log in from it once and register its passkey when prompted. No config change.
- **Lost phone:** Zero Trust → **My Team** / device management → remove that passkey/registration. Its passkey can't be used elsewhere (it never left the device), but removing it is tidy.
- **Recovery / lockout:** you administer this from the Cloudflare dashboard, which is protected by your Cloudflare account's own 2FA — keep that 2FA and its backup codes safe. That account is the master key to everything here.
- **Change who can log in:** edit the Include list in the B4 policy.

## Security notes

- The built site is data-at-rest on Cloudflare's origin; the guard is the only thing between the public internet and it. Do not add other public routes to the same Pages project.
- Keep the `dashboard/build/` output out of git (already covered by `dashboard/.gitignore`), so transactions never land in the repo.
- The `CLOUDFLARE_API_TOKEN` only has Pages-edit scope — if leaked it can redeploy the site but cannot touch the guard or DNS. Rotate it (A2) if exposed.
- If you ever want the strongest possible lock later, add **WARP device enrollment** as an extra Require rule (only enrolled devices reach the site) — more to maintain, not needed for the current goal.

## Don't forget!

1. **Guard the `*.pages.dev` URL too (Part B5), not just the custom domain.** If you only protect `myfinance.patrick-f-callahan.net`, the raw `pfc-finance.pages.dev` still serves your transactions to anyone who finds it. Both must sit behind the same policy or the guard is pointless.
2. **Cloudflare's Zero Trust menus move around.** The exact labels in Part B may have shifted since this was written. The steps' *intent* is stable — allow only your email, require a WebAuthn passkey. If a menu path is wrong, follow the linked Independent MFA doc, which tracks the current UI.

## Appendix — Harden the Cloudflare account

Everything above hangs off one thing: your Cloudflare account. It is the recovery path (lose every enrolled device and you get back in by editing the Access policy from the dashboard) and therefore the master key to the guard, the DNS, and the deploy. If someone takes over that account, the passkey guard is moot. Lock it down before you rely on the dashboard:

1. **Enable 2FA on the Cloudflare account itself** (My Profile → Authentication). Prefer a hardware key or authenticator app over SMS.
2. **Save the backup codes** somewhere offline (password manager or paper). These are how you recover if you lose your 2FA device — without them, a lost phone can lock *you* out permanently.
3. **Use a strong, unique password** for the account, stored in a password manager — not reused from anywhere else.
4. **Keep the login email secure.** Account recovery flows through it; it should have its own 2FA. (This is also the email the dashboard's one-time code is sent to.)
5. **Review periodically:** Cloudflare account → audit log for unexpected logins, and Zero Trust → registered passkeys/devices to prune anything you no longer recognize.
