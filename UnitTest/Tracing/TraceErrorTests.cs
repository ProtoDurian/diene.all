namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

public class TraceErrorTests
{
    private static TraceError Subject() => TraceErrors.Io("emit", "failed").With("k", "v");

    private static TraceError Variant(string component) => component switch
    {
        "code" => TraceErrors.Unavailable("emit", "failed").With("k", "v"),
        "operation" => TraceErrors.Io("flush", "failed").With("k", "v"),
        "message" => TraceErrors.Io("emit", "other").With("k", "v"),
        "details" => TraceErrors.Io("emit", "failed"),
        _ => TraceErrors.Io("emit", "failed").With("k", "other"),
    };

    [Fact]
    public void Construct_CopiesDetailsIntoASortedMap()
    {
        // Act
        var error = new TraceError(
            TraceErrorCode.Io,
            "emit",
            "exporter refused",
            [new("zulu", "z"), new("alpha", "a")]);

        // Assert
        error.Code.Should().Be(TraceErrorCode.Io);
        error.Operation.Should().Be("emit");
        error.Message.Should().Be("exporter refused");
        error.Details.Keys.Should().Equal("alpha", "zulu");
        error.ToString().Should().Be("io/emit: exporter refused");
    }

    [Fact]
    public void Construct_DefaultsToNoDetails()
    {
        // Act
        var error = new TraceError(TraceErrorCode.Io, "emit", "failed");

        // Assert
        error.Details.Should().BeEmpty();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void Construct_RejectsABlankOperation(string? operation)
    {
        // Act
        var act = () => new TraceError(TraceErrorCode.Io, operation!, "failed");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Construct_RejectsANullMessage()
    {
        // Act
        var act = () => new TraceError(TraceErrorCode.Io, "emit", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Construct_AcceptsAnEmptyMessage()
    {
        // Act
        var error = new TraceError(TraceErrorCode.Io, "emit", "");

        // Assert
        error.Message.Should().BeEmpty();
    }

    [Fact]
    public void With_ReturnsACopyAndLeavesTheOriginalAlone()
    {
        // Arrange
        var original = TraceErrors.Io("emit", "failed");

        // Act
        var annotated = original.With("span", "demo");

        // Assert
        annotated.Should().NotBeSameAs(original);
        annotated.Details["span"].Should().Be("demo");
        original.Details.Should().BeEmpty();
        annotated.Code.Should().Be(original.Code);
        annotated.Operation.Should().Be(original.Operation);
        annotated.Message.Should().Be(original.Message);
    }

    [Fact]
    public void With_OverwritesARepeatedKey()
    {
        // Arrange
        var error = TraceErrors.Io("emit", "failed").With("k", "1");

        // Act
        var annotated = error.With("k", "2");

        // Assert
        annotated.Details["k"].Should().Be("2");
    }

    [Theory]
    [InlineData(null)]
    [InlineData(" ")]
    public void With_RejectsABlankKey(string? key)
    {
        // Arrange
        var error = TraceErrors.Io("emit", "failed");

        // Act
        var act = () => error.With(key!, "v");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void With_RejectsANullValue()
    {
        // Arrange
        var error = TraceErrors.Io("emit", "failed");

        // Act
        var act = () => error.With("k", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Equality_IsByContent()
    {
        // Arrange
        var left = Subject();

        // Act
        var right = Subject();

        // Assert
        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
        (left == right).Should().BeTrue();
        (left != right).Should().BeFalse();
    }

    [Theory]
    [InlineData("code")]
    [InlineData("operation")]
    [InlineData("message")]
    [InlineData("details")]
    [InlineData("detail value")]
    public void Equality_IsFalseOnAnyDifferingComponent(string component)
    {
        // Arrange
        var subject = Subject();

        // Act
        var equal = subject.Equals(Variant(component));

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseAgainstNull()
    {
        // Act
        var equal = Subject().Equals((TraceError?)null);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseAgainstAnotherType()
    {
        // Act
        var equal = Subject().Equals((object?)"not an error");

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Operators_TreatTwoNullsAsEqual()
    {
        // Arrange
        TraceError? none = null;

        // Act
        bool[] outcomes = [none == null, none != null];

        // Assert
        outcomes.Should().Equal(true, false);
    }

    [Fact]
    public void Operators_TreatNullAndAValueAsUnequalOnEitherSide()
    {
        // Arrange
        TraceError? none = null;
        var some = TraceErrors.Io("emit", "failed");

        // Act
        bool[] outcomes = [none == some, some == none, some != none];

        // Assert
        outcomes.Should().Equal(false, false, true);
    }

    [Fact]
    public void Catalog_MapsEachFactoryToItsCode()
    {
        // Act
        TraceErrorCode[] codes =
        [
            TraceErrors.InvalidInput("emit", "m").Code,
            TraceErrors.Io("emit", "m").Code,
            TraceErrors.Unavailable("emit", "m").Code,
            TraceErrors.UnexpectedCall("flush", "m").Code,
        ];

        // Assert
        codes.Should().Equal(
            TraceErrorCode.InvalidInput,
            TraceErrorCode.Io,
            TraceErrorCode.Unavailable,
            TraceErrorCode.UnexpectedCall);
    }
}

public class TraceWireTests
{
    [Theory]
    [InlineData(TraceStatus.Unset, "unset")]
    [InlineData(TraceStatus.Ok, "ok")]
    [InlineData(TraceStatus.Error, "error")]
    public void Name_MapsEveryStatus(TraceStatus status, string wire)
    {
        // Act
        var name = TraceWire.Name(status);

        // Assert
        name.Should().Be(wire);
    }

    [Theory]
    [InlineData(TraceErrorCode.InvalidInput, "invalid-input")]
    [InlineData(TraceErrorCode.Io, "io")]
    [InlineData(TraceErrorCode.Unavailable, "unavailable")]
    [InlineData(TraceErrorCode.UnexpectedCall, "unexpected-call")]
    public void Name_MapsEveryErrorCode(TraceErrorCode code, string wire)
    {
        // Act
        var name = TraceWire.Name(code);

        // Assert
        name.Should().Be(wire);
    }

    [Fact]
    public void Name_RejectsAnUndefinedStatus()
    {
        // Act
        var act = () => TraceWire.Name((TraceStatus)42);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void Name_RejectsAnUndefinedErrorCode()
    {
        // Act
        var act = () => TraceWire.Name((TraceErrorCode)42);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Theory]
    [InlineData("unset", TraceStatus.Unset)]
    [InlineData("ok", TraceStatus.Ok)]
    [InlineData("error", TraceStatus.Error)]
    public void ParseStatus_RoundTripsEveryWireName(string wire, TraceStatus expected)
    {
        // Act
        var result = TraceWire.ParseStatus(wire);

        // Assert
        result.Should().BeOk().Which.Should().Be(expected);
    }

    [Theory]
    [InlineData("invalid-input", TraceErrorCode.InvalidInput)]
    [InlineData("io", TraceErrorCode.Io)]
    [InlineData("unavailable", TraceErrorCode.Unavailable)]
    [InlineData("unexpected-call", TraceErrorCode.UnexpectedCall)]
    public void ParseErrorCode_RoundTripsEveryWireName(string wire, TraceErrorCode expected)
    {
        // Act
        var result = TraceWire.ParseErrorCode(wire);

        // Assert
        result.Should().BeOk().Which.Should().Be(expected);
    }

    [Theory]
    [InlineData("OK")]
    [InlineData("sideways")]
    [InlineData("")]
    public void ParseStatus_RejectsAnythingElse(string wire)
    {
        // Act
        var result = TraceWire.ParseStatus(wire);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("status");
    }

    [Theory]
    [InlineData("invalid_input")]
    [InlineData("nonsense")]
    public void ParseErrorCode_RejectsAnythingElse(string wire)
    {
        // Act
        var result = TraceWire.ParseErrorCode(wire);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("code");
    }

    [Fact]
    public void ParseFailures_ReportTheParseOperation()
    {
        // Act
        var result = TraceWire.ParseStatus("nope");

        // Assert
        result.Should().BeErr().Which.Operation.Should().Be("parse");
    }
}
