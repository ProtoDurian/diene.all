using System.Security;

namespace AtomiCloud.DotnetBase.App.Adapters;

public sealed class HostSystem : ISystem
{
    public Result<Option<string>, SeamError> Environment(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return SeamErrors.InvalidArgument(SeamKind.System, nameof(name), "The variable name must not be blank.");
        }

        try
        {
            return Result.Ok<Option<string>, SeamError>(
                Option.FromNullable(global::System.Environment.GetEnvironmentVariable(name)));
        }
        catch (SecurityException exception)
        {
            return SeamErrors.EnvironmentUnavailable(name, exception.Message);
        }
    }

    public Result<string, SeamError> CurrentDirectory()
    {
        try
        {
            return Result.Ok<string, SeamError>(Directory.GetCurrentDirectory());
        }
        catch (IOException exception)
        {
            return SeamErrors.IoFailure(SeamKind.System, "currentDirectory", exception.Message);
        }
    }

    public Result<DateTimeOffset, SeamError> NowUtc() => Result.Ok<DateTimeOffset, SeamError>(DateTimeOffset.UtcNow);

    public async Task<Result<Unit, SeamError>> Delay(TimeSpan duration, CancellationToken cancellationToken = default)
    {
        try
        {
            await Task.Delay(duration, cancellationToken).ConfigureAwait(false);
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (OperationCanceledException)
        {
            return SeamErrors.Cancelled(SeamKind.System, "delay");
        }
    }
}
