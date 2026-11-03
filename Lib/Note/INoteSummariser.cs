namespace AtomiCloud.DotnetBase.Lib.Note;

public interface INoteSummariser
{
    string Summarise(NoteRecord record, int maxLength);
}
