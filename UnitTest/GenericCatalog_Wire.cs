using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest;

public class GenericCatalog_Wire
{
    [Fact]
    public void It_should_serialize_entity_references_as_entityType_and_id_only()
    {
        // Arrange
        IDomainProblem[] subjects =
        [
            new EntityNotFound("missing", typeof(string), "one"),
            new EntityNotFound("missing", "Note", "two"),
            new Conflict("taken", typeof(string), "three"),
            new Conflict("taken", "Note", "four"),
        ];

        // Act
        var actual = subjects.Select(Wire).ToArray();

        // Assert
        actual.Should().Equal(
            """{"entityType":"String","id":"one"}""",
            """{"entityType":"Note","id":"two"}""",
            """{"entityType":"String","id":"three"}""",
            """{"entityType":"Note","id":"four"}""");
    }

    [Fact]
    public void It_should_read_entity_references_back_and_refuse_ones_missing_a_required_field()
    {
        // Arrange
        const string complete = """{"entityType":"Note","id":"four"}""";
        const string missingId = """{"entityType":"Note"}""";

        // Act
        var conflict = JsonSerializer.Deserialize<Conflict>(complete, AtomiJson.DefaultOptions)!;
        var notFound = JsonSerializer.Deserialize<EntityNotFound>(complete, AtomiJson.DefaultOptions)!;
        var conflictAct = () => JsonSerializer.Deserialize<Conflict>(missingId, AtomiJson.DefaultOptions);
        var notFoundAct = () => JsonSerializer.Deserialize<EntityNotFound>(missingId, AtomiJson.DefaultOptions);
        var issuesAct = () => JsonSerializer.Deserialize<ValidationError>("{}", AtomiJson.DefaultOptions);

        // Assert
        (conflict.EntityType, conflict.EntityId).Should().Be(("Note", "four"));
        (notFound.EntityType, notFound.EntityId).Should().Be(("Note", "four"));
        conflictAct.Should().Throw<JsonException>();
        notFoundAct.Should().Throw<JsonException>();
        issuesAct.Should().Throw<JsonException>();
    }

    [Fact]
    public void It_should_keep_the_previous_entity_not_found_views_off_the_wire()
    {
        // Arrange
        var fromType = new EntityNotFound("missing", typeof(string), "one");
        var fromName = new EntityNotFound("missing", "Note", "two");

        // Act
        var typed = (fromType.EntityType, fromType.EntityId, fromType.RequestIdentifier, fromType.TypeName, fromType.AssemblyQualifiedName);
        var named = (fromName.EntityType, fromName.EntityId, fromName.RequestIdentifier, fromName.TypeName, fromName.AssemblyQualifiedName);

        // Assert
        typed.Should().Be(("String", "one", "one", typeof(string).FullName!, typeof(string).AssemblyQualifiedName!));
        named.Should().Be(("Note", "two", "two", "Note", string.Empty));
    }

    [Fact]
    public void It_should_describe_conflict_as_the_generic_409_problem()
    {
        // Arrange
        var subject = new Conflict();

        // Act
        var metadata = (subject.Id, subject.Title, subject.Detail, subject.Version, subject.EntityType, subject.EntityId);

        // Assert
        metadata.Should().Be(("conflict", "Conflict", string.Empty, "v1", string.Empty, string.Empty));
    }

    [Fact]
    public void It_should_map_dotted_field_errors_to_issue_paths()
    {
        // Arrange
        var errors = new Dictionary<string, string[]>
        {
            ["name"] = ["required", "too short"],
            ["address.city"] = ["unknown"],
            [""] = ["empty body"],
        };

        // Act
        var subject = new ValidationError("invalid", errors);

        // Assert
        Wire(subject).Should().Be(
            """{"issues":[{"path":["name"],"message":"required"},{"path":["name"],"message":"too short"},""" +
            """{"path":["address","city"],"message":"unknown"},{"path":[],"message":"empty body"}]}""");
        subject.Errors.Should().ContainKey("address.city").WhoseValue.Should().Equal("unknown");
    }

