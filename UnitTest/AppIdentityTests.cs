namespace AtomiCloud.DotnetBase.UnitTest;

public class AppIdentityTests
{
    [Fact]
    public void Create_TrimsEveryField()
    {
        // Act
        var result = AppIdentity.Create(" lapras ", " atomi ", " billing ", " api ", " 1.2.3 ");

        // Assert
        result.Should().BeOk().Which.Should().Be(new AppIdentity("lapras", "atomi", "billing", "api", "1.2.3"));
    }

    [Theory]
    [InlineData(null, "atomi", "billing", "api", "1.0.0")]
    [InlineData("", "atomi", "billing", "api", "1.0.0")]
    [InlineData("  ", "atomi", "billing", "api", "1.0.0")]
    [InlineData("lapras", " ", "billing", "api", "1.0.0")]
    [InlineData("lapras", "atomi", " ", "api", "1.0.0")]
    [InlineData("lapras", "atomi", "billing", " ", "1.0.0")]
    [InlineData("lapras", "atomi", "billing", "api", " ")]
    public void Create_RejectsAnyBlankField(
        string? landscape,
        string? platform,
        string? service,
        string? module,
        string? version)
    {
        // Act
        var result = AppIdentity.Create(landscape, platform, service, module, version);

        // Assert
        result.Should().BeErr().Which.Id.Should().Be("invalid_argument");
    }

    [Fact]
    public void Create_NamesTheFieldItRejected()
    {
        // Act
        var result = AppIdentity.Create("lapras", "atomi", "billing", " ", "1.0.0");

        // Assert
        result.Should().BeErr().Which.Detail.Should().Contain("module");
    }

    [Fact]
    public void Identity_IsEqualWithTheSameHashToAnIdenticalIdentity()
    {
        // Arrange
        var left = new AppIdentity("lapras", "atomi", "billing", "api", "1.0.0");

        // Act
        var right = new AppIdentity("lapras", "atomi", "billing", "api", "1.0.0");

        // Assert
        left.Should().Be(right);
        left.GetHashCode().Should().Be(right.GetHashCode());
    }

    [Fact]
    public void Identity_DiffersWhenAnyFieldDiffers()
    {
        // Arrange
        var identity = new AppIdentity("lapras", "atomi", "billing", "api", "1.0.0");

        // Act
        var other = identity with { Module = "worker" };

        // Assert
        identity.Should().NotBe(other);
    }
}
