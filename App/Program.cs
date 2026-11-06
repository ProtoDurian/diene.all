namespace AtomiCloud.DotnetBase.App;

public static class Program
{
    public static int Main()
    {
        var built = Samples.Sample();
        if (built.IsFailure(out var buildError)) return Reject(buildError);

        var receipt = built.Get();
        var wire = Samples.ToWire(receipt);

        var restored = Samples.FromWire(wire);
        if (restored.IsFailure(out var decodeError)) return Reject(decodeError);

        var telemetry = Samples.Telemetry(receipt);
        if (telemetry.IsFailure(out var attributeError)) return Reject(attributeError);

        var tracking = Samples.Lookup(telemetry.Get(), "TrackingNumber");
        if (tracking.IsFailure(out var lookupError)) return Reject(lookupError);

        var matched = restored.Get() == receipt;
        Console.WriteLine(wire);
        Console.WriteLine($"tracking attribute resolved across spellings: {tracking.Get().Wire}");
        Console.WriteLine($"Success: core-utils round trip {(matched ? "matched" : "drifted")}");
        return matched ? 0 : 1;
    }

    private static int Reject(WireFormatError error)
    {
        Console.Error.WriteLine($"Failure: expected {error.Expected}, received {error.Actual}");
        return 1;
    }

    private static int Reject(KeyError error)
    {
        Console.Error.WriteLine($"Failure: {error.Reason} (offending: {error.Offending})");
        return 1;
    }
}