    [Fact]
    public void It_should_build_issues_with_optional_codes_and_group_them_for_the_previous_view()
    {
        // Arrange
        ValidationIssue[] issues =
        [
            new(["address", "city"], "unknown", "enum"),
            new(["address", "city"], "blank"),
            new([], "empty body"),
        ];

        // Act
        var subject = new ValidationError("invalid", issues);

        // Assert
        Wire(subject).Should().Be(
            """{"issues":[{"path":["address","city"],"message":"unknown","code":"enum"},""" +
            """{"path":["address","city"],"message":"blank"},{"path":[],"message":"empty body"}]}""");
        subject.Errors.Keys.Should().Equal("address.city", string.Empty);
        subject.Errors["address.city"].Should().Equal("unknown", "blank");
        subject.Issues[0].Code.Should().Be("enum");
        subject.Issues[1].Code.Should().BeNull();
    }

    [Fact]
    public void It_should_serialize_data_less_problems_to_an_empty_object()
    {
        // Arrange
        IDomainProblem[] subjects =
        [
            new Unauthenticated("sign in"),
            new Unauthorized("forbidden", ["notes:read"], ["notes:write"]),
            new InvalidJson("invalid", "{"),
        ];

        // Act
        var actual = subjects.Select(Wire).ToArray();

        // Assert
        actual.Should().OnlyContain(json => json == "{}");
        ((Unauthorized)subjects[1]).Granted.Should().Equal("notes:read");
        ((InvalidJson)subjects[2]).InvalidString.Should().Be("{");
    }

    [Fact]
    public void It_should_reject_null_constructor_arguments()
    {
        // Arrange
        ValidationIssue[] none = [];
        ValidationIssue[] withNull = [null!];

        // Act
        var conflictType = () => new Conflict("detail", (Type)null!, "id");
        var conflictDetail = () => new Conflict(null!, "Note", "id");
        var conflictEntity = () => new Conflict("detail", (string)null!, "id");
        var conflictId = () => new Conflict("detail", "Note", null!);
        var notFoundDetail = () => new EntityNotFound(null!, "Note", "id");
        var notFoundEntity = () => new EntityNotFound("detail", (string)null!, "id");
        var notFoundId = () => new EntityNotFound("detail", "Note", null!);
        var issuePath = () => new ValidationIssue(null!, "message");
        var issueMessage = () => new ValidationIssue([], null!);
        var issuesDetail = () => new ValidationError(null!, none);
        var issuesNull = () => new ValidationError("detail", (IEnumerable<ValidationIssue>)null!);
        var issuesElement = () => new ValidationError("detail", withNull);

        // Assert
        conflictType.Should().Throw<ArgumentNullException>();
        conflictDetail.Should().Throw<ArgumentNullException>();
        conflictEntity.Should().Throw<ArgumentNullException>();
        conflictId.Should().Throw<ArgumentNullException>();
        notFoundDetail.Should().Throw<ArgumentNullException>();
        notFoundEntity.Should().Throw<ArgumentNullException>();
        notFoundId.Should().Throw<ArgumentNullException>();
        issuePath.Should().Throw<ArgumentNullException>();
        issueMessage.Should().Throw<ArgumentNullException>();
        issuesDetail.Should().Throw<ArgumentNullException>();
        issuesNull.Should().Throw<ArgumentNullException>();
        issuesElement.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_omit_absent_envelope_data_instead_of_writing_null()
    {
        // Arrange
        var subject = new Problem { Type = "about:blank", Title = "Unauthenticated", Status = 401 };

        // Act
        var json = JsonSerializer.Serialize(subject, AtomiJson.DefaultOptions);

        // Assert
        JsonNode.Parse(json)!.AsObject().Should().NotContainKey("data");
    }

    private static string Wire(IDomainProblem problem) =>
        JsonSerializer.Serialize(problem, problem.GetType(), AtomiJson.DefaultOptions);
}
