# KKS Cold Prospect Reports — Project Setup Instructions

## What this is

Four files that, when uploaded to a new Claude Project, give every future chat in that project full context without re-explaining or re-querying. This eliminates the need to re-paste your database schema, voice rules, report standards, or letter templates in every session.

## How to set up the Project

### Step 1 — Create the Project
1. In Claude.ai, click "Projects" in the left sidebar.
2. Click "Create project" (or the + icon).
3. Name it: **KKS Cold Prospect Intel Reports**
4. Description (optional): *Weekly cold-prospect Echelon Intelligence Reports for contractor home services market.*

### Step 2 — Set the Project Instructions
1. In the new project, click "Set custom instructions" or the equivalent settings link.
2. Open the file `PROJECT_INSTRUCTIONS.md`.
3. Copy the entire contents.
4. Paste into the custom instructions field.
5. Save.

### Step 3 — Upload the reference files
1. In the project, click "Add content" or the + icon to add knowledge.
2. Upload `KKS_DATABASE_SCHEMA.md`.
3. Upload `ECHELON_REPORT_SPEC.md`.
4. Upload `COVER_LETTER_TEMPLATE.md`.
5. Optionally also upload the FFE example PDF (the v3 report at korekomfortsolutions.com) so future Claude can reference the canonical example directly.

### Step 4 — Verify the setup
Start a new chat in the project. Ask: *"What do you know about my prospect database, report standards, and cover letter approach?"*

Claude should answer without running any database queries. The schema, voice rules, report spec, and letter template should all be available from the project knowledge.

## What this enables

In every new chat in this project:
- No more pasting the database schema
- No more explaining the FFE report structure
- No more reminding about em-dash rules, voice, ICP
- No more re-explaining the cover letter framing
- Direct work: "build the report for prospect 234" should be enough to get started

## What still requires human input each time

- Confirmation of which prospect IDs to work on
- Approval of API spend (DataForSEO costs, etc.)
- Final review of each report before printing
- Address verification for mailings
- Approval of cover letter personalization before printing
- Anything that touches the live production database

## File inventory in this directory

```
PROJECT_INSTRUCTIONS.md      <- Custom instructions for the Project
KKS_DATABASE_SCHEMA.md       <- Database reference (no more .schema queries)
ECHELON_REPORT_SPEC.md       <- Report structure, voice, quality gates (cold-prospect 14-18 page version)
COVER_LETTER_TEMPLATE.md     <- Cover letter template + warm-followup variant + voice checklist
README.md                    <- This file
```

## Maintenance notes

- Update `KKS_DATABASE_SCHEMA.md` whenever new tables are added or column meanings change.
- Update `ECHELON_REPORT_SPEC.md` if the FFE example evolves or new sections are added based on what works in mailings.
- Update `COVER_LETTER_TEMPLATE.md` if mailing tests show that different framings convert better.
- Update `PROJECT_INSTRUCTIONS.md` if the workflow changes (e.g., switching shipping carriers, changing batch size, expanding to new cities).
- The "Current state" section at the bottom of `PROJECT_INSTRUCTIONS.md` will go stale as you mail prospects. Plan to refresh it monthly OR remove the per-batch state and let chat context handle batch-specific details.

## After today's batch ships

Once you've mailed the first 11 prospects:
1. Update prospect statuses in DB to `mailed`
2. Track responses (calls, emails) in the `notes` field with date stamps
3. After 30 days, evaluate response rate and update the cover letter / report templates if certain framings perform better
4. Refresh the prospect pool query for next week's batch from the remaining `researched` prospects in working permit cities
