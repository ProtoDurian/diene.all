namespace AtomiCloud.Diene.Note;

public interface INoteRepository
{
    Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default);

    Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default);
}
