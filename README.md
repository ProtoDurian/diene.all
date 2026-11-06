# .NET 10 foundation

See the [.NET baseline](docs/developer/dotnet-baseline.md) for the
language-specific toolchain, task surface, test tiers, coverage ledgers, dead-code
passes, and the Result/Option contract ([docs/domain/result.md](docs/domain/result.md)).
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

This tree is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, and standards.

# Publishable library packages

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Result)](https://www.nuget.org/packages/AtomiCloud.Diene.Result)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Result)](https://www.nuget.org/packages/AtomiCloud.Diene.Result)

This repository publishes `AtomiCloud.Diene.Result` and the companion
`AtomiCloud.Diene.Result.TestHelper` package at one committed version. The
library provides guarded rich structs for `Result<T, E>` and `Option<T>`,
dotnet-idiomatic railway composition, explicit exception capture, async
composition, and versioned C0 JSON tuple codecs. It has no runtime dependency
and no dependency on a Problems package.

```bash
dotnet add package AtomiCloud.Diene.Result
dotnet add package AtomiCloud.Diene.Result.TestHelper
```

```csharp
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;

Result<int, string> parsed = Result.Ok<int, string>(21);
var answer = parsed.Map(value => value * 2);
answer.Should().BeOk(42);
```

The package ID is singular but the namespace is plural
`AtomiCloud.Diene.Results`, so the namespace tail never collides with the
`Result` type. Serialize only `ResultSerial` and `OptionSerial`, never the
in-memory structs.

`nix develop .#ci -c ./scripts/ci/pkg-validate.sh` packs both packages, validates
metadata and symbols, and restores them into a scratch consumer. See [the library baseline](docs/developer/dotnet-lib-baseline.md)
for release and promotion guidance.
