namespace AtomiCloud.DotnetBase.UnitTest;

public class SeamErrorTests
{
    private static SeamError Sample() =>
        new(SeamKind.Vfs, "not_found", "Entry not found", "No entry exists at '/tmp/x'.");

    [Fact]
    public void It_should_expose_every_component()
    {
        // Act
        var error = new SeamError(SeamKind.Terminal, "launch_failed", "Launch", "boom", [new("executable", "nope")]);

        // Assert
        error.Seam.Should().Be(SeamKind.Terminal);
        error.Id.Should().Be("launch_failed");
        error.Title.Should().Be("Launch");
        error.Detail.Should().Be("boom");
        error.Data.Should().ContainKey("executable").WhoseValue.Should().Be("nope");
    }

    [Fact]
    public void It_should_default_to_empty_context()
    {
        // Act
        var error = Sample();

        // Assert
        error.Data.Should().BeEmpty();
    }

    [Fact]
    public void It_should_add_context_without_mutating_the_original()
    {
        // Arrange
        var error = Sample();

        // Act
        var enriched = error.With("path", "/tmp/x");

        // Assert
        enriched.Data.Should().ContainKey("path");
        error.Data.Should().BeEmpty();
    }

    [Fact]
    public void It_should_replace_an_existing_context_entry()
    {
        // Arrange
        var error = Sample().With("path", "/a");

        // Act
        var replaced = error.With("path", "/b");

        // Assert
        replaced.Data["path"].Should().Be("/b");
    }

