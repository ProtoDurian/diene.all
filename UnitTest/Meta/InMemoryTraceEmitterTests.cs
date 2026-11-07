namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class InMemoryTraceEmitterTests
{
    private static TraceRecord Record(string name = "demo.request") =>
        TraceRecord
            .Create(name, [new("route", AttributeValue.Text("/v1"))], status: TraceStatus.Ok, statusMessage: "served")
            .Should().BeOk().Which;

    [Fact]
    public void Emit_CapturesTheSpanAndTheCall()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        var record = Record();

        // Act
        var result = emitter.Emit(record);

        // Assert
        result.Should().BeOk();
        emitter.Records.Should().Equal(record);
        emitter.Calls.Should().ContainSingle().Which.Should()
            .Be(new TraceCall(0, TraceCallKind.Emit, Option.Some(record)));
    }

    [Fact]
    public void Calls_AreSequencedAcrossBothMethods()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        Result<Unit, TraceError>[] results =
        [
            emitter.Emit(Record("first")),
            emitter.Flush(),
            emitter.Emit(Record("second")),
        ];

        // Assert
        results.Should().AllSatisfy(result => result.Should().BeOk());
        emitter.Calls.Select(call => call.Sequence).Should().Equal(0, 1, 2);
        emitter.Calls.Select(call => call.Kind).Should()
            .Equal(TraceCallKind.Emit, TraceCallKind.Flush, TraceCallKind.Emit);
    }

    [Fact]
    public void Flush_CarriesNoSpanAndIsCounted()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        Result<Unit, TraceError>[] results = [emitter.Flush(), emitter.Flush()];

        // Assert
        results.Should().AllSatisfy(result => result.Should().BeOk());
        emitter.Flushes.Should().Be(2);
        emitter.Calls.Should().AllSatisfy(call => call.Record.Should().BeNone());
        emitter.Records.Should().BeEmpty();
    }

    [Fact]
    public void FailNext_FailsTheNextEmitAndRecordsTheAttemptWithoutAcceptingIt()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        var error = TraceErrors.Io("emit", "exporter refused");
        emitter.FailNext(error);

        // Act
        var result = emitter.Emit(Record());

        // Assert
        result.Should().BeErr().Which.Should().Be(error);
        emitter.Records.Should().BeEmpty();
        emitter.Calls.Should().ContainSingle().Which.Kind.Should().Be(TraceCallKind.Emit);
    }

    [Fact]
    public void FailNext_AppliesToAFlushToo()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        var error = TraceErrors.Unavailable("flush", "shutting down");
        emitter.FailNext(error);

        // Act
        var first = emitter.Flush();
        var second = emitter.Flush();

        // Assert
        first.Should().BeErr().Which.Should().Be(error);
        second.Should().BeOk();
    }

    [Fact]
    public void FailNext_IsConsumedOnceAndQueuesInOrder()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        var first = TraceErrors.Io("emit", "first");
        var second = TraceErrors.Unavailable("emit", "second");
        emitter.FailNext(first);
        emitter.FailNext(second);

        // Act
        var results = new[] { emitter.Emit(Record()), emitter.Emit(Record()), emitter.Emit(Record()) };

        // Assert
        results[0].Should().BeErr().Which.Should().Be(first);
        results[1].Should().BeErr().Which.Should().Be(second);
        results[2].Should().BeOk();
        emitter.Records.Should().HaveCount(1);
    }

    [Fact]
    public void FailNext_RejectsANullError()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        var act = () => emitter.FailNext(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Emit_RejectsANullRecordWithoutRecordingACall()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        var result = emitter.Emit(null!);

        // Assert
        result.Should().BeErr().Which.Code.Should().Be(TraceErrorCode.InvalidInput);
        emitter.Calls.Should().BeEmpty();
    }

    [Theory]
    [InlineData("a", 2)]
    [InlineData("b", 1)]
    [InlineData("missing", 0)]
    public void Named_FiltersTheAcceptedSpansByName(string name, int expected)
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        emitter.Emit(Record("a")).Should().BeOk();
        emitter.Emit(Record("b")).Should().BeOk();
        emitter.Emit(Record("a")).Should().BeOk();

        // Act
        var named = emitter.Named(name);

        // Assert
        named.Select(record => record.Name).Should().Equal(Enumerable.Repeat(name, expected));
    }

    [Fact]
    public void Named_RejectsANullName()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        var act = () => emitter.Named(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Clear_DiscardsSpansCallsAndQueuedFailures()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        emitter.Emit(Record()).Should().BeOk();
        emitter.Flush().Should().BeOk();
        emitter.FailNext(TraceErrors.Io("emit", "queued"));

        // Act
        emitter.Clear();

        // Assert
        emitter.Records.Should().BeEmpty();
        emitter.Calls.Should().BeEmpty();
        emitter.Flushes.Should().Be(0);
        emitter.Emit(Record()).Should().BeOk();
    }

    [Fact]
    public void Snapshots_AreCopiesSoALaterCallCannotMutateAnEarlierReading()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();
        emitter.Emit(Record()).Should().BeOk();
        var records = emitter.Records;
        var calls = emitter.Calls;

        // Act
        emitter.Emit(Record("later")).Should().BeOk();

        // Assert
        records.Should().HaveCount(1);
        calls.Should().HaveCount(1);
    }

    [Fact]
    public void TraceCall_IsEqualWithTheSameHashToAnIdenticalCall()
    {
        // Arrange
        var record = Record();
        var left = new TraceCall(0, TraceCallKind.Emit, Option.Some(record));

        // Act
        var right = new TraceCall(0, TraceCallKind.Emit, Option.Some(record));

        // Assert
        left.Should().Be(right);
        left.GetHashCode().Should().Be(right.GetHashCode());
    }

    [Theory]
    [InlineData(1, TraceCallKind.Emit)]
    [InlineData(0, TraceCallKind.Flush)]
    public void TraceCall_DiffersOnADifferentSequenceOrKind(int sequence, TraceCallKind kind)
    {
        // Arrange
        var record = Record();
        var left = new TraceCall(0, TraceCallKind.Emit, Option.Some(record));

        // Act
        var right = new TraceCall(sequence, kind, Option.Some(record));

        // Assert
        left.Should().NotBe(right);
    }
}
