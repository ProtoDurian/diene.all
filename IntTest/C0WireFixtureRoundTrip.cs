using System.Text.Json;
using AtomiCloud.DotnetBase.App.Adapters;

namespace AtomiCloud.DotnetBase.IntTest;

public class C0WireFixtureRoundTrip : IDisposable
{
    private static readonly string Source = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "seam-wire-v1.json");

    private readonly HostVfs _vfs = new();

    private readonly string _scratch = Path.Combine(Path.GetTempPath(), $"diene-interfaces-c0-{Guid.NewGuid():N}");

    private static CancellationToken Token => TestContext.Current.CancellationToken;

    private string Copy => Path.Combine(_scratch, "seam-wire-v1.json");

    public void Dispose()
    {
        if (Directory.Exists(_scratch)) Directory.Delete(_scratch, true);
        GC.SuppressFinalize(this);
    }

    private async Task<JsonElement> CarryFixture()
    {
        var original = (await _vfs.ReadText(Source, Token)).Should().BeOk().Which;
        (await _vfs.WriteText(Copy, original, new VfsWriteOptions(true), Token)).Should().BeOk();
        var carried = (await _vfs.ReadText(Copy, Token)).Should().BeOk().Which;
        using var document = JsonDocument.Parse(carried);
        return document.RootElement.Clone();
    }

    [Fact]
    public async Task It_should_carry_the_fixture_verbatim_through_the_host_filesystem()
    {
        // Arrange
        var original = (await _vfs.ReadText(Source, Token)).Should().BeOk().Which;

        // Act
        var written = await _vfs.WriteText(Copy, original, new VfsWriteOptions(true), Token);
        var reread = await _vfs.ReadText(Copy, Token);

        // Assert
        written.Should().BeOk();
        reread.Should().BeOk(original);
    }

    [Fact]
    public async Task It_should_carry_the_fixture_version()
    {
        // Act
        var fixture = await CarryFixture();

        // Assert
        fixture.GetProperty("version").GetInt32().Should().Be(1);
    }

    [Fact]
    public async Task It_should_carry_the_fixture_status()
    {
        // Act
        var fixture = await CarryFixture();

        // Assert
        fixture.GetProperty("status").GetString().Should().Be("local-regression-only");
    }

    [Fact]
    public async Task It_should_round_trip_the_carried_instant()
    {
        // Arrange
        var instant = (await CarryFixture()).GetProperty("instant").GetString()!;

        // Act
        var parsed = SeamWire.ParseInstant(instant).Should().BeOk().Which;

        // Assert
        SeamWire.Instant(parsed).Should().Be(instant);
    }

    [Fact]
    public async Task It_should_round_trip_the_carried_duration()
    {
        // Arrange
        var duration = (await CarryFixture()).GetProperty("duration").GetString()!;

        // Act
        var parsed = SeamWire.ParseDuration(duration).Should().BeOk().Which;

        // Assert
        parsed.Should().Be(TimeSpan.FromSeconds(90));
        SeamWire.Duration(parsed).Should().Be(duration);
    }

    [Fact]
    public async Task It_should_resolve_the_carried_timezone()
    {
        // Arrange
        var id = (await CarryFixture()).GetProperty("timeZone").GetString()!;

        // Act
        var result = SeamWire.TimeZone(id);

        // Assert
        result.Should().BeOk();
    }

    [Theory]
    [InlineData("text")]
    [InlineData("integer")]
    [InlineData("real")]
    [InlineData("flag")]
    [InlineData("instant")]
    [InlineData("duration")]
    [InlineData("time_zone")]
    public async Task It_should_round_trip_the_carried_attribute_payload(string name)
    {
        // Arrange
        var wire = (await CarryFixture()).GetProperty("attributes").GetProperty(name).GetString()!;
        var kind = SeamWire.ParseAttributeValueKind(name).Should().BeOk().Which;

        // Act
        var value = AttributeValue.FromWire(kind, wire).Should().BeOk().Which;

        // Assert
        value.Wire.Should().Be(wire);
    }

    [Fact]
    public async Task It_should_carry_a_full_attribute_set_through_a_host_backed_sink()
    {
        // Arrange
        await using var writer = new StringWriter();
        var sink = new TextWriterLoggerSink(writer);
        var instant = new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);
        var record = new LogRecord(
            instant,
            LogLevel.Warning,
            "wire",
            SeamContracts.SampleAttributes(instant),
            "boom",
            "at wire");

        // Act
        var result = sink.Emit(record);

        // Assert
        result.Should().BeOk();
        var rendered = writer.ToString();
        rendered.Should().Contain("2026-07-25T22:30:00.0000000Z warning wire");
        rendered.Should().Contain("duration=duration:PT1M30S");
        rendered.Should().Contain("error=boom");
        rendered.Should().Contain("stack=at wire");
    }
}
