# {Alert name}

> Covers: 🚨 {critical title} · ⚠️ {warning title} (keep the tiers that exist)
> Context: `observability/overview.md` · [Dashboard panel]({panel url}) · Escalation: #{channel}

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

Known cause: {YYYY-MM-DD} — {one-line incident summary}.

## Escalation

If not fixed in {30m}, or {condition}, escalate to {team} in #{channel}. Declare an incident if {user-impact condition}.
