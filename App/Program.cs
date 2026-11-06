using System.Globalization;
using AtomiCloud.DotnetBase.App.Adapters;

namespace AtomiCloud.DotnetBase.App;

public static class Program
{
    public static async Task Main()
    {
        Samples.RunAll();

        ISystem system = new HostSystem();
        IVfs vfs = new HostVfs();
        ILoggerSink logger = new TextWriterLoggerSink(Console.Out);
        IMetricsCollector metrics = new TextWriterMetricsCollector(TextWriter.Null);

        var scratch = Path.Combine(Path.GetTempPath(), $"diene-interfaces-app-{Guid.NewGuid():N}");
        var file = Path.Combine(scratch, "answer.txt");

        var message = await Doubled(system, vfs, logger, metrics, scratch, file).ConfigureAwait(false);
        _ = await vfs.Delete(scratch, new VfsDirectoryOptions(true)).ConfigureAwait(false);
        Console.WriteLine(message);
    }

    private static async Task<string> Doubled(
        ISystem system,
        IVfs vfs,
        ILoggerSink logger,
        IMetricsCollector metrics,
        string scratch,
        string file)
    {
        var now = system.NowUtc();
        if (now.IsFailure(out var clockError)) return Failure(clockError);

        var created = await vfs.CreateDirectory(scratch, new VfsDirectoryOptions(true)).ConfigureAwait(false);
        if (created.IsFailure(out var createError)) return Failure(createError);

        var written = await vfs.WriteText(file, "21").ConfigureAwait(false);
        if (written.IsFailure(out var writeError)) return Failure(writeError);

        var read = await vfs.ReadText(file).ConfigureAwait(false);
        return read
            .Then(Parse)
            .Do(_ => logger.Emit(new LogRecord(
                now.Get(),
                LogLevel.Info,
                "doubled the stored answer",
                [new("source", AttributeValue.Text(file))])))
            .Do(value => metrics.Emit(new MetricRecord(now.Get(), "app.answer", MetricKind.Gauge, value * 2)))
            .Match(value => $"Success: {value * 2}", Failure);
    }

    private static string Failure(SeamError error) => $"Failure: {error}";

    private static Result<int, SeamError> Parse(string text) =>
        int.TryParse(text, CultureInfo.InvariantCulture, out var value)
            ? Result.Ok<int, SeamError>(value)
            : SeamErrors.InvalidWire("integer", text);
}
