namespace AtomiCloud.Diene.Note;

public interface INoteSummariser
{
    string Summarise(NoteRecord record, int maxLength);
}
