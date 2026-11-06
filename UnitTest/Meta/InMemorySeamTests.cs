namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class InMemorySeamTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    private static CancellationToken Token => TestContext.Current.CancellationToken;

    private static SeamError SystemFailure => SeamErrors.IoFailure(SeamKind.System, "probe", "injected");

    [Fact]
    public void The_system_mock_should_keep_its_seeded_environment_when_a_variable_is_set()
    {
        // Arrange
        var system = new InMemorySystem(Anchor, "/work", [new("KEEP", "1")]);
        system.SetEnvironment("ADDED", "2");

        // Act
        var result = system.Environment("KEEP");

        // Assert
        result.Should().BeOk().Which.Should().BeSome("1");
    }

    [Fact]
    public void The_system_mock_should_expose_a_set_environment_variable()
    {
        // Arrange
        var system = new InMemorySystem(Anchor, "/work", [new("KEEP", "1")]);
        system.SetEnvironment("ADDED", "2");

        // Act
        var result = system.Environment("ADDED");

        // Assert
        result.Should().BeOk().Which.Should().BeSome("2");
    }

    [Fact]
    public void The_system_mock_should_remove_an_environment_variable()
    {
        // Arrange
        var system = new InMemorySystem(Anchor, "/work", [new("KEEP", "1")]);
        system.SetEnvironment("ADDED", "2");
        system.RemoveEnvironment("ADDED");

        // Act
        var result = system.Environment("ADDED");

        // Assert
        result.Should().BeOk().Which.IsNone().Should().BeTrue();
    }

    [Fact]
    public void The_system_mock_should_report_its_supplied_clock()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var now = system.NowUtc();

        // Assert
        now.Should().BeOk(Anchor);
    }

    [Fact]
    public void The_system_mock_should_advance_its_clock()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.Advance(TimeSpan.FromMinutes(1));

        // Act
        var now = system.NowUtc();

        // Assert
        now.Should().BeOk(Anchor.AddMinutes(1));
    }

    [Fact]
    public void The_system_mock_should_set_its_clock()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.Advance(TimeSpan.FromMinutes(1));
        system.SetNow(Anchor);

        // Act
        var now = system.NowUtc();

        // Assert
        now.Should().BeOk(Anchor);
    }

    [Fact]
    public void The_system_mock_should_default_its_clock()
    {
        // Arrange
        var system = new InMemorySystem();

        // Act
        var now = system.NowUtc();

        // Assert
        now.Should().BeOk(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
    }

    [Fact]
    public void The_system_mock_should_default_its_directory()
    {
        // Arrange
        var system = new InMemorySystem();

        // Act
        var directory = system.CurrentDirectory();

        // Assert
        directory.Should().BeOk("/work");
    }

    [Fact]
    public void The_system_mock_should_normalize_a_supplied_clock_to_utc()
    {
        // Arrange
        var system = new InMemorySystem(new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8)));

        // Act
        var now = system.NowUtc();

        // Assert
        now.Should().BeOk(Anchor);
    }

    [Fact]
    public void The_system_mock_should_expose_a_settable_directory()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.SetDirectory("/other");

        // Act
        var directory = system.CurrentDirectory();

        // Assert
        directory.Should().BeOk("/other");
    }

    [Fact]
    public async Task The_system_mock_should_record_and_apply_delays()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var result = await system.Delay(TimeSpan.FromSeconds(5), Token);

        // Assert
        result.Should().BeOk();
        system.RequestedDelays.Should().Equal(TimeSpan.FromSeconds(5));
        system.NowUtc().Should().BeOk(Anchor.AddSeconds(5));
    }

    [Fact]
    public async Task The_system_mock_should_report_a_cancelled_delay_as_a_failure_value()
    {
        // Arrange
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();
        var system = new InMemorySystem(Anchor);

        // Act
        var result = await system.Delay(TimeSpan.FromSeconds(5), cancelled.Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "cancelled");
    }

    [Fact]
    public void The_system_mock_should_fail_an_environment_read_with_a_queued_failure()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.EnqueueFailure(SystemFailure);

        // Act
        var result = system.Environment("ANY");

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "io_failure");
    }

    [Fact]
    public void The_system_mock_should_consume_a_queued_failure_in_one_call()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.EnqueueFailure(SystemFailure);
        system.Environment("ANY").Should().BeErr();

        // Act
        var result = system.Environment("ANY");

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void The_system_mock_should_fail_a_directory_read_with_a_queued_failure()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.EnqueueFailure(SystemFailure);

        // Act
        var result = system.CurrentDirectory();

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "io_failure");
    }

    [Fact]
    public void The_system_mock_should_fail_a_clock_read_with_a_queued_failure()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.EnqueueFailure(SystemFailure);

        // Act
        var result = system.NowUtc();

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "io_failure");
    }

    [Fact]
    public async Task The_system_mock_should_fail_a_delay_with_a_queued_failure()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);
        system.EnqueueFailure(SystemFailure);

        // Act
        var result = await system.Delay(TimeSpan.Zero, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "io_failure");
    }

    [Fact]
    public void The_system_mock_should_reject_a_blank_variable_name()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var result = system.Environment("  ");

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "invalid_argument");
    }

    [Fact]
    public void The_system_mock_should_reject_a_blank_initial_directory()
    {
        // Act
        var act = () => new InMemorySystem(Anchor, "  ");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_system_mock_should_reject_setting_a_blank_variable_name()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var act = () => system.SetEnvironment(" ", "v");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_system_mock_should_reject_setting_a_null_variable_value()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var act = () => system.SetEnvironment("k", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_system_mock_should_reject_removing_a_blank_variable_name()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var act = () => system.RemoveEnvironment(" ");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_system_mock_should_reject_setting_a_blank_directory()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var act = () => system.SetDirectory(" ");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_system_mock_should_reject_queueing_a_null_failure()
    {
        // Arrange
        var system = new InMemorySystem(Anchor);

        // Act
        var act = () => system.EnqueueFailure(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task The_vfs_mock_should_seed_files_with_their_ancestors()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        vfs.Seed("/a/b/c.txt", "hello");

        // Assert
        (await vfs.ReadText("/a/b/c.txt", Token)).Should().BeOk("hello");
        vfs.Directories.Should().Contain(["/", "/a", "/a/b"]);
        vfs.Files.Should().ContainKey("/a/b/c.txt");
    }

    [Fact]
    public async Task The_vfs_mock_should_report_entry_metadata_from_its_fixed_clock()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a/b.txt", "hello");

        // Act
        var result = await vfs.List("/a", default, Token);

        // Assert
        result.Should().BeOk().Which.Should().ContainSingle().Which.ModifiedAt.Should().BeSome(Anchor);
    }

    [Fact]
    public async Task The_vfs_mock_should_fail_the_next_call_with_a_queued_failure()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);
        vfs.EnqueueFailure(SeamErrors.IoFailure(SeamKind.Vfs, "probe", "injected"));

        // Act
        var result = await vfs.Exists("/a", Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "io_failure");
    }

    [Fact]
    public async Task The_vfs_mock_should_consume_a_queued_failure_in_one_call()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);
        vfs.EnqueueFailure(SeamErrors.IoFailure(SeamKind.Vfs, "probe", "injected"));
        (await vfs.Exists("/a", Token)).Should().BeErr();

        // Act
        var result = await vfs.Exists("/a", Token);

        // Assert
        result.Should().BeOk(false);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_probing_existence(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.Exists(path, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_reading_bytes(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.ReadBytes(path, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_reading_text(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.ReadText(path, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_writing_bytes(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.WriteBytes(path, ReadOnlyMemory<byte>.Empty, default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_writing_text(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.WriteText(path, "x", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_listing(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.List(path, default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_creating_a_directory(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.CreateDirectory(path, default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_vfs_mock_should_reject_a_blank_path_when_deleting(string path)
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.Delete(path, default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_vfs_mock_should_refuse_a_non_recursive_directory_under_a_missing_parent()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var result = await vfs.CreateDirectory("/a/b", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "not_found");
    }

    [Fact]
    public async Task The_vfs_mock_should_treat_an_existing_file_as_an_occupied_directory_path()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a.txt", "hello");

        // Act
        var result = await vfs.CreateDirectory("/a.txt", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "already_exists");
    }

    [Fact]
    public async Task The_vfs_mock_should_accept_a_recursive_directory_over_an_existing_file()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a.txt", "hello");

        // Act
        var result = await vfs.CreateDirectory("/a.txt", new VfsDirectoryOptions(true), Token);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public async Task The_vfs_mock_should_expose_independently_owned_snapshots()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);
        vfs.Seed("/a.txt", "hello");
        var before = vfs.Files;
        var directories = vfs.Directories;

        // Act
        var result = await vfs.WriteText("/b.txt", "world", default, Token);

        // Assert
        result.Should().BeOk();
        before.Should().HaveCount(1);
        directories.Should().HaveCount(1);
        vfs.Files.Should().HaveCount(2);
    }

    [Fact]
    public void The_vfs_mock_should_reject_seeding_a_blank_path()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var act = () => vfs.Seed(" ", "x");

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_vfs_mock_should_reject_seeding_null_content()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var act = () => vfs.Seed("/a", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_vfs_mock_should_reject_queueing_a_null_failure()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var act = () => vfs.EnqueueFailure(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task The_vfs_mock_should_reject_writing_null_content()
    {
        // Arrange
        var vfs = new InMemoryVfs(Anchor);

        // Act
        var act = async () => await vfs.WriteText("/a", null!, default, Token);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_terminal_mock_should_return_a_programmed_output()
    {
        // Arrange
        var terminal = new InMemoryTerminal();
        terminal.Program("ok", new TerminalOutput(0, "hello", string.Empty));

        // Act
        var result = await terminal.Run(new TerminalCommand("ok", ["arg"]), Token);

        // Assert
        result.Should().BeOk().Which.Stdout.Should().Be("hello");
    }

    [Fact]
    public async Task The_terminal_mock_should_return_a_scripted_failure()
    {
        // Arrange
        var terminal = new InMemoryTerminal();
        terminal.Fail("bad", SeamErrors.LaunchFailed("bad", "scripted"));

        // Act
        var result = await terminal.Run(new TerminalCommand("bad"), Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Terminal, "launch_failed");
    }

    [Fact]
    public async Task The_terminal_mock_should_fail_to_launch_an_unprogrammed_executable()
    {
        // Arrange
        var terminal = new InMemoryTerminal();

        // Act
        var result = await terminal.Run(new TerminalCommand("absent"), Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Terminal, "launch_failed");
    }

    [Fact]
    public async Task The_terminal_mock_should_record_every_command_in_order()
    {
        // Arrange
        var terminal = new InMemoryTerminal();
        terminal.Program("ok", new TerminalOutput(0, "hello", string.Empty));
        terminal.Fail("bad", SeamErrors.LaunchFailed("bad", "scripted"));

        // Act
        await terminal.Run(new TerminalCommand("ok", ["arg"]), Token);
        await terminal.Run(new TerminalCommand("bad"), Token);
        await terminal.Run(new TerminalCommand("absent"), Token);

        // Assert
        terminal.Commands.Select(command => command.Executable).Should().Equal("ok", "bad", "absent");
    }

    [Fact]
    public async Task The_terminal_mock_should_reject_a_null_command()
    {
        // Arrange
        var terminal = new InMemoryTerminal();

        // Act
        var result = await terminal.Run(null!, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Terminal, "invalid_argument");
    }

    [Fact]
    public void The_terminal_mock_should_reject_programming_a_blank_executable()
    {
        // Arrange
        var terminal = new InMemoryTerminal();

        // Act
        var act = () => terminal.Program(" ", default);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_terminal_mock_should_reject_failing_a_blank_executable()
    {
        // Arrange
        var terminal = new InMemoryTerminal();

        // Act
        var act = () => terminal.Fail(" ", SeamErrors.LaunchFailed("x", "y"));

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void The_terminal_mock_should_reject_failing_with_a_null_error()
    {
        // Arrange
        var terminal = new InMemoryTerminal();

        // Act
        var act = () => terminal.Fail("x", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_logger_mock_should_fail_an_emit_with_a_queued_failure()
    {
        // Arrange
        var logger = new InMemoryLoggerSink();
        logger.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Logging, "injected"));

        // Act
        var result = logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one"));

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "emit_failed");
    }

    [Fact]
    public void The_logger_mock_should_consume_a_queued_failure_in_one_emit()
    {
        // Arrange
        var logger = new InMemoryLoggerSink();
        logger.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Logging, "injected"));
        logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one")).Should().BeErr();

        // Act
        var result = logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one"));

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void The_logger_mock_should_reject_a_null_record()
    {
        // Arrange
        var logger = new InMemoryLoggerSink();

        // Act
        var result = logger.Emit(null!);

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_argument");
    }

    [Fact]
    public void The_logger_mock_should_record_only_successful_emits()
    {
        // Arrange
        var logger = new InMemoryLoggerSink();
        logger.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Logging, "injected"));

        // Act
        logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one"));
        logger.Emit(new LogRecord(Anchor, LogLevel.Info, "one"));
        logger.Emit(null!);

        // Assert
        logger.Records.Should().ContainSingle();
    }

    [Fact]
    public void The_logger_mock_should_reject_queueing_a_null_failure()
    {
        // Arrange
        var logger = new InMemoryLoggerSink();

        // Act
        var act = () => logger.EnqueueFailure(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void The_metrics_mock_should_fail_an_emit_with_a_queued_failure()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Metrics, "injected"));

        // Act
        var result = collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1));

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "emit_failed");
    }

    [Fact]
    public void The_metrics_mock_should_consume_a_queued_failure_in_one_emit()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Metrics, "injected"));
        collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1)).Should().BeErr();

        // Act
        var result = collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1));

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void The_metrics_mock_should_reject_a_null_record()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();

        // Act
        var result = collector.Emit(null!);

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "invalid_argument");
    }

    [Fact]
    public void The_metrics_mock_should_record_only_successful_emits()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.EnqueueFailure(SeamErrors.EmitFailed(SeamKind.Metrics, "injected"));

        // Act
        collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1));
        collector.Emit(new MetricRecord(Anchor, "m", MetricKind.Gauge, 1));
        collector.Emit(null!);

        // Assert
        collector.Records.Should().ContainSingle();
    }

    [Fact]
    public void The_metrics_mock_should_reject_queueing_a_null_failure()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();

        // Act
        var act = () => collector.EnqueueFailure(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
