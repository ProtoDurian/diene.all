# Validation in C#/.NET

FluentValidation is the default validator. Pin it through Central Package
Management (`Directory.Packages.props`). Validate at the boundary, then pass typed
values into domain behavior.

```csharp
public sealed record CreateNote
{
    public required string Title { get; init; }
    public required string Body { get; init; }
}

public sealed class CreateNoteValidator : AbstractValidator<CreateNote>
{
    public CreateNoteValidator()
    {
        RuleFor(note => note.Title).NotEmpty().MaximumLength(200);
        RuleFor(note => note.Body).NotEmpty();
    }
}
```

Turn failures into an RFC 9457 Problem with the
[wire format](../../wire-format/languages/csharp.md). Do not return ad hoc
dictionaries or throw expected validation failures across a public boundary.

```csharp
var result = validator.Validate(command);
if (!result.IsValid)
{
    return TypedResults.Problem(
        type: "https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/validation_error",
        title: "The request is invalid",
        statusCode: 400,
        extensions: new Dictionary<string, object?>
        {
            ["errors"] = result.Errors
                .GroupBy(error => JsonNamingPolicy.CamelCase.ConvertName(error.PropertyName))
                .ToDictionary(group => group.Key, group => group.Select(error => error.ErrorMessage).ToArray()),
        });
}
```

Use native guard APIs such as `ArgumentException.ThrowIfNullOrWhiteSpace` only for
programmer errors inside a layer, not for user input.
