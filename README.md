# TL;DR

I want to be able to regularly extract banking data from my Navy Federal Credit Union account (as CSVs). I will call this a NFCU Data Pipeline, or just `nfcu-pipe`

# The Details

The flow should be like this:

1. Script (GitHub Actions) Runs ->
   - This should run using CRON 0 23 * * *
2. NFCU Website, Extracts CSV
3. Saves CSV to S3 bucket (I have my own AWS account)

## Major Design Decisions

1. How will we get past NFCU MFA Requirements?
  - I have heard that a tool called Plaid may be a good fit here
2. What will be the overall approach to get to NFCU? Do we simulate someone actually trying to use the website like a normal user (meaning we need a tool like Selenium or Playwright)? Something else?

## Operations

**Re-link runbook:** a workflow failure email usually means SimpleFIN's NFCU connection needs re-auth — re-link NFCU at <https://bridge.simplefin.org> (one-time MFA) and the pipeline resumes. See the frictionless-relink plan at the bottom of `planning/plan.md`.
