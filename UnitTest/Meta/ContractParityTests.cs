namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class ContractParityTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public async Task The_in_memory_vfs_should_satisfy_the_vfs_contract()
    {
        // Act
        var report = await SeamContracts.Vfs(new InMemoryVfs(Anchor), "/root");

        // Assert
        report.Seam.Should().Be(SeamKind.Vfs);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_in_memory_system_should_satisfy_the_system_contract()
    {
        // Arrange
        var system = new InMemorySystem(Anchor, "/work", [new("DIENE_PRESENT", "yes")]);

        // Act
        var report = await SeamContracts.System(system, "DIENE_PRESENT", "yes", "DIENE_ABSENT");

        // Assert
        report.Seam.Should().Be(SeamKind.System);
        report.Should().BeConformant();
    }

    [Fact]
    public async Task The_in_memory_terminal_should_satisfy_the_terminal_contract()
    {
        // Arrange
        var terminal = new InMemoryTerminal();
        terminal.Program("diene-ok", new TerminalOutput(0, "hello", string.Empty));
        terminal.Program("diene-fail", new TerminalOutput(3, string.Empty, "boom"));

        // Act
        var report = await SeamContracts.Terminal(
            terminal,
            new TerminalCommand("diene-ok"),
            "hello",
            new TerminalCommand("diene-fail"),
            new TerminalCommand("diene-missing"));

        // Assert
        report.Seam.Should().Be(SeamKind.Terminal);
        report.Should().BeConformant();
        terminal.Commands.Should().HaveCount(3);
    }

    [Fact]
    public async Task The_in_memory_logger_sink_should_satisfy_the_logging_contract()
    {
        // Arrange
        var sink = new InMemoryLoggerSink();

        // Act
        var report = await SeamContracts.LoggerSink(sink, Anchor);

        // Assert
        report.Seam.Should().Be(SeamKind.Logging);
        report.Should().BeConformant();
        sink.Records.Should().HaveCount(2);
    }

    [Fact]
    public async Task The_in_memory_metrics_collector_should_satisfy_the_metrics_contract()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();

        // Act
        var report = await SeamContracts.MetricsCollector(collector, Anchor);

        // Assert
        report.Seam.Should().Be(SeamKind.Metrics);
        report.Should().BeConformant();
        collector.Records.Should().HaveCount(2);
    }

    [Fact]
    public void The_sample_attribute_map_should_cover_every_kind()
    {
        // Act
        var kinds = SeamContracts.SampleAttributes(Anchor).Values.Select(value => value.Kind).ToArray();

        // Assert
        kinds.Should().BeEquivalentTo(Enum.GetValues<AttributeValueKind>());
    }

    [Fact]
    public async Task The_vfs_contract_should_reject_a_null_seam()
    {
        // Act
        var act = () => SeamContracts.Vfs(null!, "/root");

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_vfs_contract_should_reject_a_blank_root()
    {
        // Act
        var act = () => SeamContracts.Vfs(new InMemoryVfs(), "  ");

        // Assert
        await act.Should().ThrowAsync<ArgumentException>();
    }

    [Fact]
    public async Task The_system_contract_should_reject_a_null_seam()
    {
        // Act
        var act = () => SeamContracts.System(null!, "A", "a", "B");

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_system_contract_should_reject_a_blank_present_variable()
    {
        // Act
        var act = () => SeamContracts.System(new InMemorySystem(), " ", "a", "B");

        // Assert
        await act.Should().ThrowAsync<ArgumentException>();
    }

    [Fact]
    public async Task The_system_contract_should_reject_a_null_expected_value()
    {
        // Act
        var act = () => SeamContracts.System(new InMemorySystem(), "A", null!, "B");

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_system_contract_should_reject_a_blank_absent_variable()
    {
        // Act
        var act = () => SeamContracts.System(new InMemorySystem(), "A", "a", " ");

        // Assert
        await act.Should().ThrowAsync<ArgumentException>();
    }

    [Fact]
    public async Task The_terminal_contract_should_reject_a_null_seam()
    {
        // Act
        var act = () => SeamContracts.Terminal(
            null!,
            new TerminalCommand("a"),
            "x",
            new TerminalCommand("b"),
            new TerminalCommand("c"));

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_terminal_contract_should_reject_a_null_zero_exit_command()
    {
        // Act
        var act = () => SeamContracts.Terminal(
            new InMemoryTerminal(),
            null!,
            "x",
            new TerminalCommand("b"),
            new TerminalCommand("c"));

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_terminal_contract_should_reject_a_null_expected_stdout()
    {
        // Act
        var act = () => SeamContracts.Terminal(
            new InMemoryTerminal(),
            new TerminalCommand("a"),
            null!,
            new TerminalCommand("b"),
            new TerminalCommand("c"));

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_terminal_contract_should_reject_a_null_non_zero_exit_command()
    {
        // Act
        var act = () => SeamContracts.Terminal(
            new InMemoryTerminal(),
            new TerminalCommand("a"),
            "x",
            null!,
            new TerminalCommand("c"));

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_terminal_contract_should_reject_a_null_missing_command()
    {
        // Act
        var act = () => SeamContracts.Terminal(
            new InMemoryTerminal(),
            new TerminalCommand("a"),
            "x",
            new TerminalCommand("b"),
            null!);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_logging_contract_should_reject_a_null_seam()
    {
        // Act
        var act = () => SeamContracts.LoggerSink(null!, Anchor);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task The_metrics_contract_should_reject_a_null_seam()
    {
        // Act
        var act = () => SeamContracts.MetricsCollector(null!, Anchor);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public void A_contract_report_should_reject_null_cases()
    {
        // Act
        var act = () => new ContractReport(SeamKind.Vfs, null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
