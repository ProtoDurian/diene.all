# .NET 10 foundation

See the [.NET baseline](docs/developer/dotnet-baseline.md) for the
language-specific toolchain, task surface, test tiers, coverage ledgers, dead-code
passes, and the typed-problem contract ([docs/domain/problems.md](docs/domain/problems.md)).
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

[![NuGet version](https://img.shields.io/nuget/v/AtomiCloud.Diene.Problems)](https://www.nuget.org/packages/AtomiCloud.Diene.Problems)
[![NuGet downloads](https://img.shields.io/nuget/dt/AtomiCloud.Diene.Problems)](https://www.nuget.org/packages/AtomiCloud.Diene.Problems)

`AtomiCloud.Diene.Problems` provides typed domain problems, a consumer-owned
catalog, the canonical type-URI builder, RFC 9457 rendering, schema export, and
Problem custom-resource emission. `AtomiCloud.Diene.Problems.TestHelper`
provides FluentAssertions for domain, result, envelope, and HTTP boundaries.

```bash
dotnet add package AtomiCloud.Diene.Problems
dotnet add package AtomiCloud.Diene.Problems.TestHelper
```

## Register and render problems

Problem types do not enter the runtime implicitly. Register every baseline and
consumer-owned problem at composition time, then enable ASP.NET Core's exception
handler middleware:

```csharp
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddAtomiProblems(
    new ProblemIdentity("raichu", "dotnet", "notes", "api"),
    new ErrorPortalOption
    {
        Scheme = "https",
        Host = "docs.raichu.cluster.atomi.cloud",
    },
    catalog => catalog.AddBaseline());

var app = builder.Build();
app.UseExceptionHandler();
```

Throw a registered problem only at a framework boundary. Within domain code,
prefer the Result-returning guards and adapters:

```csharp
var guarded = ProblemGuard.NotFound(note, noteId);
var failed = new ValidationError(
    "The note is invalid.",
    [new ValidationIssue(["title"], "Title is required.", "required")]).ToErr<Note>();
var taken = new Conflict($"Note '{noteId}' already exists.", "Note", noteId).ToErr<Note>();
throw new EntityNotFound(
    $"Note '{noteId}' was not found.",
    typeof(Note),
    noteId).ToException();
```

`AddBaseline()` registers the generic catalog: `validation_error` (400),
`entity_not_found` (404), `conflict` (409), `unauthenticated` (401),
`unauthorized` (403) and `invalid_json` (400), plus the .NET-only
`multiple_entity_not_found` and `entity_conflict` (superseded by `conflict`).
`entity_not_found` and `conflict` carry `{ entityType, id }`; `validation_error`
carries `{ issues: [{ path, message, code? }] }`. The other three carry no data:
their envelope omits `data` and their schema is `{"not":{}}`.

## Type URIs and catalog export

Resolve `IProblemTypeUriBuilder` whenever a type URI is needed. Never recreate
the URI template in a controller or consumer. Resolve `ProblemResourceEmitter`
from the same service provider to emit the registered single-version catalog as
canonical JSON, which is also valid YAML 1.2. The resource is named
`{service}.{module}.{landscape}.{version}` (here `notes.api.raichu.v1`) in the
platform namespace:

```csharp
var emitter = app.Services.GetRequiredService<ProblemResourceEmitter>();
var resource = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "api", "raichu", "v1"));
var manifest = emitter.Serialize(resource);
```

## Assert the wire contract

```csharp
using AtomiCloud.Diene.Problems.TestHelper;
using FluentAssertions;

var envelope = (await response.Should().BeRfc9457()).Which;
envelope.Should().HaveStatus(404);
envelope.Should().HaveType(expectedTypeUri);
envelope.Should().HaveData(expectedProblem);
envelope.Should().BeRecoverable(false);

dataLessEnvelope.Should().HaveNoData();
```

Run `nix develop .#ci -c ./scripts/ci/pkg-validate.sh` to pack both packages,
validate metadata and symbols, and restore them into a scratch consumer. See
[the library baseline](docs/developer/dotnet-lib-baseline.md) for release and
promotion guidance.
