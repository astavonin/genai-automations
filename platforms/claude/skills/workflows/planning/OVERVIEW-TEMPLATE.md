# `overview.md` template

Every `planning/<epic-slug>/overview.md` file MUST follow this structure. The header block ("Source", "Owner", "State", "Last synced") is sourced from `projctl load epic &<N>` and refreshed by `/review-mr` if `**Last synced:**` is older than 30 days. As other commands migrate to the epic-slug convention, they may pick up the refresh behavior. The "Milestones" section is locally maintained — the epic-cache commands never overwrite it.

## Structure

```markdown
# <Epic Title>

**Source:** [&<N>](<epic-web-url>)
**Owner:** @<handle>            # From epic assignee; fall back to `@<handle> (author)` if unassigned
**State:** <opened|closed>
**Last synced:** YYYY-MM-DD

## About

<3–5 sentence summary of what the epic delivers and why it exists. Sourced from the epic Description on GitLab, condensed. Explain the user-visible outcome, not the implementation.>

## Scope

**In scope:**
- <bullet — what this epic will deliver>
- <bullet>

**Out of scope:**
- <bullet — what this epic will NOT deliver, to prevent scope creep>
- <bullet>

<!-- If the epic description does not have an explicit scope split, use the TBD variant below instead: -->
<!-- **In scope:**                                      -->
<!-- - <TBD — extract from epic description>           -->
<!-- **Out of scope:**                                  -->
<!-- - <TBD — extract from epic description>           -->

## Milestones

<Locally maintained roadmap — milestone titles, sequencing, status.
Not touched by the epic-cache refresh path. Populated as you plan and complete milestones.
Example:>

- **milestone-01-foundation** — landed 2026-05-10
- **milestone-02-integration** — in progress ([%<N>](<milestone-web-url>))
- **milestone-03-hardening** — planned
```

## Rules

- **Header block is machine-generated.** `Source`, `Owner`, `State`, `Last synced` are refreshed from `projctl load epic &<N>`. Do not hand-edit these — they'll be overwritten on next refresh.
- **`## About` is machine-generated on first creation, hand-edited thereafter.** The initial fill uses the epic Description from GitLab (condensed to 3–5 sentences). Once you've refined it locally, refresh commands leave `## About` alone unless the epic description on GitLab has changed materially — in which case they append a note under the section, they don't rewrite it.
- **`## Scope` is required.** If the epic description doesn't have an explicit scope split, populate both blocks with `- <TBD — extract from epic description>` so the gap is visible. Never delete `## Scope` even if empty.
- **`## Milestones` is locally maintained.** Neither `projctl` nor any refresh path modifies this section.
- **Refresh cadence:** `/review-mr` checks `**Last synced:**` when it resolves an epic. If older than 30 days, re-fetch and update the header block + note any material change to `## About`. Otherwise skip. As other commands migrate to the epic-slug convention, they may pick up the refresh behavior.
- **Missing `**Last synced:**`:** If the field is absent (pre-existing manually-created `overview.md` files predate this convention), treat it as `never` and run one refresh to backfill the header block — preserving all hand-authored content in `## About`, `## Scope`, and `## Milestones`. Never delete hand-authored `overview.md` content.

## When to instantiate

Create `planning/<epic-slug>/overview.md` in any of these situations:

1. `/review-mr` reviews an MR whose linked issue lives under an epic we haven't tracked locally yet — the command creates `planning/<epic-slug>/` and writes `overview.md` populated from `projctl load epic &<N>` before writing the MR review YAML.
2. A new epic folder is created manually for our own work (e.g. during `/research` or `/design` when no existing folder is present) — write `overview.md` from `projctl load epic &<N>` at that time.

## Slug derivation

`<epic-slug>` slugs are human-readable but deterministically derived on first creation:
- Take the epic title (e.g. "Run supercombo on RockChip hardware").
- Lowercase, strip punctuation, collapse whitespace to `-`.
- Strip filler words (`run`, `on`, `the`, `for`, `of`, `in`, `a`, `an`) from the start.
- **Acronym-in-parens shortcut:** if the title contains an acronym in parentheses (e.g. "Forward Collision Warning (FCW)"), prefer the acronym as the slug component: `fcw`.
- **Target 2–3 content tokens** — enough to be recognizable in a directory listing, short enough to type. Use the full hardware/product name only if it disambiguates (e.g. `supercombo-rockchip` to distinguish from `supercombo-qualcomm`).
- Present the proposed slug to the user for confirmation before creating the folder.

Examples:
- "Run supercombo on RockChip hardware" → strip filler → `supercombo rockchip` → propose `supercombo-rockchip` (2 content tokens; or `supercombo-rk` if user prefers the abbreviation).
- "Forward Collision Warning (FCW)" → acronym-in-parens → propose `fcw`.
- "OTA software updates" → strip filler → `ota software` → propose `ota`.
- "Manager start/stop daemon supervision" → propose `manager-supervisor` (user picks).
