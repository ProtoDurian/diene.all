namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

public class TraceEventTests
{
    private static TraceEvent Event(string name = "e", long value = 1) =>
        TraceEvent.Create(name, [new("a", AttributeValue.Integer(value))]).Should().BeOk().Which;

    [Fact]
    public void Create_AcceptsANameAndSortsAttributes()
    {
        // Act
        var result = TraceEvent.Create(
            "cache.miss",
            [new("z", AttributeValue.Text("z")), new("a", AttributeValue.Text("a"))]);

        // Assert
        var recorded = result.Should().BeOk().Which;
        recorded.Name.Should().Be("cache.miss");
        recorded.Attributes.Keys.Should().Equal("a", "z");
        recorded.ToString().Should().Be("cache.miss");
    }

    [Fact]
    public void Create_DefaultsToNoAttributes()
    {
        // Act
        var result = TraceEvent.Create("cache.miss");

        // Assert
        result.Should().BeOk().Which.Attributes.Should().BeEmpty();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_RejectsABlankName(string? name)
    {
        // Act
        var result = TraceEvent.Create(name);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("must not be blank");
    }

    [Fact]
    public void Create_PropagatesAnAttributeRejection()
    {
        // Act
        var result = TraceEvent.Create("cache.miss", [new(" ", AttributeValue.Text("x"))]);

        // Assert
        result.Should().BeErr().Which.Code.Should().Be(TraceErrorCode.InvalidInput);
    }

    [Fact]
    public void Equality_IsByContent()
    {
        // Arrange
        var left = Event();

        // Act
        var right = Event();

        // Assert
        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
    }

    [Theory]
    [InlineData("e", 2)]
    [InlineData("f", 1)]
    public void Equality_IsFalseOnADifferentNameOrAttribute(string name, long value)
    {
        // Arrange
        var left = Event();

        // Act
        var equal = left.Equals(Event(name, value));

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseAgainstNull()
    {
        // Act
        var equal = Event().Equals((TraceEvent?)null);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseAgainstAnotherType()
    {
        // Act
        var equal = Event().Equals((object?)"not an event");

        // Assert
        equal.Should().BeFalse();
    }
}

public class TraceRecordTests
{
    private static TraceEvent Recorded { get; } = TraceEvent.Create("step").Should().BeOk().Which;

    private static TraceRecord Span(
        string name = "s",
        long value = 1,
        bool withEvent = true,
        TraceStatus status = TraceStatus.Ok,
        string message = "m") =>
        TraceRecord
            .Create(name, [new("a", AttributeValue.Integer(value))], withEvent ? [Recorded] : [], status, message)
            .Should().BeOk().Which;

    private static TraceRecord Variant(string component) => component switch
    {
        "name" => Span(name: "other"),
        "attribute" => Span(value: 2),
        "events" => Span(withEvent: false),
        "status" => Span(status: TraceStatus.Error),
        _ => Span(message: "other"),
    };

    [Fact]
    public void Create_AcceptsAFullyPopulatedSpan()
    {
        // Act
        var result = TraceRecord.Create(
            "demo.request",
            [new("route", AttributeValue.Text("/v1"))],
            [Recorded],
            TraceStatus.Ok,
            "served");

        // Assert
        var record = result.Should().BeOk().Which;
        record.Name.Should().Be("demo.request");
        record.Attributes.Should().ContainKey("route");
        record.Events.Should().Equal(Recorded);
        record.Status.Should().Be(TraceStatus.Ok);
        record.StatusMessage.Should().BeSome().Which.Should().Be("served");
        record.ToString().Should().Be("demo.request ok");
    }

    [Fact]
    public void Create_DefaultsToAnUnsetSpanWithNothingAttached()
    {
        // Act
        var result = TraceRecord.Create("demo.request");

        // Assert
        var record = result.Should().BeOk().Which;
        record.Attributes.Should().BeEmpty();
        record.Events.Should().BeEmpty();
        record.Status.Should().Be(TraceStatus.Unset);
        record.StatusMessage.Should().BeNone();
        record.ToString().Should().Be("demo.request unset");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void Create_RejectsABlankName(string? name)
    {
        // Act
        var result = TraceRecord.Create(name);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("Trace name");
    }

    [Fact]
    public void Create_RejectsAnUndefinedStatus()
    {
        // Act
        var result = TraceRecord.Create("demo.request", status: (TraceStatus)42);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("status is invalid");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_RejectsABlankStatusMessage(string message)
    {
        // Act
        var result = TraceRecord.Create("demo.request", statusMessage: message);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("status message");
    }

    [Fact]
    public void Create_RejectsANullEventInTheSequence()
    {
        // Act
        var result = TraceRecord.Create("demo.request", events: [null!]);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("must not be null");
    }

    [Fact]
    public void Create_PropagatesAnAttributeRejection()
    {
        // Act
        var result = TraceRecord.Create("demo.request", [new(" ", AttributeValue.Text("x"))]);

        // Assert
        result.Should().BeErr().Which.Code.Should().Be(TraceErrorCode.InvalidInput);
    }

    [Fact]
    public void Create_CopiesTheEventSequenceSoLaterMutationCannotLeakIn()
    {
        // Arrange
        var events = new List<TraceEvent> { Recorded };
        var record = TraceRecord.Create("demo.request", events: events).Should().BeOk().Which;

        // Act
        events.Add(TraceEvent.Create("late").Should().BeOk().Which);

        // Assert
        record.Events.Should().HaveCount(1);
    }

    [Fact]
    public void Equality_IsByContent()
    {
        // Arrange
        var left = Span();

        // Act
        var right = Span();

        // Assert
        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.GetHashCode().Should().Be(right.GetHashCode());
    }

    [Fact]
    public void Equality_IsFalseAgainstNull()
    {
        // Act
        var equal = Span().Equals((TraceRecord?)null);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equality_IsFalseAgainstAnotherType()
    {
        // Act
        var equal = Span().Equals((object?)"not a span");

        // Assert
        equal.Should().BeFalse();
    }

    [Theory]
    [InlineData("name")]
    [InlineData("attribute")]
    [InlineData("events")]
    [InlineData("status")]
    [InlineData("message")]
    public void Equality_IsFalseOnAnyDifferingComponent(string component)
    {
        // Arrange
        var subject = Span();

        // Act
        var equal = subject.Equals(Variant(component));

        // Assert
        equal.Should().BeFalse();
    }
}
