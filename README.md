# .NET 10 foundation

See the [.NET baseline](docs/developer/dotnet-baseline.md) for the
language-specific toolchain, task surface, test tiers, coverage ledgers, dead-code
passes, and the shared seam contract ([docs/domain/interfaces.md](docs/domain/interfaces.md)).
C# variants accompany the shared standards for
[date/time](docs/standards/datetime/languages/csharp.md),
[domain-driven design](docs/standards/domain-driven-design/languages/csharp.md),
[functional practices](docs/standards/functional-practices/languages/csharp.md),
[SOLID](docs/standards/solid-principles/languages/csharp.md),
[stateless OOP/DI](docs/standards/stateless-oop-di/languages/csharp.md),
[testing](docs/standards/testing/languages/csharp.md),
[utilities](docs/standards/utilities/languages/csharp.md), and
[validation](docs/standards/validation/languages/csharp.md). This node also owns
the [authorization standard](docs/standards/authorization/index.md).

# Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. See
[the Taskfile standard](docs/standards/taskfile/index.md) for the conventions.

# Development Environment

All binaries, tools, and PATH are managed by **Nix**. Do not install tools manually or modify PATH outside of the nix configuration.

## Prerequisites

1. **[Nix](https://nixos.org/download)** — package manager
2. **[Docker](https://docs.docker.com/get-docker)** — container runtime
3. **[direnv](https://direnv.net/docs/installation.html)** — auto-loads the nix shell on `cd`

## Getting Started

```bash
direnv allow    # first time only — loads the nix dev shell
```

Once allowed, direnv automatically loads the development environment whenever you enter the project directory.

## Nix Configuration

See [docs/standards/nix/index.md](docs/standards/nix/index.md) for the full guide on:

- File structure (`flake.nix`, `nix/`, `.envrc`)
- Adding/removing packages
- Environment groups and shells
- Formatters and pre-commit hooks
- Adding registries

# Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

# Workspace baseline

This tree is the all-features workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, and standards.

# Publishable library packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Interfaces)](https://www.nuget.org/packages/AtomiCloud.Diene.Interfaces)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Interfaces)](https://www.nuget.org/packages/AtomiCloud.Diene.Interfaces)

This repository publishes `AtomiCloud.Diene.Interfaces` and the companion
`AtomiCloud.Diene.Interfaces.TestHelper` package at one committed version. It
owns the shared seams `ISystem`, `IVfs`, `ITerminal`, `ILoggerSink`, and
`IMetricsCollector`; every fallible method returns `Result<T, SeamError>` and
never throws. The `otel` package implements the telemetry seams; it does not
own them.

```bash
dotnet add package AtomiCloud.Diene.Interfaces
dotnet add package AtomiCloud.Diene.Interfaces.TestHelper
```

```csharp
using AtomiCloud.Diene.Interfaces;
using AtomiCloud.Diene.Interfaces.TestHelper;
using AtomiCloud.Diene.Results.TestHelper;

var vfs = new InMemoryVfs();
(await vfs.WriteText("/etc/app.yaml", "key: value", new VfsWriteOptions(true))).Should().BeOk();
(await vfs.ReadText("/etc/app.yaml")).Should().BeOk("key: value");
(await vfs.ReadText("/absent")).Should().BeSeamErr(SeamKind.Vfs, "not_found");

(await SeamContracts.Vfs(new MyVfs(), "/tmp/scratch")).Should().BeConformant();
```

Run one `SeamContracts` suite against your real adapter and against the
in-memory mock: a conformant pair is substitutable. Wire values follow the C0
contract: RFC 3339 UTC instants, ISO 8601 durations, IANA timezone ids, and one
lowercase wire name per enumeration.

`nix develop .#ci -c ./scripts/ci/pkg-validate.sh` packs both packages, validates
metadata and symbols, and restores them into a scratch consumer. See [the library baseline](docs/developer/dotnet-lib-baseline.md)
for release and promotion guidance.
