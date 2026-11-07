namespace AtomiCloud.DotnetBase.UnitTest;

public class AtomiResourceTests
{
    private static AppIdentity Identity { get; } = new("lapras", "atomi", "billing", "api", "1.2.3");

    [Theory]
    [InlineData("deployment.environment.name", "lapras")]
    [InlineData("service.namespace", "atomi")]
    [InlineData("service.name", "billing")]
    [InlineData("service.version", "1.2.3")]
    [InlineData("atomi.landscape", "lapras")]
    [InlineData("atomi.platform", "atomi")]
    [InlineData("atomi.service", "billing")]
    [InlineData("atomi.module", "api")]
    [InlineData("atomi.version", "1.2.3")]
    public void Map_LandsEveryIdentityValueOnItsKey(string key, string expected)
    {
        // Act
        var mapped = AtomiResource.Map(Identity);

        // Assert
        mapped[key].Should().Be(expected);
    }

    [Fact]
    public void Map_ShipsNineKeysAndNoSemconvTwinForModule()
    {
        // Act
        var mapped = AtomiResource.Map(Identity);

        // Assert
        mapped.Should().HaveCount(9);
        mapped.Keys.Should().NotContain("service.module");
    }

    [Fact]
    public void Map_RejectsANullIdentity()
    {
        // Act
        var act = () => AtomiResource.Map(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void SemconvKeys_AreTheSpecSpellings()
    {
        // Act
        string[] keys =
        [
            AtomiResource.DeploymentEnvironmentNameKey,
            AtomiResource.ServiceNamespaceKey,
            AtomiResource.ServiceNameKey,
            AtomiResource.ServiceVersionKey,
        ];

        // Assert
        keys.Should().Equal("deployment.environment.name", "service.namespace", "service.name", "service.version");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ParseResourceAttributes_TreatsAnAbsentValueAsEmpty(string? value)
    {
        // Act
        var parsed = AtomiResource.ParseResourceAttributes(value);

        // Assert
        parsed.Should().BeEmpty();
    }

    [Fact]
    public void ParseResourceAttributes_ReadsABaggageStyleList()
    {
        // Act
        var parsed = AtomiResource.ParseResourceAttributes(" tenant = acme , region=ap-southeast-1 ");

        // Assert
        parsed.Should().HaveCount(2);
        parsed["tenant"].Should().Be("acme");
        parsed["region"].Should().Be("ap-southeast-1");
    }

    [Theory]
    [InlineData("malformed")]
    [InlineData("=orphan")]
    [InlineData(" =orphan")]
    [InlineData(",,")]
    public void ParseResourceAttributes_DropsUnusableEntriesRatherThanFailing(string value)
    {
        // Act
        var parsed = AtomiResource.ParseResourceAttributes(value);

        // Assert
        parsed.Should().BeEmpty();
    }

    [Fact]
    public void ParseResourceAttributes_KeepsAnEmptyValueForAKnownKey()
    {
        // Act
        var parsed = AtomiResource.ParseResourceAttributes("tenant=");

        // Assert
        parsed["tenant"].Should().BeEmpty();
    }

    [Fact]
    public void ParseResourceAttributes_KeepsAValueContainingAnEqualsSign()
    {
        // Act
        var parsed = AtomiResource.ParseResourceAttributes("filter=a=b");

        // Assert
        parsed["filter"].Should().Be("a=b");
    }

    [Fact]
    public void Attributes_UsesTheBlockWhenNoEnvironmentOverridesExist()
    {
        // Act
        var attributes = AtomiResource.Attributes(Identity, Env.None);

        // Assert
        attributes.Should().BeEquivalentTo(AtomiResource.Map(Identity));
    }

    [Fact]
    public void Attributes_LetsResourceAttributesOverrideABlockDerivedValue()
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.ResourceAttributesVariable, "service.name=override,tenant=acme"));

        // Act
        var attributes = AtomiResource.Attributes(Identity, environment);

        // Assert
        attributes
            .Should().Contain(new KeyValuePair<string, string>("service.name", "override"))
            .And.Contain(new KeyValuePair<string, string>("tenant", "acme"));
    }

    [Fact]
    public void Attributes_LetsServiceNameWinOverResourceAttributes()
    {
        // Arrange
        var environment = Env.Of(
            (OtelEnvironment.ResourceAttributesVariable, "service.name=from-list"),
            (OtelEnvironment.ServiceNameVariable, " from-variable "));

        // Act
        var attributes = AtomiResource.Attributes(Identity, environment);

        // Assert
        attributes[AtomiResource.ServiceNameKey].Should().Be("from-variable");
    }

    [Fact]
    public void Attributes_IgnoresABlankServiceNameOverride()
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.ServiceNameVariable, "  "));

        // Act
        var attributes = AtomiResource.Attributes(Identity, environment);

        // Assert
        attributes[AtomiResource.ServiceNameKey].Should().Be("billing");
    }

    [Fact]
    public void Attributes_RejectsANullEnvironment()
    {
        // Act
        var act = () => AtomiResource.Attributes(Identity, null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Build_ProducesAResourceCarryingTheMappedAttributes()
    {
        // Act
        var resource = AtomiResource.Build(Identity, Env.None).Build();

        // Assert
        resource.Attributes.Should().Contain(new KeyValuePair<string, object>("service.name", "billing"));
        resource.Attributes.Should().Contain(new KeyValuePair<string, object>("atomi.module", "api"));
        resource.Attributes.Should().HaveCount(9);
    }
}
