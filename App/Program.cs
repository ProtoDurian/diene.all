using AtomiCloud.DotnetBase.App.Adapters.Redis;
using AtomiCloud.DotnetBase.Lib.Note;
using StackExchange.Redis;

namespace AtomiCloud.DotnetBase.App;

public static class Program
{
    public static async Task Main()
    {
        var connectionString = Environment.GetEnvironmentVariable("REDIS_CONNECTION");
        if (string.IsNullOrWhiteSpace(connectionString)) connectionString = "localhost:6379";

        await using var redis = await ConnectionMultiplexer.ConnectAsync(connectionString);
        var notes = new NoteService(new RedisNoteRepository(redis), new NoteSummariser());

        var saved = await notes.Create(new NoteRecord
        {
            Title = "Welcome",
            Body = "The first note stored through the Redis adapter.",
        });
        var preview = await notes.Preview(saved.Id);

        Console.WriteLine(preview ?? $"Note {saved.Id} could not be read back.");
    }
}
