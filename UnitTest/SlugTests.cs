namespace AtomiCloud.DotnetBase.UnitTest;

public class SlugTests
{
    [Theory]
    [InlineData("Hello, World!", "hello-world")]
    [InlineData("  Crème Brûlée  ", "creme-brulee")]
    [InlineData("ÅNGSTRÖM__unit", "angstrom-unit")]
    [InlineData("already-kebab", "already-kebab")]
    [InlineData("MiXeD CaSe 42", "mixed-case-42")]
    [InlineData("---leading and trailing---", "leading-and-trailing")]
    [InlineData("ß", "")]
    [InlineData("", "")]
    [InlineData("!!!", "")]
    public void It_should_fold_input_into_a_deterministic_kebab_slug(string input, string expected)
    {
        // Act
        var actual = Slug.Slugify(input);

        // Assert
        actual.Should().Be(expected);
    }

    [Fact]
    public void It_should_reject_a_null_input()
    {
        // Act
        var act = FluentActions.Invoking(() => Slug.Slugify(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_compose_a_namespaced_key_from_slugified_parts()
    {
        // Act
        var actual = Slug.NamespacedKey("AtomiCloud", "Express Parcel");

        // Assert
        actual.Should().BeOk("atomicloud:express-parcel");
    }

    [Fact]
    public void It_should_reject_a_namespace_that_slugifies_to_empty()
    {
        // Act
        var actual = Slug.NamespacedKey("!!!", "key");

        // Assert
        actual.Should().BeErr(new KeyError("namespace must not be empty", "!!!"));
    }

    [Fact]
    public void It_should_reject_a_key_that_slugifies_to_empty()
    {
        // Act
        var actual = Slug.NamespacedKey("ns", "   ");

        // Assert
        actual.Should().BeErr(new KeyError("key must not be empty", "   "));
    }

    [Fact]
    public void It_should_reject_a_null_namespace_part()
    {
        // Act
        var act = FluentActions.Invoking(() => Slug.NamespacedKey(null!, "key"));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_key_part()
    {
        // Act
        var act = FluentActions.Invoking(() => Slug.NamespacedKey("ns", null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