    [Fact]
    public void It_should_reject_a_blank_id()
    {
        // Act
        var act = () => new SeamError(SeamKind.Vfs, "  ", "Title", "Detail");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_null_title()
    {
        // Act
        var act = () => new SeamError(SeamKind.Vfs, "id", null!, "Detail");

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_detail()
    {
        // Act
        var act = () => new SeamError(SeamKind.Vfs, "id", "Title", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_blank_context_key()
    {
        // Arrange
        var error = Sample();

        // Act
        var act = () => error.With("  ", "value");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_null_context_value()
    {
        // Arrange
        var error = Sample();

        // Act
        var act = () => error.With("key", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_equal_an_error_with_the_same_components()
    {
        // Arrange
        var left = Sample().With("path", "/tmp/x");
        var right = Sample().With("path", "/tmp/x");

        // Act
        var equal = left.Equals(right);

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_equal_a_boxed_error_with_the_same_components()
    {
        // Arrange
        var left = Sample().With("path", "/tmp/x");
        object right = Sample().With("path", "/tmp/x");

        // Act
        var equal = left.Equals(right);

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_compare_equal_errors_with_the_equality_operator()
    {
        // Arrange
        var left = Sample().With("path", "/tmp/x");
        var right = Sample().With("path", "/tmp/x");

        // Act
        var equal = left == right;

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_compare_equal_errors_with_the_inequality_operator()
    {
        // Arrange
        var left = Sample().With("path", "/tmp/x");
        var right = Sample().With("path", "/tmp/x");

        // Act
        var unequal = left != right;

        // Assert
        unequal.Should().BeFalse();
    }

    [Fact]
    public void It_should_share_a_hash_code_with_an_equal_error()
    {
        // Arrange
        var left = Sample().With("path", "/tmp/x");
        var right = Sample().With("path", "/tmp/x");

        // Act
        var hash = left.GetHashCode();

        // Assert
        hash.Should().Be(right.GetHashCode());
    }

    [Theory]
    [InlineData(SeamKind.System, "not_found", "Entry not found", "No entry exists at '/tmp/x'.")]
    [InlineData(SeamKind.Vfs, "other", "Entry not found", "No entry exists at '/tmp/x'.")]
    [InlineData(SeamKind.Vfs, "not_found", "Other", "No entry exists at '/tmp/x'.")]
    [InlineData(SeamKind.Vfs, "not_found", "Entry not found", "Other")]
    public void It_should_differ_on_any_component(SeamKind seam, string id, string title, string detail)
    {
        // Arrange
        var other = new SeamError(seam, id, title, detail);

        // Act
        var equal = Sample().Equals(other);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_differ_on_a_context_value()
    {
        // Arrange
        var left = Sample().With("path", "/a");
        var right = Sample().With("path", "/b");

        // Act
        var equal = left.Equals(right);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_differ_on_a_missing_context_entry()
    {
        // Arrange
        var left = Sample().With("path", "/a");
        var right = Sample();

        // Act
        var equal = left.Equals(right);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_not_equal_null()
    {
        // Arrange
        var error = Sample();

        // Act
        var equal = error.Equals(null);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_not_equal_another_type()
    {
        // Arrange
        var error = Sample();

        // Act
        var equal = Equals(error, "text");

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_not_equal_a_null_object()
    {
        // Arrange
        var error = Sample();

        // Act
        var equal = Equals(error, null);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_not_compare_equal_to_a_null_right_operand()
    {
        // Arrange
        var error = Sample();
        SeamError? absent = null;

        // Act
        var equal = error == absent;

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_not_compare_equal_to_a_null_left_operand()
    {
        // Arrange
        var error = Sample();
        SeamError? absent = null;

        // Act
        var equal = absent == error;

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_compare_two_null_operands_as_equal()
    {
        // Arrange
        SeamError? absent = null;

        // Act
        var equal = absent == null;

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_render_seam_id_and_detail()
    {
        // Arrange
        var error = Sample();

        // Act
        var rendered = error.ToString();

        // Assert
        rendered.Should().Be("vfs/not_found: No entry exists at '/tmp/x'.");
    }

    [Fact]
    public void It_should_publish_one_canonical_catalog_entry_per_failure_mode()
    {
        // Act
        SeamError[] catalog =
        [
            SeamErrors.InvalidArgument(SeamKind.System, "name", "blank"),
            SeamErrors.NotFound("/tmp/a"),
            SeamErrors.AlreadyExists("/tmp/a"),
            SeamErrors.NotADirectory("/tmp/a"),
            SeamErrors.DirectoryNotEmpty("/tmp/a"),
            SeamErrors.IoFailure(SeamKind.Vfs, "read", "disk"),
            SeamErrors.EnvironmentUnavailable("HOME", "denied"),
            SeamErrors.LaunchFailed("nope", "missing"),
            SeamErrors.EmitFailed(SeamKind.Metrics, "closed"),
            SeamErrors.Cancelled(SeamKind.Terminal, "run"),
            SeamErrors.InvalidWire("instant", "nope"),
            SeamErrors.UnknownTimeZone("Mars/Olympus", "unknown"),
        ];

        // Assert
        catalog.Select(error => error.Id).Should().OnlyHaveUniqueItems();
        catalog.Should().AllSatisfy(error => error.Detail.Should().NotBeNullOrWhiteSpace());
    }

    [Theory]
    [InlineData("invalid_argument", SeamKind.System)]
    [InlineData("not_found", SeamKind.Vfs)]
    [InlineData("launch_failed", SeamKind.Terminal)]
    [InlineData("emit_failed", SeamKind.Metrics)]
    public void It_should_bind_each_catalog_entry_to_its_seam(string id, SeamKind seam)
    {
        // Arrange
        SeamError[] catalog =
        [
            SeamErrors.InvalidArgument(SeamKind.System, "name", "blank"),
            SeamErrors.NotFound("/tmp/a"),
            SeamErrors.LaunchFailed("nope", "missing"),
            SeamErrors.EmitFailed(SeamKind.Metrics, "closed"),
        ];

        // Act
        var entry = catalog.Single(error => error.Id == id);

        // Assert
        entry.Seam.Should().Be(seam);
    }

    [Fact]
    public void It_should_carry_the_argument_on_an_invalid_argument_error()
    {
        // Act
        var error = SeamErrors.InvalidArgument(SeamKind.System, "name", "blank");

        // Assert
        error.Data["argument"].Should().Be("name");
    }

    [Fact]
    public void It_should_carry_the_path_on_a_not_found_error()
    {
        // Act
        var error = SeamErrors.NotFound("/tmp/a");

        // Assert
        error.Data["path"].Should().Be("/tmp/a");
    }

    [Fact]
    public void It_should_carry_the_path_on_an_already_exists_error()
    {
        // Act
        var error = SeamErrors.AlreadyExists("/tmp/a");

        // Assert
        error.Data["path"].Should().Be("/tmp/a");
    }

    [Fact]
    public void It_should_carry_the_path_on_a_not_a_directory_error()
    {
        // Act
        var error = SeamErrors.NotADirectory("/tmp/a");

        // Assert
        error.Data["path"].Should().Be("/tmp/a");
    }

    [Fact]
    public void It_should_carry_the_path_on_a_directory_not_empty_error()
    {
        // Act
        var error = SeamErrors.DirectoryNotEmpty("/tmp/a");

        // Assert
        error.Data["path"].Should().Be("/tmp/a");
    }

    [Fact]
    public void It_should_carry_the_operation_on_an_io_failure()
    {
        // Act
        var error = SeamErrors.IoFailure(SeamKind.Vfs, "read", "disk");

        // Assert
        error.Data["operation"].Should().Be("read");
    }

    [Fact]
    public void It_should_carry_the_variable_on_an_environment_unavailable_error()
    {
        // Act
        var error = SeamErrors.EnvironmentUnavailable("HOME", "denied");

        // Assert
        error.Data["variable"].Should().Be("HOME");
    }

    [Fact]
    public void It_should_carry_the_executable_on_a_launch_failure()
    {
        // Act
        var error = SeamErrors.LaunchFailed("nope", "missing");

        // Assert
        error.Data["executable"].Should().Be("nope");
    }

    [Fact]
    public void It_should_carry_no_context_on_an_emit_failure()
    {
        // Act
        var error = SeamErrors.EmitFailed(SeamKind.Metrics, "closed");

        // Assert
        error.Data.Should().BeEmpty();
    }

    [Fact]
    public void It_should_carry_the_operation_on_a_cancellation()
    {
        // Act
        var error = SeamErrors.Cancelled(SeamKind.Terminal, "run");

        // Assert
        error.Data["operation"].Should().Be("run");
    }

    [Fact]
    public void It_should_carry_the_field_on_an_invalid_wire_error()
    {
        // Act
        var error = SeamErrors.InvalidWire("instant", "nope");

        // Assert
        error.Data["field"].Should().Be("instant");
    }

    [Fact]
    public void It_should_carry_the_timezone_on_an_unknown_timezone_error()
    {
        // Act
        var error = SeamErrors.UnknownTimeZone("Mars/Olympus", "unknown");

        // Assert
        error.Data["timeZone"].Should().Be("Mars/Olympus");
    }
}
