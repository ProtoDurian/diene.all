using System.Text.Json;
using AtomiCloud.Diene.Results;
using AtomiCloud.DotnetBase.App;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.IntTest;

public class C0Fixture_RoundTrip
{
    [Fact]
    public void It_should_serialize_a_success_like_the_versioned_source_fixture()
    {
        // Arrange
        var expected = FixtureCase("ok");

        // Act
        var actual = Equivalent(Result.Ok<int, string>(42).ToSerial(), expected);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_serialize_a_failure_like_the_versioned_source_fixture()
    {
        // Arrange
        var expected = FixtureCase("err");

        // Act
        var actual = Equivalent(Result.Err<int, string>("boom").ToSerial(), expected);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_serialize_some_like_the_versioned_source_fixture()
    {
        // Arrange
        var expected = FixtureCase("some");

        // Act
        var actual = Equivalent(Option.Some("value").ToSerial(), expected);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_serialize_none_like_the_versioned_source_fixture()
    {
        // Arrange
        var expected = FixtureCase("none");

        // Act
        var actual = Equivalent(Option.None<string>().ToSerial(), expected);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_run_the_package_consumer_sample()
    {
        // Arrange
        using var output = new StringWriter();
        var original = Console.Out;

        // Act
        try
        {
            Console.SetOut(output);
            Program.Main();
        }
        finally
        {
            Console.SetOut(original);
        }

        // Assert
        output.ToString().Trim().Should().Be("Success: 42");
    }

    private static JsonElement FixtureCase(string name)
    {
        var fixturePath = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "monad-v1.json");
        using var document = JsonDocument.Parse(File.ReadAllText(fixturePath));
        return document.RootElement.GetProperty("cases").GetProperty(name).Clone();
    }

    private static bool Equivalent<T>(T value, JsonElement expected) =>
        JsonElement.DeepEquals(JsonDocument.Parse(JsonSerializer.Serialize(value)).RootElement, expected);
}
