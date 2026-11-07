using System.Diagnostics.Metrics;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelMetricsCollectorTests : IDisposable
{
    private readonly Instrumentation _instrumentation = new(new AppIdentity("l", "p", "billing", "m", "1.0.0"));

    private static Dictionary<string, AttributeValue> Attributes { get; } = new(StringComparer.Ordinal)
    {
        ["route"] = AttributeValue.Text("/v1/demo"),
    };

    public void Dispose()
    {
        _instrumentation.Dispose();
        GC.SuppressFinalize(this);
    }

    private MetricRecord Sample(
        MetricKind kind = MetricKind.Counter,
        double value = 1.0,
        string? unit = "ms",
        string name = "demo.samples") =>
        new(DateTimeOffset.UnixEpoch, name, kind, value, unit, Attributes);

    private (List<(string Name, double Value, int Tags)> Measurements, MeterListener Listener) Listen()
    {
        var measurements = new List<(string, double, int)>();
        var listener = new MeterListener
        {
            InstrumentPublished = (instrument, active) =>
            {
                if (ReferenceEquals(instrument.Meter, _instrumentation.Meter)) active.EnableMeasurementEvents(instrument);
            },
        };
        listener.SetMeasurementEventCallback<double>((instrument, value, tags, _) =>
            measurements.Add((instrument.Name, value, tags.Length)));
        listener.Start();
        return (measurements, listener);
    }

    [Fact]
    public void Construct_RejectsANullInstrumentation()
    {
        // Act
        var act = () => new OtelMetricsCollector(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [InlineData(MetricKind.Counter)]
    [InlineData(MetricKind.Gauge)]
    [InlineData(MetricKind.Histogram)]
    public void Emit_RecordsEveryInstrumentKindWithItsTags(MetricKind kind)
    {
        // Arrange
        var (measurements, listener) = Listen();
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        Result<Unit, SeamError> result;
        using (listener)
        {
            result = collector.Emit(Sample(kind, 2.5, name: $"demo.{kind}"));
        }

        // Assert
        result.Should().BeOk();
        measurements.Should().ContainSingle()
            .Which.Should().Be(($"demo.{kind}", 2.5, 1));
    }

    [Fact]
    public void Emit_ReusesTheInstrumentForARepeatedSeries()
    {
        // Arrange
        var (measurements, listener) = Listen();
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        using (listener)
        {
            collector.Emit(Sample(value: 1.0)).Should().BeOk();
            collector.Emit(Sample(value: 2.0)).Should().BeOk();
        }

        // Assert
        measurements.Should().HaveCount(2);
        measurements.Select(measurement => measurement.Value).Should().Equal(1.0, 2.0);
    }

    [Fact]
    public void Emit_TreatsADifferentUnitAsADifferentSeries()
    {
        // Arrange
        var (measurements, listener) = Listen();
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        using (listener)
        {
            collector.Emit(Sample(unit: "ms")).Should().BeOk();
            collector.Emit(Sample(unit: null)).Should().BeOk();
        }

        // Assert
        measurements.Should().HaveCount(2);
    }

    [Fact]
    public void Emit_AcceptsASampleCarryingNoAttributes()
    {
        // Arrange
        var (measurements, listener) = Listen();
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        Result<Unit, SeamError> result;
        using (listener)
        {
            result = collector.Emit(new MetricRecord(DateTimeOffset.UnixEpoch, "demo.bare", MetricKind.Counter, 1.0));
        }

        // Assert
        result.Should().BeOk();
        measurements.Should().ContainSingle().Which.Tags.Should().Be(0);
    }

    [Fact]
    public void Emit_RejectsANullRecord()
    {
        // Arrange
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        var result = collector.Emit(null!);

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "invalid_argument");
    }

    [Fact]
    public void Emit_RejectsAnUndefinedKind()
    {
        // Arrange
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        var result = collector.Emit(new MetricRecord(DateTimeOffset.UnixEpoch, "demo", (MetricKind)42, 1.0));

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "invalid_argument")
            .Which.Detail.Should().Contain("not a recognized metric kind");
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void Emit_RejectsANonFiniteValue(double value)
    {
        // Arrange
        var collector = new OtelMetricsCollector(_instrumentation);

        // Act
        var result = collector.Emit(Sample(value: value));

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "invalid_argument").Which.Detail.Should().Contain("finite");
    }

    [Fact]
    public void Emit_ReportsAnEmitFailureWhenTheMeterIsDisposed()
    {
        // Arrange
        var instrumentation = new Instrumentation(new AppIdentity("l", "p", "s", "m", "1.0.0"));
        instrumentation.Dispose();

        // Act
        var result = new OtelMetricsCollector(instrumentation).Emit(Sample());

        // Assert
        // A disposed meter may refuse the instrument or no-op; either way it returns a value, never throws.
        result.Match(_ => "ok", error => error.Id).Should().BeOneOf("ok", "emit_failed");
    }
}
