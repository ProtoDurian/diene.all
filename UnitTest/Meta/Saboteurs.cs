namespace AtomiCloud.DotnetBase.UnitTest.Meta;

internal sealed class AlwaysFailingEmitter : ITraceEmitter
{
    private static TraceError Error => TraceErrors.Io("sabotage", "always fails");

    public Result<Unit, TraceError> Emit(TraceRecord record) => Error.With("span", record?.Name ?? "<null>");

    public Result<Unit, TraceError> Flush() => Error;
}

internal sealed class AlwaysSucceedingEmitter : ITraceEmitter
{
    public List<string> Seen { get; } = [];

    public Result<Unit, TraceError> Emit(TraceRecord record)
    {
        Seen.Add(record?.Name ?? "<null>");
        return Result.Ok<Unit, TraceError>(default);
    }

    public Result<Unit, TraceError> Flush() => Result.Ok<Unit, TraceError>(default);
}

internal sealed class ForgetfulEmitter : ITraceEmitter
{
    public int Emitted { get; private set; }

    public Result<Unit, TraceError> Emit(TraceRecord record)
    {
        Emitted++;
        return Result.Ok<Unit, TraceError>(default);
    }

    public Result<Unit, TraceError> Flush() => Result.Ok<Unit, TraceError>(default);
}

public class SaboteurTests
{
    private static TraceRecord Record() => TraceRecord.Create("demo.request").Should().BeOk().Which;

    [Fact]
    public void AnAlwaysFailingEmitter_FailsEveryEmit()
    {
        // Arrange
        var emitter = new AlwaysFailingEmitter();

        // Act
        var result = emitter.Emit(Record());

        // Assert
        result.Should().BeTraceErr(TraceErrorCode.Io);
    }

    [Fact]
    public void AnAlwaysFailingEmitter_FailsEveryFlush()
    {
        // Arrange
        var emitter = new AlwaysFailingEmitter();

        // Act
        var result = emitter.Flush();

        // Assert
        result.Should().BeTraceErr(TraceErrorCode.Io);
    }

    [Fact]
    public void AnAlwaysFailingEmitter_CannotSatisfyTheAcceptanceExpectation()
    {
        // Arrange
        var emitter = new AlwaysFailingEmitter();

        // Act
        var act = () => emitter.Emit(Record()).Should().BeOk();

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void AnAlwaysSucceedingEmitter_AcceptsANullRecordItHasSeen()
    {
        // Arrange
        var emitter = new AlwaysSucceedingEmitter();

        // Act
        var result = emitter.Emit(null!);

        // Assert
        result.Should().BeOk();
        emitter.Seen.Should().Equal("<null>");
    }

    [Fact]
    public void AnAlwaysSucceedingEmitter_CannotSatisfyTheRejectionExpectation()
    {
        // Arrange
        var emitter = new AlwaysSucceedingEmitter();

        // Act
        var act = () => emitter.Emit(null!).Should().BeTraceErr(TraceErrorCode.InvalidInput);

        // Assert
        act.Should().Throw<Exception>();
        emitter.Seen.Should().AllBe("<null>");
    }

    [Fact]
    public void AForgetfulEmitter_AcceptsAndCountsTheSpan()
    {
        // Arrange
        var emitter = new ForgetfulEmitter();

        // Act
        var result = emitter.Emit(Record());

        // Assert
        result.Should().BeOk();
        emitter.Emitted.Should().Be(1);
    }

    [Fact]
    public void AForgetfulEmitter_CannotSatisfyTheCaptureExpectation()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        var act = () => emitter.Should().HaveEmitted("demo.request");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void TheRealEmitter_AcceptsAValidSpanAndCapturesIt()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        var result = emitter.Emit(Record());

        // Assert
        result.Should().BeOk();
        emitter.Should().HaveEmitted("demo.request");
    }

    [Fact]
    public void TheRealEmitter_RejectsANullRecord()
    {
        // Arrange
        var emitter = new InMemoryTraceEmitter();

        // Act
        var result = emitter.Emit(null!);

        // Assert
        result.Should().BeTraceErr(TraceErrorCode.InvalidInput);
    }
}
