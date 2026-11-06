namespace AtomiCloud.DotnetBase.App.Adapters;

public sealed class TextWriterLoggerSink(TextWriter writer) : ILoggerSink
{
    public Result<Unit, SeamError> Emit(LogRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Logging, nameof(record), "The record must not be null.");
        }

        try
        {
            writer.WriteLine(Render(record));
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (IOException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Logging, exception.Message);
        }
        catch (ObjectDisposedException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Logging, exception.Message);
        }
    }

    private static string Render(LogRecord record)
    {
        var attributes = string.Join(' ', record.Attributes.Select(entry => $"{entry.Key}={entry.Value}"));
        var error = record.Error.Match(value => $" error={value}", () => string.Empty);
        var stack = record.StackTrace.Match(value => $" stack={value}", () => string.Empty);
        return $"{record} {attributes}{error}{stack}".TrimEnd();
    }
}

public sealed class TextWriterMetricsCollector(TextWriter writer) : IMetricsCollector
{
    public Result<Unit, SeamError> Emit(MetricRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Metrics, nameof(record), "The record must not be null.");
        }

        try
        {
            writer.WriteLine(Render(record));
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (IOException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Metrics, exception.Message);
        }
        catch (ObjectDisposedException exception)
        {
            return SeamErrors.EmitFailed(SeamKind.Metrics, exception.Message);
        }
    }

    private static string Render(MetricRecord record)
    {
        var attributes = string.Join(' ', record.Attributes.Select(entry => $"{entry.Key}={entry.Value}"));
        var unit = record.Unit.Match(value => $" unit={value}", () => string.Empty);
        return $"{record}{unit} {attributes}".TrimEnd();
    }
}
