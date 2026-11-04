using AtomiCloud.DotnetBase.Lib.Note;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class NoteService_Preview
{
    [Fact]
    public async Task It_should_preview_a_created_note()
    {
        // Arrange
        var subject = new NoteService(new InMemoryNoteRepository(), new NoteSummariser());
        var saved = await subject.Create(
            new NoteRecord { Title = "Hello", Body = "world" },
            TestContext.Current.CancellationToken);

        // Act
        var actual = await subject.Preview(saved.Id, TestContext.Current.CancellationToken);

        // Assert
        actual.Should().Be("Hello — world");
    }

    [Fact]
    public async Task It_should_return_null_for_an_unknown_note()
    {
        // Arrange
        var subject = new NoteService(new InMemoryNoteRepository(), new NoteSummariser());

        // Act
        var actual = await subject.Preview("missing", TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeNull();
    }
}
