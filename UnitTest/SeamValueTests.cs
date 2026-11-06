namespace AtomiCloud.DotnetBase.UnitTest;

public class SeamValueTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_normalize_a_log_record_timestamp_to_utc()
    {
        // Arrange
        var local = new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8));

        // Act
        var record = new LogRecord(local, LogLevel.Info, "m");

        // Assert
        record.Timestamp.Should().Be(Anchor);
        record.Timestamp.Offset.Should().Be(TimeSpan.Zero);
    }

    [Fact]
    public void It_should_default_log_optionals_to_none()
    {
        // Act
        var record = new LogRecord(Anchor, LogLevel.Debug, "message");

        // Assert
        record.Level.Should().Be(LogLevel.Debug);
        record.Message.Should().Be("message");
        record.Attributes.Should().BeEmpty();
        record.Error.IsNone().Should().BeTrue();
        record.StackTrace.IsNone().Should().BeTrue();
    }

    [Fact]
    public void It_should_carry_log_optionals_when_supplied()
    {
        // Act
        var record = new LogRecord(
            Anchor,
            LogLevel.Error,
            "message",
            [new("key", AttributeValue.Text("value"))],
            "boom",
            "at frame");

        // Assert
        record.Attributes["key"].Should().Be(AttributeValue.Text("value"));
        record.Error.Should().BeSome("boom");
        record.StackTrace.Should().BeSome("at frame");
    }

    [Fact]
    public void It_should_reject_a_null_log_message()
    {
        // Act
        var act = () => new LogRecord(Anchor, LogLevel.Info, null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_render_a_log_record_on_the_wire()
    {
        // Arrange
        var record = new LogRecord(Anchor, LogLevel.Warning, "careful");

        // Act
        var rendered = record.ToString();

        // Assert
        rendered.Should().Be("2026-07-25T22:30:00.0000000Z warning careful");
    }

    [Fact]
    public void It_should_normalize_a_metric_timestamp_and_default_its_unit()
    {
        // Arrange
        var local = new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8));

        // Act
        var record = new MetricRecord(local, "app.count", MetricKind.Counter, 1);

        // Assert
        record.Timestamp.Should().Be(Anchor);
        record.Name.Should().Be("app.count");
        record.Kind.Should().Be(MetricKind.Counter);
        record.Value.Should().Be(1);
        record.Unit.IsNone().Should().BeTrue();
        record.Attributes.Should().BeEmpty();
    }

    [Fact]
    public void It_should_carry_metric_optionals_when_supplied()
    {
        // Act
        var record = new MetricRecord(
            Anchor,
            "app.latency",
            MetricKind.Histogram,
            12.5,
            "ms",
            [new("key", AttributeValue.Text("value"))]);

        // Assert
        record.Unit.Should().BeSome("ms");
        record.Attributes.Should().ContainKey("key");
    }

    [Fact]
    public void It_should_reject_a_blank_metric_name()
    {
        // Act
        var act = () => new MetricRecord(Anchor, "  ", MetricKind.Gauge, 1);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_render_a_metric_record_on_the_wire()
    {
        // Arrange
        var record = new MetricRecord(Anchor, "app.latency", MetricKind.Histogram, 12.5);

        // Act
        var rendered = record.ToString();

        // Assert
        rendered.Should().Be("2026-07-25T22:30:00.0000000Z histogram app.latency=12.5");
    }

    [Fact]
    public void It_should_snapshot_a_vfs_entry()
    {
        // Act
        var entry = new VfsEntry("/tmp/a.txt", VfsEntryType.File, 5, Anchor);

        // Assert
        entry.Path.Should().Be("/tmp/a.txt");
        entry.Type.Should().Be(VfsEntryType.File);
        entry.Size.Should().Be(5);
        entry.ModifiedAt.Should().BeSome(Anchor);
    }

    [Fact]
    public void It_should_render_a_vfs_entry()
    {
        // Arrange
        var entry = new VfsEntry("/tmp/a.txt", VfsEntryType.File, 5, Anchor);

        // Act
        var rendered = entry.ToString();

        // Assert
        rendered.Should().Be("file /tmp/a.txt (5)");
    }

    [Fact]
    public void It_should_leave_an_absent_modification_time_as_none()
    {
        // Act
        var entry = new VfsEntry("/tmp", VfsEntryType.Directory, 0);

        // Assert
        entry.ModifiedAt.IsNone().Should().BeTrue();
    }

    [Fact]
    public void It_should_normalize_an_entry_modification_time_to_utc()
    {
        // Arrange
        var local = new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8));

        // Act
        var entry = new VfsEntry("/tmp/a", VfsEntryType.Link, 0, local);

        // Assert
        entry.ModifiedAt.Should().BeSome(Anchor);
    }

    [Fact]
    public void It_should_reject_a_null_entry_path()
    {
        // Act
        var act = () => new VfsEntry(null!, VfsEntryType.File, 0);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_default_write_options_to_not_creating_parents()
    {
        // Act
        var options = default(VfsWriteOptions);

        // Assert
        options.CreateParents.Should().BeFalse();
    }

    [Fact]
    public void It_should_default_list_options_to_non_recursive()
    {
        // Act
        var options = default(VfsListOptions);

        // Assert
        options.Recursive.Should().BeFalse();
    }

    [Fact]
    public void It_should_default_directory_options_to_non_recursive()
    {
        // Act
        var options = default(VfsDirectoryOptions);

        // Assert
        options.Recursive.Should().BeFalse();
    }

    [Fact]
    public void It_should_carry_a_supplied_create_parents_flag()
    {
        // Act
        var options = new VfsWriteOptions(true);

        // Assert
        options.CreateParents.Should().BeTrue();
    }

    [Fact]
    public void It_should_carry_a_supplied_recursive_list_flag()
    {
        // Act
        var options = new VfsListOptions(true);

        // Assert
        options.Recursive.Should().BeTrue();
    }

    [Fact]
    public void It_should_carry_a_supplied_recursive_directory_flag()
    {
        // Act
        var options = new VfsDirectoryOptions(true);

        // Assert
        options.Recursive.Should().BeTrue();
    }

    [Fact]
    public void It_should_snapshot_a_terminal_command()
    {
        // Arrange
        var args = new List<string> { "hello" };
        var environment = new Dictionary<string, string>(StringComparer.Ordinal) { ["DIENE"] = "1" };
        var command = new TerminalCommand("echo", args, "/tmp", environment, false, true);

        // Act
        args.Add("mutated");
        environment["DIENE"] = "2";

        // Assert
        command.Executable.Should().Be("echo");
        command.Args.Should().ContainSingle().Which.Should().Be("hello");
        command.WorkingDirectory.Should().BeSome("/tmp");
        command.Environment["DIENE"].Should().Be("1");
        command.IncludeParentEnvironment.Should().BeFalse();
        command.RunInShell.Should().BeTrue();
    }

    [Fact]
    public void It_should_render_a_terminal_command_with_its_args()
    {
        // Arrange
        var command = new TerminalCommand("echo", ["hello"]);

        // Act
        var rendered = command.ToString();

        // Assert
        rendered.Should().Be("echo hello");
    }

    [Fact]
    public void It_should_default_a_terminal_command_to_an_inherited_environment()
    {
        // Act
        var command = new TerminalCommand("true");

        // Assert
        command.Args.Should().BeEmpty();
        command.WorkingDirectory.IsNone().Should().BeTrue();
        command.Environment.Should().BeEmpty();
        command.IncludeParentEnvironment.Should().BeTrue();
        command.RunInShell.Should().BeFalse();
    }

    [Fact]
    public void It_should_render_a_terminal_command_without_args()
    {
        // Arrange
        var command = new TerminalCommand("true");

        // Act
        var rendered = command.ToString();

        // Assert
        rendered.Should().Be("true");
    }

    [Fact]
    public void It_should_reject_a_blank_executable()
    {
        // Act
        var act = () => new TerminalCommand("  ");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Theory]
    [InlineData(0, true)]
    [InlineData(3, false)]
    public void It_should_treat_only_a_zero_exit_code_as_success(int exitCode, bool expected)
    {
        // Arrange
        var output = new TerminalOutput(exitCode, "out", "err");

        // Act
        var succeeded = output.Succeeded;

        // Assert
        succeeded.Should().Be(expected);
    }

    [Fact]
    public void It_should_expose_every_terminal_output_component()
    {
        // Act
        var output = new TerminalOutput(3, "out", "err");

        // Assert
        output.ExitCode.Should().Be(3);
        output.Stdout.Should().Be("out");
        output.Stderr.Should().Be("err");
    }
}
