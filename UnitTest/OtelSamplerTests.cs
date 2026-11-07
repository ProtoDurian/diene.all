namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelSamplerTests
{
    [Fact]
    public void Names_AreTheCanonicalSamplerTypes()
    {
        // Act
        string[] names = [OtelSampler.ParentBasedTraceIdRatio, OtelSampler.AlwaysOn, OtelSampler.AlwaysOff];

        // Assert
        names.Should().Equal("parentbased_traceidratio", "always_on", "always_off");
    }

    [Fact]
    public void Create_MapsAlwaysOn()
    {
        // Act
        var result = OtelSampler.Create(new SamplerOption { Type = OtelSampler.AlwaysOn }, Env.None);

        // Assert
        result.Should().BeOk().Which.Should().BeSome().Which.Description.Should().Be("AlwaysOnSampler");
    }

    [Fact]
    public void Create_MapsAlwaysOff()
    {
        // Act
        var result = OtelSampler.Create(new SamplerOption { Type = OtelSampler.AlwaysOff }, Env.None);

        // Assert
        result.Should().BeOk().Which.Should().BeSome().Which.Description.Should().Be("AlwaysOffSampler");
    }

    [Theory]
    [InlineData(0.0)]
    [InlineData(0.25)]
    [InlineData(1.0)]
    public void Create_WrapsARatioSamplerInAParentBasedDecision(double ratio)
    {
        // Arrange
        var option = new SamplerOption { Type = OtelSampler.ParentBasedTraceIdRatio, Ratio = ratio };

        // Act
        var result = OtelSampler.Create(option, Env.None);

        // Assert
        result.Should().BeOk()
            .Which.Should().BeSome()
            .Which.Description.Should().StartWith("ParentBased{TraceIdRatioBasedSampler{");
    }

    [Theory]
    [InlineData(-0.1)]
    [InlineData(1.1)]
    [InlineData(double.NaN)]
    public void Create_RejectsARatioOutsideTheUnitInterval(double ratio)
    {
        // Arrange
        var option = new SamplerOption { Type = OtelSampler.ParentBasedTraceIdRatio, Ratio = ratio };

        // Act
        var result = OtelSampler.Create(option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("between 0 and 1");
    }

    [Theory]
    [InlineData("traceidratio")]
    [InlineData("coin_flip")]
    [InlineData("")]
    public void Create_RejectsAnUnsupportedType(string type)
    {
        // Act
        var result = OtelSampler.Create(new SamplerOption { Type = type }, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("not a supported sampler type");
    }

    [Fact]
    public void Create_DefersToTheSdkWhenTheEnvironmentNamesASampler()
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.TracesSamplerVariable, "always_off"));

        // Act
        var result = OtelSampler.Create(new SamplerOption { Type = OtelSampler.AlwaysOn }, environment);

        // Assert
        result.Should().BeOk().Which.Should().BeNone();
    }

    [Fact]
    public void Create_IgnoresABlankSamplerOverride()
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.TracesSamplerVariable, "  "));

        // Act
        var result = OtelSampler.Create(new SamplerOption { Type = OtelSampler.AlwaysOn }, environment);

        // Assert
        result.Should().BeOk().Which.Should().BeSome();
    }

    [Fact]
    public void Create_ReportsAnUnsupportedTypeAsASamplerFailure()
    {
        // Act
        var result = OtelSampler.Create(new SamplerOption { Type = "nope" }, Env.None);

        // Assert
        result.Should().BeErr().Which.Operation.Should().Be("sampler");
    }

    [Fact]
    public void Create_RejectsANullOption()
    {
        // Act
        var act = () => OtelSampler.Create(null!, Env.None);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Create_RejectsANullEnvironment()
    {
        // Act
        var act = () => OtelSampler.Create(new SamplerOption(), null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}

public class InstrumentationTests
{
    private static AppIdentity Identity { get; } = new("lapras", "atomi", "billing", "api", "1.2.3");

    [Fact]
    public void Construct_NamesBothSourcesFromTheIdentity()
    {
        // Act
        using var instrumentation = new Instrumentation(Identity);

        // Assert
        instrumentation.Identity.Should().Be(Identity);
        instrumentation.ActivitySource.Name.Should().Be("billing");
        instrumentation.ActivitySource.Version.Should().Be("1.2.3");
        instrumentation.Meter.Name.Should().Be("billing");
        instrumentation.Meter.Version.Should().Be("1.2.3");
    }

    [Fact]
    public void Construct_RejectsANullIdentity()
    {
        // Act
        var act = () => new Instrumentation(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Dispose_IsIdempotent()
    {
        // Arrange
        var instrumentation = new Instrumentation(Identity);
        instrumentation.Dispose();

        // Act
        var act = instrumentation.Dispose;

        // Assert
        act.Should().NotThrow();
    }
}

public class OtelBlockSchemaTests
{
    [Fact]
    public void ResourceName_IsTheEmbeddedLogicalName()
    {
        // Act
        var name = OtelBlockSchema.ResourceName;

        // Assert
        name.Should().Be("AtomiCloud.Diene.Otel.otel-block.schema.json");
    }

    [Fact]
    public void Json_IsTheEngineOwnedBlockSchema()
    {
        // Act
        var json = OtelBlockSchema.Json;

        // Assert
        json.Should().Contain("\"$schema\"");
        json.Should().Contain("parentbased_traceidratio");
        json.Should().Contain("http/protobuf");
    }

    [Fact]
    public void Json_IsLoadedOnceAndCached()
    {
        // Arrange
        var first = OtelBlockSchema.Json;

        // Act
        var second = OtelBlockSchema.Json;

        // Assert
        second.Should().BeSameAs(first);
    }
}
