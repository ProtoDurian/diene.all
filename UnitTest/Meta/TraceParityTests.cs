using System.Diagnostics;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class TraceParityTests
{
    public static TheoryData<string> Emitters => new("activity", "in-memory");

    private static TraceRecord Record(
        string name,
        TraceStatus status = TraceStatus.Unset,
        params KeyValuePair<string, AttributeValue>[] attributes) =>
        TraceRecord.Create(name, attributes, status: status).Should().BeOk().Which;

    private static (ITraceEmitter Emitter, Func<IReadOnlyList<string>> Names, IDisposable Scope) Subject(string kind)
    {
        if (kind == "in-memory")
        {
            var emitter = new InMemoryTraceEmitter();
            return (emitter, () => [.. emitter.Records.Select(record => record.Name)], new Nothing());
        }

        var instrumentation = new Instrumentation(new AppIdentity("l", "p", $"parity-{Guid.NewGuid():N}", "m", "1.0.0"));
        var stopped = new List<string>();
        var listener = new ActivityListener
        {
            ShouldListenTo = source => string.Equals(
                source.Name,
                instrumentation.ActivitySource.Name,
                StringComparison.Ordinal),
            Sample = (ref _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = activity => stopped.Add(activity.DisplayName),
        };
        ActivitySource.AddActivityListener(listener);
        return (
            new ActivityTraceEmitter(instrumentation),
            () => stopped,
            new Both(listener, instrumentation));
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsAValidSpan(string kind)
    {
        // Arrange
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            // Act
            var result = emitter.Emit(Record("demo.request"));

            // Assert
            result.Should().BeOk();
            names().Should().Equal("demo.request");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_PreservesEmitOrder(string kind)
    {
        // Arrange
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            // Act
            var results = new[] { "first", "second", "third" }.Select(name => emitter.Emit(Record(name))).ToList();

            // Assert
            results.Should().AllSatisfy(result => result.Should().BeOk());
            names().Should().Equal("first", "second", "third");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_RejectsANullRecordAsInvalidInput(string kind)
    {
        // Arrange
        var (emitter, _, scope) = Subject(kind);
        using (scope)
        {
            // Act
            var result = emitter.Emit(null!);

            // Assert
            result.Should().BeTraceErr(TraceErrorCode.InvalidInput);
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsEveryStatus(string kind)
    {
        // Arrange
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            // Act
            var results = Enum.GetValues<TraceStatus>()
                .Select(status => emitter.Emit(Record($"span.{status}", status)))
                .ToList();

            // Assert
            results.Should().HaveCount(3).And.AllSatisfy(result => result.Should().BeOk());
            names().Should().HaveCount(3);
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsEveryAttributeKind(string kind)
    {
        // Arrange
        var (emitter, names, scope) = Subject(kind);
        var record = Record(
            "rich",
            TraceStatus.Ok,
            new("text", AttributeValue.Text("value")),
            new("integer", AttributeValue.Integer(7)),
            new("real", AttributeValue.Real(1.5)),
            new("flag", AttributeValue.Flag(true)),
            new("instant", AttributeValue.Instant(DateTimeOffset.UnixEpoch)),
            new("duration", AttributeValue.Duration(TimeSpan.FromSeconds(30))));
        using (scope)
        {
            // Act
            var result = emitter.Emit(record);

            // Assert
            result.Should().BeOk();
            names().Should().Equal("rich");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_AcceptsASpanCarryingNothingButAName(string kind)
    {
        // Arrange
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            // Act
            var result = emitter.Emit(Record("bare"));

            // Assert
            result.Should().BeOk();
            names().Should().Equal("bare");
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_FlushesSuccessfullyAndRepeatedly(string kind)
    {
        // Arrange
        var (emitter, _, scope) = Subject(kind);
        using (scope)
        {
            // Act
            var results = new[] { emitter.Flush(), emitter.Flush() };

            // Assert
            results.Should().AllSatisfy(result => result.Should().BeOk());
        }
    }

    [Theory]
    [MemberData(nameof(Emitters))]
    public void EveryEmitter_KeepsWorkingAfterAFlush(string kind)
    {
        // Arrange
        var (emitter, names, scope) = Subject(kind);
        using (scope)
        {
            emitter.Emit(Record("before")).Should().BeOk();
            emitter.Flush().Should().BeOk();

            // Act
            var result = emitter.Emit(Record("after"));

            // Assert
            result.Should().BeOk();
            names().Should().Equal("before", "after");
        }
    }

    private sealed class Nothing : IDisposable
    {
        public void Dispose()
        {
        }
    }

    private sealed class Both(IDisposable first, IDisposable second) : IDisposable
    {
        public void Dispose()
        {
            first.Dispose();
            second.Dispose();
        }
    }
}
