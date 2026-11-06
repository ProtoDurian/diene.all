namespace AtomiCloud.Diene.Note;

public class NoteService(INoteRepository notes, INoteSummariser summariser)
{
    private const int PreviewLength = 80;

    public Task<NotePrincipal> Create(NoteRecord record, CancellationToken cancellationToken = default) =>
        notes.Save(record, cancellationToken);

    public async Task<string?> Preview(string id, CancellationToken cancellationToken = default)
    {
        var note = await notes.Find(id, cancellationToken);
        return note is null ? null : summariser.Summarise(note.Record, PreviewLength);
    }
}
