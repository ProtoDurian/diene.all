---
id: dotnet-baseline
title: .NET Baseline
---

# .NET baseline

`dotnet-base` is the .NET 10 foundation for the dotnet template family. It
replays the real `AtomiCloud/diene.dotnet-base` sample while retaining the current
shared workspace, standards, Docker, secret, and release surfaces.

## Local commands

| Command                            | Purpose                                                        |
| ---------------------------------- | -------------------------------------------------------------- |
| `task setup`                       | Synchronize vendored skills and restore repo-local .NET tools. |
| `task clean`                       | Remove build and test artifacts.                               |
| `task build`                       | Build every project in Release.                                |
| `task dev`                         | Run the App through `dotnet watch`.                            |
| `task run -- <args>`               | Run the App in development mode.                               |
| `task preview -- <args>`           | Build and run the compiled Release artifact.                   |
| `task up` / `task down`            | Start or stop the local Redis dependency.                      |
| `task test`                        | Run unit and integration tiers.                                |
| `task test:unit` / `task test:int` | Run one tier.                                                  |
| `task test:unit:coverage`          | Enforce the merged unit coverage ledger.                       |
| `task test:int:coverage`           | Enforce the merged integration coverage ledger.                |
| `task test:unit:watch`             | Watch the fast unit tier.                                      |
| `task deadcode`                    | Emit both broad, non-blocking LLM reviews.                     |
| `task deadcode:strict`             | Run both blocking dead-code passes, as CI does.                |
| `task lint`                        | Run every generated pre-commit hook.                           |

## Projects and coverage

`dotnet-base.slnx` contains `App`, `Lib`, `UnitTest`, and `IntTest`. Register test
projects once in `.config/dotnet-base.test.yaml`. The coverage runner iterates the
registered projects, merges Coverlet JSON, and enforces one final threshold per
tier:

- unit: every `[Lib*]*` assembly at 100%;
- integration: every `[App*]*` assembly at 80%.

The runner then parses the merged `coverage.cobertura.xml` with `xmlstarlet`: it
rejects a report that measured zero lines, rejects any package whose assembly name
escapes the tier ledger, and re-checks the tier minimum against every package's own
`line-rate` rather than the merged total alone.

Adding `Lib2` and `UnitTest2` requires one solution line per project and one YAML
list entry for `UnitTest2`. Assembly filters, merged thresholds, and production
dead-code project discovery follow the naming convention automatically.

## Dead code and supply chain

dn-inspect has four dead-code modes, none with exclusion lists:

- strict all projects (`--strict-all`): blocking pass over source and tests, so dead test code fails too.
- strict production (`--strict-production`): blocking pass over `App*`/`Lib*` only, so code only tests use fails.
- LLM all projects: `task deadcode`, broad filter, non-blocking.
- LLM production: `task deadcode`, broad filter, non-blocking.

CI and `task deadcode:strict` run both strict passes; `task deadcode` runs both LLM views.

The SDK is pinned by `global.json`; packages use Central Package Management.
`NuGetAuditMode=all`, analyzers, deterministic builds, and warnings-as-errors are
enforced in Release builds.

The `dotnetlint` pre-commit hook runs `dotnet format --no-restore`, so it expects
`dotnet restore dotnet-base.slnx` to have run; `task setup` and CI's pre-commit
script both restore first.

## Docker and release

The Dockerfile is the parent template's stub, unchanged, for descendants to
replace. Releaser stamps the version in `App/App.csproj`; its canonical
`release.yaml` is the single commit-type vocabulary.

## C# standards

C# variants accompany the shared standards:
[date/time](../standards/datetime/languages/csharp.md),
[domain-driven design](../standards/domain-driven-design/languages/csharp.md),
[functional practices](../standards/functional-practices/languages/csharp.md),
[SOLID](../standards/solid-principles/languages/csharp.md),
[stateless OOP/DI](../standards/stateless-oop-di/languages/csharp.md),
[testing](../standards/testing/languages/csharp.md),
[utilities](../standards/utilities/languages/csharp.md), and
[validation](../standards/validation/languages/csharp.md).

## Template-maintenance boundary

Downstream nodes may adapt package/artifact identity, coverage thresholds, Docker
runtime, chart contents, badges, and the illustrative Note source/tests. Keep
`dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, and the
`AtomiCloud.DotnetBase.*` root namespaces base-named for merge stability.

Observability is deliberately absent on this branch and arrives only through the
separate observability add-back.
