# Utilities in C#/.NET

LINQ (`System.Linq`) is the primary utility library. Use it for collection work
before writing a helper.

```csharp
var openByOwner = notes
    .Where(note => note.IsOpen)
    .OrderBy(note => note.CreatedAt)
    .GroupBy(note => note.OwnerId)
    .ToDictionary(group => group.Key, group => group.ToList());

var batches = ids.Distinct().Chunk(100);
```

Prefer a small injectable object when behavior has policy, configuration, IO, or
nondeterminism. Use extension methods only for pure, obvious transformations that
do not hide dependencies.

```csharp
public static class StringExtensions
{
    public static string CollapseWhitespace(this string value) =>
        string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
}
```

Keep utility APIs typed and narrow. Do not add catch-all `Helpers`, `Utils`, or
global service-locator classes. Shared capabilities graduate into a dedicated
`AtomiCloud.Diene.*` library before they are copied across applications.
