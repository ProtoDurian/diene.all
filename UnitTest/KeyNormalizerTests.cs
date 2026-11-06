namespace AtomiCloud.DotnetBase.UnitTest;

public class KeyNormalizerTests
{
    [Theory]
    [InlineData("error_portal", "errorportal")]
    [InlineData("error-portal", "errorportal")]
    [InlineData("errorPortal", "errorportal")]
    [InlineData("ErrorPortal", "errorportal")]
    [InlineData("ERROR PORTAL", "errorportal")]
    [InlineData("error.portal", "errorportal")]
    [InlineData("", "")]
    [InlineData("___", "")]
    public void It_should_reduce_every_casing_and_separator_spelling_to_one_form(string key, string expected)
    {
        // Act
        var actual = KeyNormalizer.Canonical(key);

        // Assert
        actual.Should().Be(expected);
    }

    [Fact]
    public void It_should_reject_a_null_key()
    {
        // Act
        var act = FluentActions.Invoking(() => KeyNormalizer.Canonical(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [InlineData("error_portal", "ErrorPortal", true)]
    [InlineData("connection-pool", "connectionPool", true)]
    [InlineData("error_portal", "error_portals", false)]
    public void It_should_match_keys_by_their_canonical_form(string a, string b, bool expected)
    {
        // Act
        var actual = KeyNormalizer.KeysMatch(a, b);

        // Assert
        actual.Should().Be(expected);
    }
}
