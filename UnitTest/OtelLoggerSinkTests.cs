using Microsoft.Extensions.Logging;
using MsLogLevel = Microsoft.Extensions.Logging.LogLevel;
using SeamLogLevel = AtomiCloud.Diene.Interfaces.LogLevel;

namespace AtomiCloud.DotnetBase.UnitTest;

internal sealed class CapturingLogger : ILogger
{
    public List<(MsLogLevel Level, string Message)> Entries { get; } = [];

    public List<EventId> Events { get; } = [];

    public List<IReadOnlyList<KeyValuePair<string, object?>>> Scopes { get; } = [];

    public bool Throw { get; set; }

    public IDisposable BeginScope<TState>(TState state)
        where TState : notnull
    {
        if (state is IReadOnlyList<KeyValuePair<string, object?>> entries) Scopes.Add(entries);
        return new Scope();
    }

    public bool IsEnabled(MsLogLevel _) => true;

    public void Log<TState>(
        MsLogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (Throw) throw new InvalidOperationException("logger exploded");
        Events.Add(eventId);
        Entries.Add((logLevel, formatter(state, exception)));
    }

    private sealed class Scope : IDisposable
    {
        public void Dispose()
        {
        }
    }
}

public class OtelLoggerSinkTests
{
    private static Dictionary<string, AttributeValue> Attributes { get; } = new(StringComparer.Ordinal)
    {
        ["route"] = AttributeValue.Text("/v1/demo"),
        ["attempt"] = AttributeValue.Integer(2),
    };

    private static LogRecord Record(
        SeamLogLevel level = SeamLogLevel.Info,
        string? error = null,
        string? stackTrace = null) =>
        new(DateTimeOffset.UnixEpoch, level, "request served", Attributes, error, stackTrace);

    [Theory]
    [InlineData(SeamLogLevel.Trace, MsLogLevel.Trace)]
    [InlineData(SeamLogLevel.Debug, MsLogLevel.Debug)]
    [InlineData(SeamLogLevel.Info, MsLogLevel.Information)]
    [InlineData(SeamLogLevel.Warning, MsLogLevel.Warning)]
    [InlineData(SeamLogLevel.Error, MsLogLevel.Error)]
    [InlineData(SeamLogLevel.Fatal, MsLogLevel.Critical)]
    public void Level_MapsEverySeamSeverity(SeamLogLevel seam, MsLogLevel host)
    {
        // Act
        var level = OtelLoggerSink.Level(seam);

        // Assert
        level.Should().Be(host);
    }

    [Fact]
    public void Level_MapsAnUndefinedSeverityToNone()
    {
        // Act
        var level = OtelLoggerSink.Level((SeamLogLevel)42);

        // Assert
        level.Should().Be(MsLogLevel.None);
    }

    [Fact]
    public void AttributeKeys_AreTheSemconvExceptionKeys()
    {
        // Act
        string[] keys = [OtelLoggerSink.ErrorKey, OtelLoggerSink.StackTraceKey];

        // Assert
        keys.Should().Equal("exception.message", "exception.stacktrace");
    }

    [Fact]
    public void State_CarriesEveryAttributeInItsWireForm()
    {
        // Act
        var state = OtelLoggerSink.State(Record());

        // Assert
        state.Should().HaveCount(2);
        state.Should().Contain(new KeyValuePair<string, object?>("route", "/v1/demo"));
        state.Should().Contain(new KeyValuePair<string, object?>("attempt", "2"));
    }

    [Fact]
    public void State_AddsTheErrorAndStackTraceWhenPresent()
    {
        // Arrange
        var record = Record(error: "boom", stackTrace: "at Demo.Run()");

        // Act
        var state = OtelLoggerSink.State(record);

        // Assert
        state.Should().Contain(new KeyValuePair<string, object?>(OtelLoggerSink.ErrorKey, "boom"));
        state.Should().Contain(new KeyValuePair<string, object?>(OtelLoggerSink.StackTraceKey, "at Demo.Run()"));
    }

    [Fact]
    public void State_OmitsTheErrorAndStackTraceWhenAbsent()
    {
        // Act
        var state = OtelLoggerSink.State(Record());

        // Assert
        state.Select(entry => entry.Key).Should().NotContain([OtelLoggerSink.ErrorKey, OtelLoggerSink.StackTraceKey]);
    }

    [Fact]
    public void State_RejectsANullRecord()
    {
        // Act
        var act = () => OtelLoggerSink.State(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Construct_RejectsANullLogger()
    {
        // Act
        var act = () => new OtelLoggerSink(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Emit_LogsAtTheMappedLevelWithTheRecordMessage()
    {
        // Arrange
        var logger = new CapturingLogger();
        var sink = new OtelLoggerSink(logger);

        // Act
        var result = sink.Emit(Record(SeamLogLevel.Warning));

        // Assert
        result.Should().BeOk();
        logger.Entries.Should().ContainSingle()
            .Which.Should().Be((MsLogLevel.Warning, "request served"));
        logger.Scopes.Should().ContainSingle().Which.Should().HaveCount(2);
        logger.Events.Should().ContainSingle().Which.Should().Be(default(EventId));
    }

    [Fact]
    public void Emit_RejectsANullRecord()
    {
        // Arrange
        var sink = new OtelLoggerSink(new CapturingLogger());

        // Act
        var result = sink.Emit(null!);

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_argument");
    }

    [Fact]
    public void Emit_RejectsAnUndefinedSeverity()
    {
        // Arrange
        var sink = new OtelLoggerSink(new CapturingLogger());

        // Act
        var result = sink.Emit(new LogRecord(DateTimeOffset.UnixEpoch, (SeamLogLevel)42, "message"));

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void Emit_ConvertsAThrowingLoggerIntoAnEmitFailure()
    {
        // Arrange
        var sink = new OtelLoggerSink(new CapturingLogger { Throw = true });

        // Act
        var result = sink.Emit(Record());

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "emit_failed").Which.Detail.Should().Contain("logger exploded");
    }

    [Fact]
    public void Emit_IsTotalOverAnEmptyMessageAndNoAttributes()
    {
        // Arrange
        var sink = new OtelLoggerSink(new CapturingLogger());

        // Act
        var result = sink.Emit(new LogRecord(DateTimeOffset.UnixEpoch, SeamLogLevel.Info, string.Empty));

        // Assert
        result.Should().BeOk();
    }
}
