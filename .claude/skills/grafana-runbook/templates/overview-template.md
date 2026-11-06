# {Service} — System Overview

## What it does

{One short paragraph in plain language, including who uses it.}

## How it works

{The modules and how data flows between them: bullets or a small Mermaid diagram, at most 10 lines.}

## Dependencies

| Direction | System       | Purpose | When it fails, this service… |
| --------- | ------------ | ------- | ---------------------------- |
| calls     | {downstream} | {why}   | {behavior}                   |
| called by | {upstream}   | {why}   | {behavior}                   |
| stores    | {db/queue}   | {what}  | {behavior}                   |

## Failure modes

- {The most common way it breaks, one line}
- {The second most common, one line}

## Common commands

| Purpose               | Command                                                                   |
| --------------------- | ------------------------------------------------------------------------- |
| Pod status            | `kubectl get pods -n {namespace}`                                         |
| Recent errors (LogQL) | `{service="{service}", landscape="{landscape}"} \| json \| level="ERROR"` |
| Request rate (PromQL) | `sum by (status) (rate({metric}_total{service="{service}"}[5m]))`         |
| {Key domain query}    | `{query}`                                                                 |
| Slow traces (TraceQL) | `{ resource.service.name="{service}" && duration > 2s }`                  |
| Rollout restart       | `kubectl argo rollouts restart {workload} -n {namespace}`                 |

## Links

- [Curated dashboard]({url}) · [Generic dashboard]({url with LPSM variables})
- [Deployment]({url}) · [Design doc]({url})
