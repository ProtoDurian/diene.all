namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class AssertTheAsserterTests
{
    private static TraceRecord Record(
        string name = "demo.request",
        TraceStatus status = TraceStatus.Ok) =>
        TraceRecord
            .Create(
                name,
                [new("route", AttributeValue.Text("/v1"))],
                [TraceEvent.Create("cache.miss").Should().BeOk().Which],
                status)
            .Should().BeOk().Which;

    private static InMemoryTraceEmitter Emitted(params TraceRecord[] records)
    {
        var emitter = new InMemoryTraceEmitter();
        foreach (var record in records) emitter.Emit(record).Should().BeOk();
        return emitter;
    }

    private static InMemoryTraceEmitter FlushedOnce()
    {
        var emitter = new InMemoryTraceEmitter();
        emitter.Flush().Should().BeOk();
        return emitter;
    }

    [Fact]
    public void HaveEmitted_PassesOnAMatchAndYieldsTheSpan()
    {
        // Arrange
        var emitter = Emitted(Record());

        // Act
        var span = emitter.Should().HaveEmitted("demo.request").Which;

        // Assert
        span.Name.Should().Be("demo.request");
    }

    [Fact]
    public void HaveEmitted_FailsOnAMiss()
    {
        // Arrange
        var emitter = Emitted(Record());

        // Act
        var act = () => emitter.Should().HaveEmitted("other");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEmitted_FailsOnAnEmptyEmitterAndSaysSo()
    {
        // Act
        var act = () => new InMemoryTraceEmitter().Should().HaveEmitted("demo.request");

        // Assert
        act.Should().Throw<Exception>().WithMessage("*no spans*");
    }

    [Fact]
    public void NotHaveEmitted_PassesWhenAbsent()
    {
        // Arrange
        var emitter = Emitted(Record());

        // Act
        var act = () => emitter.Should().NotHaveEmitted("other");

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void NotHaveEmitted_FailsWhenPresent()
    {
        // Arrange
        var emitter = Emitted(Record());

        // Act
        var act = () => emitter.Should().NotHaveEmitted("demo.request");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEmittedExactly_PassesOnTheExactSequence()
    {
        // Arrange
        var emitter = Emitted(Record("first"), Record("second"));

        // Act
        var act = () => emitter.Should().HaveEmittedExactly(["first", "second"]);

        // Assert
        act.Should().NotThrow();
    }

    [Theory]
    [InlineData("second", "first")]
    [InlineData("first")]
    [InlineData("first", "second", "third")]
    public void HaveEmittedExactly_FailsOnAnyDeviation(params string[] expected)
    {
        // Arrange
        var emitter = Emitted(Record("first"), Record("second"));

        // Act
        var act = () => emitter.Should().HaveEmittedExactly(expected);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEmittedExactly_RejectsANullSequence()
    {
        // Arrange
        var emitter = Emitted(Record());

        // Act
        var act = () => emitter.Should().HaveEmittedExactly(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void HaveFlushed_PassesOnTheExactCount()
    {
        // Arrange
        var emitter = FlushedOnce();

        // Act
        var act = () => emitter.Should().HaveFlushed(1);

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void HaveFlushed_FailsOnALowerCount()
    {
        // Arrange
        var emitter = FlushedOnce();

        // Act
        var act = () => emitter.Should().HaveFlushed(0);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveFlushed_FailsOnAHigherCount()
    {
        // Arrange
        var emitter = FlushedOnce();

        // Act
        var act = () => emitter.Should().HaveFlushed(2);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveAttribute_PassesOnAMatch()
    {
        // Arrange
        var record = Record();

        // Act
        var act = () => record.Should().HaveAttribute("route", AttributeValue.Text("/v1"));

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void HaveAttribute_FailsOnAWrongValue()
    {
        // Arrange
        var record = Record();

        // Act
        var act = () => record.Should().HaveAttribute("route", AttributeValue.Text("/v2"));

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveAttribute_FailsOnAMissingKeyAndSaysSo()
    {
        // Arrange
        var record = Record();

        // Act
        var act = () => record.Should().HaveAttribute("missing", AttributeValue.Text("/v1"));

        // Assert
        act.Should().Throw<Exception>().WithMessage("*no 'missing'*");
    }

    [Fact]
    public void HaveEvent_PassesOnAMatchAndYieldsTheEvent()
    {
        // Arrange
        var record = Record();

        // Act
        var recorded = record.Should().HaveEvent("cache.miss").Which;

        // Assert
        recorded.Name.Should().Be("cache.miss");
    }

    [Fact]
    public void HaveEvent_FailsOnAMiss()
    {
        // Arrange
        var record = Record();

        // Act
        var act = () => record.Should().HaveEvent("other");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveEvent_FailsOnAnEventlessSpanAndSaysSo()
    {
        // Arrange
        var record = TraceRecord.Create("bare").Should().BeOk().Which;

        // Act
        var act = () => record.Should().HaveEvent("cache.miss");

        // Assert
        act.Should().Throw<Exception>().WithMessage("*no events*");
    }

    [Fact]
    public void HaveStatus_PassesOnAMatch()
    {
        // Arrange
        var record = Record(status: TraceStatus.Error);

        // Act
        var act = () => record.Should().HaveStatus(TraceStatus.Error);

        // Assert
        act.Should().NotThrow();
    }

    [Theory]
    [InlineData(TraceStatus.Ok)]
    [InlineData(TraceStatus.Unset)]
    public void HaveStatus_FailsOnAnyOtherOutcome(TraceStatus expected)
    {
        // Arrange
        var record = Record(status: TraceStatus.Error);

        // Act
        var act = () => record.Should().HaveStatus(expected);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeTraceErr_PassesOnTheExactCodeAndYieldsTheError()
    {
        // Arrange
        var failure = Result.Err<Unit, TraceError>(TraceErrors.Io("emit", "exporter refused"));

        // Act
        var error = failure.Should().BeTraceErr(TraceErrorCode.Io).Which;

        // Assert
        error.Message.Should().Be("exporter refused");
    }

    [Fact]
    public void BeTraceErr_FailsOnAnotherCode()
    {
        // Arrange
        var failure = Result.Err<Unit, TraceError>(TraceErrors.Io("emit", "exporter refused"));

        // Act
        var act = () => failure.Should().BeTraceErr(TraceErrorCode.InvalidInput);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeTraceErr_FailsOnASuccessfulResult()
    {
        // Arrange
        var success = Result.Ok<Unit, TraceError>(default);

        // Act
        var act = () => success.Should().BeTraceErr(TraceErrorCode.Io);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeTraceErr_RejectsNullAssertions()
    {
        // Act
        var act = () => TraceAssertionExtensions.BeTraceErr<Unit>(null!, TraceErrorCode.Io);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Should_RootsAnEmitterChainOnTheEmitterItWasGiven()
    {
        // Arrange
        var emitter = Emitted(Record());

        // Act
        var subject = emitter.Should().Subject;

        // Assert
        ReferenceEquals(subject, emitter).Should().BeTrue();
    }

    [Fact]
    public void Should_RootsARecordChainOnTheRecordItWasGiven()
    {
        // Arrange
        var record = Record();

        // Act
        var subject = record.Should().Subject;

        // Assert
        ReferenceEquals(subject, record).Should().BeTrue();
    }
}
