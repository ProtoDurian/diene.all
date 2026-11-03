# Testing in C#/.NET

Use xUnit v3 with FluentAssertions 7.x. Test classes describe the subject and
operation; methods begin with `It_should_`. Every test keeps Arrange, Act and
Assert as blank-line-separated blocks, without marker comments.

```csharp
public class NoteSummariser_Summarise
{
    [Fact]
    public void It_should_return_a_single_line_preview()
    {
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "Hello", Body = "world" };

        var actual = subject.Summarise(input, 80);

        actual.Should().Be("Hello — world");
    }
}
```

Use `TheoryData<>` plus `[ClassData]`; never use `[InlineData]`. Write manual fakes
for domain ports instead of mock-framework expectations. Unit tests cover every
`Lib*` assembly at 100%. Integration tests cover every `App*` assembly at 80%
against real dependencies through Testcontainers. Test infrastructure does not
enter either ledger.
