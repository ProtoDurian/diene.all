using AtomiCloud.DotnetBase.Lib.Note;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class NotePrincipal_Construct
{
    [Fact]
    public void It_should_pair_a_stable_identity_with_its_record()
    {
        var record = new NoteRecord { Title = "Title", Body = "Body" };

        var actual = new NotePrincipal { Id = "note-1", Record = record };

        actual.Id.Should().Be("note-1");
        actual.Record.Should().BeSameAs(record);
    }

    [Fact]
    public void It_should_compare_by_value()
    {
        var record = new NoteRecord { Title = "Title", Body = "Body" };
        var subject = new NotePrincipal { Id = "note-1", Record = record };

        var twin = new NotePrincipal { Id = "note-1", Record = new NoteRecord { Title = "Title", Body = "Body" } };

        subject.Should().Be(twin);
    }
}
