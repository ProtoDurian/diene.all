# Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. Build artifacts — Dockerfiles and Helm charts —
live under [`infra/`](infra) and may be plural, so their tasks are keyed per
artifact. See [the Taskfile standard](docs/standards/taskfile/index.md) for the
conventions.

# Development environment

Diene's reproducible development environment is managed by Nix. Run `direnv allow` once, then use `task` tasks from the loaded shell.

# Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

# Workspace baseline

This tree is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, and standards.

<!-- ### dotnet-base -->
<!-- #### source: dotnet-base -->

# .NET 10 foundation

See the [.NET baseline](docs/developer/dotnet-baseline.md) for the
language-specific toolchain, task surface, test tiers, coverage ledgers, dead-code
passes, and the illustrative Note domain ([docs/domain/note.md](docs/domain/note.md)).
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
