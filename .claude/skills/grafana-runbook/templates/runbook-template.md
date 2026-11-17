# {Alert name}

> Covers: 🚨 {critical title} · ⚠️ {warning title} (keep the tiers that exist)
> Context: [System overview](/observability/overview.md); its Links section has the owner, the channel and both dashboards. Curated dashboard panel: {panel} (delete if the tiers set no `panel`)

{What this means and who is affected, in two plain sentences.}

## Triage

1. {Fastest check that tells the causes apart:}

   ```bash
   {command}
   ```

   {Normal: {X}. Bad: {Y} → step {N}.}

2. {Next check:}

   ```promql
   {query}
   ```

## Remediation

- **{Likely cause 1}**: {fix steps}. Confirm with:

  ```bash
  {command}
  ```

- **{Likely cause 2}**: {fix}. Confirm with: `{command}`

Known causes: {YYYY-MM-DD — one-line incident summary}, or "none recorded yet".

## Escalation

If not fixed in {30m}, or {condition}, escalate to the owner team in its channel (System overview, Links); if a dependency is at fault, also to its owner (System overview, Dependencies). Declare an incident if {user-impact condition}.
