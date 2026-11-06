using AtomiCloud.Diene.Results;

namespace AtomiCloud.DotnetBase.App;

public static class Program
{
    public static void Main()
    {
        Samples.RunAll();

        Result<int, string> parsed = Result.Ok<int, string>(21);
        var message = parsed
            .Map(value => value * 2)
            .Match(value => $"Success: {value}", error => $"Failure: {error}");
        Console.WriteLine(message);
    }
}
