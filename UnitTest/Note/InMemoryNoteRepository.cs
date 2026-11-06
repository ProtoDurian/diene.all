using AtomiCloud.Diene.Note;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

internal sealed class InMemoryNoteRepository : INoteRepository
{
    private readonly Dictionary<string, NotePrincipal> _notes = [];

    public Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default)
    {
        var principal = new NotePrincipal { Id = $"note-{_notes.Count + 1}", Record = record };
        _notes[principal.Id] = principal;
        return Task.FromResult(principal);
    }

    public Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default) =>
        Task.FromResult(_notes.GetValueOrDefault(id));
}
