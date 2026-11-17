# {Service} — System Overview

## What it does

{One short paragraph in plain language, including who uses it.}

## How it works

{The modules (`{module}`, …) and how data flows between them: bullets or a small Mermaid diagram, at most 10 lines.}

## Dependencies

| Direction | System and its owner        | Purpose | When it fails, this service… |
| --------- | --------------------------- | ------- | ---------------------------- |
| calls     | {downstream} ({owner team}) | {why}   | {behavior}                   |
| called by | {upstream} ({owner team})   | {why}   | {behavior}                   |
| stores    | {db/queue} ({owner team})   | {what}  | {behavior}                   |

## Failure modes

- {The most common way it breaks, one line}
- {The second most common, one line}

## Common commands

| Purpose                                                      | Command                                                  |
| ------------------------------------------------------------ | -------------------------------------------------------- |
| Pod status                                                   | `kubectl get pods -n {namespace}`                        |
| Recent errors (LogsQL; the responder fills in `{landscape}`) | the `logsql` block below the table                       |
| {Key domain query}                                           | `{query}`                                                |
| Slow traces (TraceQL)                                        | `{ resource.service.name="{service}" && duration > 2s }` |
| Restart                                                      | `kubectl rollout restart {workload} -n {namespace}`      |

```logsql
_stream:{"durian.cloud.service"="{service}", "durian.cloud.landscape"="{landscape}"} {error filter from log-notes.md, or the expected one marked UNVERIFIED}
```

## Links

- Owner: {team} in {#channel}
- [Curated dashboard]({grafana-url}/d/{platform}-{service}-overview) · [Generic dashboard]({grafana-url}/d/{generic-dashboard-uid}?{generic-dashboard-vars})
- [Design doc]({design-doc-url}) (delete the line if there is none)
