using System.Collections.Concurrent;
using System.Diagnostics.Metrics;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The OpenTelemetry implementation of the metrics seam. Instruments are created
/// once per (name, kind, unit) and cached, because
/// <see cref="System.Diagnostics.Metrics.Meter" /> treats a second instrument of
/// the same name as a duplicate series. A gauge is recorded synchronously rather
/// than through an observable callback: the seam hands over a sample that was
/// already observed, so there is nothing left to poll.
/// </summary>
/// <param name="instrumentation">The app-scoped meter to create instruments on.</param>
public sealed class OtelMetricsCollector(Instrumentation instrumentation) : IMetricsCollector
{
    private readonly ConcurrentDictionary<string, object> _instruments = new(StringComparer.Ordinal);

    private readonly Instrumentation _instrumentation =
        instrumentation ?? throw new ArgumentNullException(nameof(instrumentation));

    /// <inheritdoc />
    public Result<Unit, SeamError> Emit(MetricRecord record)
    {
        if (record is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Metrics, nameof(record), "The record must not be null.");
        }

        // InvalidWire is logging-only, so an unknown kind is an invalid argument here.
        if (!Enum.IsDefined(record.Kind))
        {
            return SeamErrors.InvalidArgument(
                SeamKind.Metrics,
                nameof(record.Kind),
                $"'{record.Kind}' is not a recognized metric kind.");
        }

        if (!double.IsFinite(record.Value))
        {
            return SeamErrors.InvalidArgument(
                SeamKind.Metrics,
                nameof(record.Value),
                "A metric value must be finite; no exporter can represent NaN or infinity.");
        }

        // No catch: inputs are validated and BCL instruments never throw (even when disposed).
        var tags = Tags(record);
        switch (record.Kind)
        {
            case MetricKind.Counter:
                Instrument<Counter<double>>(record, unit => _instrumentation.Meter
                        .CreateCounter<double>(record.Name, unit))
                    .Add(record.Value, tags);
                break;
            case MetricKind.Gauge:
                Instrument<Gauge<double>>(record, unit => _instrumentation.Meter
                        .CreateGauge<double>(record.Name, unit))
                    .Record(record.Value, tags);
                break;
            default:
                Instrument<Histogram<double>>(record, unit => _instrumentation.Meter
                        .CreateHistogram<double>(record.Name, unit))
                    .Record(record.Value, tags);
                break;
        }

        return Result.Ok<Unit, SeamError>(default);
    }

    /// <summary>The instrument tags a sample carries, in its canonical wire form.</summary>
    private static KeyValuePair<string, object?>[] Tags(MetricRecord record) =>
        [.. record.Attributes.Select(attribute =>
            new KeyValuePair<string, object?>(attribute.Key, attribute.Value.Wire))];

    private TInstrument Instrument<TInstrument>(MetricRecord record, Func<string?, TInstrument> create)
        where TInstrument : class
    {
        var unit = record.Unit.ToNullable();
        var key = $"{typeof(TInstrument).Name}/{record.Name}/{unit}";
        return (TInstrument)_instruments.GetOrAdd(key, _ => create(unit));
    }
}
