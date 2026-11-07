namespace AtomiCloud.DotnetBase.UnitTest;

internal static class Env
{
    public static IReadOnlyDictionary<string, string?> None { get; } =
        new Dictionary<string, string?>(StringComparer.Ordinal);

    public static IReadOnlyDictionary<string, string?> Of(params (string Name, string? Value)[] entries)
    {
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var (name, value) in entries) environment[name] = value;
        return environment;
    }
}
