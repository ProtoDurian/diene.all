namespace AtomiCloud.DotnetBase.UnitTest.Tracing;

public class TraceAttributesTests
{
    private static Dictionary<string, AttributeValue> Of(string key, AttributeValue value) =>
        new(StringComparer.Ordinal) { [key] = value };

    [Fact]
    public void Empty_IsAnEmptyMap()
    {
        // Act
        var empty = TraceAttributes.Empty;

        // Assert
        empty.Should().BeEmpty();
    }

    [Fact]
    public void Empty_EqualsItself()
    {
        // Act
        var equal = TraceAttributes.Equal(TraceAttributes.Empty, TraceAttributes.Empty);

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void Check_TreatsNullAsEmpty()
    {
        // Act
        var result = TraceAttributes.Check(null, "emit");

        // Assert
        result.Should().BeOk().Which.Should().BeEmpty();
    }

    [Fact]
    public void Check_SortsKeysSoOrderCannotAffectEquality()
    {
        // Arrange
        KeyValuePair<string, AttributeValue>[] attributes =
        [
            new("zulu", AttributeValue.Text("z")),
            new("alpha", AttributeValue.Text("a")),
            new("mike", AttributeValue.Text("m")),
        ];

        // Act
        var result = TraceAttributes.Check(attributes, "emit");

        // Assert
        result.Should().BeOk().Which.Keys.Should().Equal("alpha", "mike", "zulu");
    }

    [Fact]
    public void Check_KeepsTheLastValueForARepeatedKey()
    {
        // Arrange
        KeyValuePair<string, AttributeValue>[] attributes =
            [new("key", AttributeValue.Integer(1)), new("key", AttributeValue.Integer(2))];

        // Act
        var result = TraceAttributes.Check(attributes, "emit");

        // Assert
        result.Should().BeOk().Which["key"].Should().Be(AttributeValue.Integer(2));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("\t")]
    public void Check_RejectsABlankKey(string key)
    {
        // Act
        var result = TraceAttributes.Check(Of(key, AttributeValue.Text("value")), "emit");

        // Assert
        result.Should().BeErr().Which.Code.Should().Be(TraceErrorCode.InvalidInput);
    }

    [Fact]
    public void Check_RejectsAKeyCarryingANul()
    {
        // Arrange
        // Built at runtime: a literal control byte in source is a corruption hazard.
        var key = "route" + (char)0 + "suffix";

        // Act
        var result = TraceAttributes.Check(Of(key, AttributeValue.Text("value")), "emit");

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("NUL-free");
    }

    [Fact]
    public void Check_AcceptsAKeyCarryingASpace()
    {
        // Act
        var result = TraceAttributes.Check(Of("two words", AttributeValue.Text("value")), "emit");

        // Assert
        result.Should().BeOk();
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void Check_RejectsANonFiniteReal(double value)
    {
        // Act
        var result = TraceAttributes.Check(Of("ratio", AttributeValue.Real(value)), "emit");

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("finite");
    }

    [Fact]
    public void Check_AcceptsEveryOtherAttributeKind()
    {
        // Arrange
        KeyValuePair<string, AttributeValue>[] attributes =
        [
            new("text", AttributeValue.Text("value")),
            new("integer", AttributeValue.Integer(long.MaxValue)),
            new("real", AttributeValue.Real(1.5)),
            new("flag", AttributeValue.Flag(true)),
            new("instant", AttributeValue.Instant(DateTimeOffset.UnixEpoch)),
            new("duration", AttributeValue.Duration(TimeSpan.FromSeconds(90))),
        ];

        // Act
        var result = TraceAttributes.Check(attributes, "emit");

        // Assert
        result.Should().BeOk().Which.Should().HaveCount(6);
    }

    [Fact]
    public void Check_ReportsTheOperationItWasGiven()
    {
        // Act
        var result = TraceAttributes.Check(Of(" ", AttributeValue.Text("x")), "flush");

        // Assert
        result.Should().BeErr().Which.Operation.Should().Be("flush");
    }

    [Fact]
    public void Equal_ComparesByContentNotByOrderOrIdentity()
    {
        // Arrange
        var left = TraceAttributes
            .Check([new("a", AttributeValue.Integer(1)), new("b", AttributeValue.Integer(2))], "emit")
            .Should().BeOk().Which;
        var right = TraceAttributes
            .Check([new("b", AttributeValue.Integer(2)), new("a", AttributeValue.Integer(1))], "emit")
            .Should().BeOk().Which;

        // Act
        var equal = TraceAttributes.Equal(left, right);

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void Equal_IsFalseOnACountMismatch()
    {
        // Act
        var equal = TraceAttributes.Equal(Of("a", AttributeValue.Integer(1)), TraceAttributes.Empty);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equal_IsFalseOnAMissingKey()
    {
        // Act
        var equal = TraceAttributes.Equal(Of("a", AttributeValue.Integer(1)), Of("b", AttributeValue.Integer(1)));

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equal_IsFalseOnADifferentValue()
    {
        // Act
        var equal = TraceAttributes.Equal(Of("a", AttributeValue.Integer(1)), Of("a", AttributeValue.Integer(2)));

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void Equal_RejectsANullLeftMap()
    {
        // Act
        var act = () => TraceAttributes.Equal(null!, TraceAttributes.Empty);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Equal_RejectsANullRightMap()
    {
        // Act
        var act = () => TraceAttributes.Equal(TraceAttributes.Empty, null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
