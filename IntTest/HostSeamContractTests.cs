using AtomiCloud.DotnetBase.App;
using AtomiCloud.DotnetBase.App.Adapters;

namespace AtomiCloud.DotnetBase.IntTest;

public class HostSeamContractTests : IDisposable
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        $"diene-interfaces-int-{Guid.NewGuid():N}");

    public HostSeamContractTests() => Directory.CreateDirectory(_root);

    private static CancellationToken Token => TestContext.Current.CancellationToken;

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
        GC.SuppressFinalize(this);
    }

    [Fact]
    public async Task The_host_vfs_should_satisfy_the_vfs_contract()
    {
        // Act
        var report = await SeamContracts.Vfs(new HostVfs(), _root);

        // Assert
        report.Seam.Should().Be(SeamKind.Vfs);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_host_system_should_satisfy_the_system_contract()
    {
        // Arrange
        var present = $"DIENE_INT_{Guid.NewGuid():N}";
        var absent = $"DIENE_INT_ABSENT_{Guid.NewGuid():N}";
        Environment.SetEnvironmentVariable(present, "yes");
        try
        {
            // Act
            var report = await SeamContracts.System(new HostSystem(), present, "yes", absent);

            // Assert
            report.Seam.Should().Be(SeamKind.System);
            report.Should().BeConformant();
        }
        finally
        {
            Environment.SetEnvironmentVariable(present, null);
        }
    }

    [Fact]
    public async Task The_host_terminal_should_satisfy_the_terminal_contract()
    {
        // Act
        var report = await SeamContracts.Terminal(
            new HostTerminal(),
            new TerminalCommand("sh", ["-c", "printf hello"]),
            "hello",
            new TerminalCommand("sh", ["-c", "exit 3"]),
            new TerminalCommand($"diene-absent-{Guid.NewGuid():N}"));

        // Assert
        report.Seam.Should().Be(SeamKind.Terminal);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_host_logger_sink_should_satisfy_the_logging_contract()
    {
        // Arrange
        await using var writer = new StringWriter();

        // Act
        var report = await SeamContracts.LoggerSink(new TextWriterLoggerSink(writer), Anchor);

        // Assert
        report.Should().BeConformant();
        writer.ToString().Should().Contain("contract");
    }

    [Fact]
    public async Task The_host_metrics_collector_should_satisfy_the_metrics_contract()
    {
        // Arrange
        await using var writer = new StringWriter();

        // Act
        var report = await SeamContracts.MetricsCollector(new TextWriterMetricsCollector(writer), Anchor);

        // Assert
        report.Should().BeConformant();
        writer.ToString().Should().Contain("contract");
    }

    [Fact]
    public async Task The_host_logger_sink_should_report_a_closed_destination_as_a_failure_value()
    {
        // Arrange
        var writer = new StringWriter();
        await writer.DisposeAsync();
        var sink = new TextWriterLoggerSink(writer);

        // Act
        var result = sink.Emit(new LogRecord(Anchor, LogLevel.Info, "closed"));

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "emit_failed");
    }

    [Fact]
    public async Task The_host_metrics_collector_should_report_a_closed_destination_as_a_failure_value()
    {
        // Arrange
        var writer = new StringWriter();
        await writer.DisposeAsync();
        var collector = new TextWriterMetricsCollector(writer);

        // Act
        var result = collector.Emit(new MetricRecord(Anchor, "closed", MetricKind.Counter, 1));

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "emit_failed");
    }

    [Fact]
    public void The_host_logger_sink_should_reject_a_null_record()
    {
        // Arrange
        var sink = new TextWriterLoggerSink(TextWriter.Null);

        // Act
        var result = sink.Emit(null!);

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_argument");
    }

    [Fact]
    public void The_host_metrics_collector_should_reject_a_null_record()
    {
        // Arrange
        var collector = new TextWriterMetricsCollector(TextWriter.Null);

        // Act
        var result = collector.Emit(null!);

        // Assert
        result.Should().BeSeamErr(SeamKind.Metrics, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path_when_probing_existence()
    {
        // Arrange
        var vfs = new HostVfs();

        // Act
        var result = await vfs.Exists("  ", Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path_when_reading_text()
    {
        // Arrange
        var vfs = new HostVfs();

        // Act
        var result = await vfs.ReadText("  ", Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path_when_writing_text()
    {
        // Arrange
        var vfs = new HostVfs();

        // Act
        var result = await vfs.WriteText("  ", "x", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path_when_listing()
    {
        // Arrange
        var vfs = new HostVfs();

        // Act
        var result = await vfs.List("  ", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path_when_creating_a_directory()
    {
        // Arrange
        var vfs = new HostVfs();

        // Act
        var result = await vfs.CreateDirectory("  ", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_reject_a_blank_path_when_deleting()
    {
        // Arrange
        var vfs = new HostVfs();

        // Act
        var result = await vfs.Delete("  ", default, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Vfs, "invalid_argument");
    }

    [Fact]
    public async Task The_host_vfs_should_report_a_symbolic_link_as_a_link_entry()
    {
        // Arrange
        var vfs = new HostVfs();
        var target = Path.Combine(_root, "target.txt");
        var link = Path.Combine(_root, "link.txt");
        (await vfs.WriteText(target, "hello", default, Token)).Should().BeOk();
        File.CreateSymbolicLink(link, target);

        // Act
        var result = await vfs.List(_root, default, Token);

        // Assert
        var entries = result.Should().BeOk().Which;
        entries.Should().Contain(entry => entry.Type == VfsEntryType.Link);
        entries.Should().Contain(entry => entry.Type == VfsEntryType.File);
    }

    [Fact]
    public async Task The_host_system_should_report_a_cancelled_delay_as_a_failure_value()
    {
        // Arrange
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();
        var system = new HostSystem();

        // Act
        var result = await system.Delay(TimeSpan.FromSeconds(30), cancelled.Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "cancelled");
    }

    [Fact]
    public void The_host_system_should_reject_a_blank_variable_name()
    {
        // Arrange
        var system = new HostSystem();

        // Act
        var result = system.Environment("  ");

        // Assert
        result.Should().BeSeamErr(SeamKind.System, "invalid_argument");
    }

    [Fact]
    public void The_host_system_should_report_the_current_directory()
    {
        // Arrange
        var system = new HostSystem();

        // Act
        var result = system.CurrentDirectory();

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void The_host_system_should_report_the_clock_in_utc()
    {
        // Arrange
        var system = new HostSystem();

        // Act
        var result = system.NowUtc();

        // Assert
        result.Should().BeOk().Which.Offset.Should().Be(TimeSpan.Zero);
    }

    [Fact]
    public async Task The_host_system_should_complete_a_zero_delay()
    {
        // Arrange
        var system = new HostSystem();

        // Act
        var result = await system.Delay(TimeSpan.Zero, Token);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public async Task The_host_terminal_should_reject_a_null_command()
    {
        // Arrange
        var terminal = new HostTerminal();

        // Act
        var result = await terminal.Run(null!, Token);

        // Assert
        result.Should().BeSeamErr(SeamKind.Terminal, "invalid_argument");
    }

    [Fact]
    public async Task The_host_terminal_should_honour_a_command_environment_and_working_directory()
    {
        // Arrange
        var command = new TerminalCommand(
            "sh",
            ["-c", "printf \"$DIENE_INT_VALUE:$(pwd)\""],
            _root,
            [new("DIENE_INT_VALUE", "carried")]);

        // Act
        var result = await new HostTerminal().Run(command, Token);

        // Assert
        result.Should().BeOk().Which.Stdout.Should().StartWith("carried:");
    }

    [Fact]
    public void The_demo_consumer_should_exercise_the_published_surface_against_the_host()
    {
        // Act
        var act = Samples.RunAll;

        // Assert
        act.Should().NotThrow();
    }
}
