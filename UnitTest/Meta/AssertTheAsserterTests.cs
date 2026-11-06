namespace AtomiCloud.DotnetBase.UnitTest.Meta;

public class AssertTheAsserterTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void BeSeamErr_should_pass_on_the_expected_seam_and_id()
    {
        // Arrange
        var result = Result.Err<int, SeamError>(SeamErrors.NotFound("/tmp/a"));

        // Act
        var error = result.Should().BeSeamErr(SeamKind.Vfs, "not_found").Which;

        // Assert
        error.Data["path"].Should().Be("/tmp/a");
    }

    [Fact]
    public void BeSeamErr_should_fail_on_a_different_id()
    {
        // Arrange
        var result = Result.Err<int, SeamError>(SeamErrors.NotFound("/tmp/a"));

        // Act
        var act = () => result.Should().BeSeamErr(SeamKind.Vfs, "already_exists");

        // Assert
        act.Should().Throw<Exception>().WithMessage("*already_exists*not_found*");
    }

    [Fact]
    public void BeSeamErr_should_fail_on_a_different_seam()
    {
        // Arrange
        var result = Result.Err<int, SeamError>(SeamErrors.NotFound("/tmp/a"));

        // Act
        var act = () => result.Should().BeSeamErr(SeamKind.System, "not_found");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeSeamErr_should_fail_on_a_successful_result()
    {
        // Arrange
        var result = Result.Ok<int, SeamError>(1);

        // Act
        var act = () => result.Should().BeSeamErr(SeamKind.Vfs, "not_found");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void BeSeamErr_should_reject_a_null_assertion_subject()
    {
        // Act
        var act = () => SeamAssertionExtensions.BeSeamErr<int>(null!, SeamKind.Vfs, "not_found");

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task BeConformant_should_pass_on_a_conformant_implementation()
    {
        // Act
        var report = await SeamContracts.Vfs(new InMemoryVfs(Anchor), "/root");

        // Assert
        report.Should().BeConformant();
        report.Failures.Should().BeEmpty();
        report.ToString().Should().Contain("cases conformant");
    }

    [Fact]
    public async Task A_contract_report_should_fail_every_case_of_an_implementation_that_always_fails()
    {
        // Act
        var report = await SeamContracts.Vfs(new AlwaysFailingVfs(), "/root");

        // Assert
        report.Conformant.Should().BeFalse();
        report.Failures.Should().HaveCount(report.Cases.Count);
        report.ToString().Should().Contain("cases failed");
    }

    [Fact]
    public async Task BeConformant_should_fail_on_an_implementation_that_always_fails()
    {
        // Arrange
        var report = await SeamContracts.Vfs(new AlwaysFailingVfs(), "/root");

        // Act
        var act = () => report.Should().BeConformant();

        // Assert
        act.Should().Throw<Exception>().WithMessage("*conformant*");
    }

    [Fact]
    public async Task BeConformant_should_fail_on_an_implementation_that_never_fails()
    {
        // Act
        var report = await SeamContracts.Vfs(new AlwaysSucceedingVfs(), "/root");

        // Assert
        report.Conformant.Should().BeFalse();
        report.Failures.Should().NotBeEmpty();
        report.Cases.Should().Contain(one => one.Passed);
    }

    [Fact]
    public async Task BeConformant_should_fail_on_an_implementation_that_throws()
    {
        // Act
        var report = await SeamContracts.Vfs(new ThrowingVfs(), "/root");

        // Assert
        report.Conformant.Should().BeFalse();
        report.Failures.Should().AllSatisfy(failure => failure.Should().Contain("threw InvalidOperationException"));
    }

    [Fact]
    public void HaveLogged_should_pass_on_a_matching_record()
    {
        // Arrange
        var sink = new InMemoryLoggerSink();
        sink.Emit(new LogRecord(Anchor, LogLevel.Warning, "careful")).Should().BeOk();

        // Act
        var record = sink.Should().HaveLogged(LogLevel.Warning, "careful").Which;

        // Assert
        record.Timestamp.Should().Be(Anchor);
    }

    [Fact]
    public void HaveLogged_should_fail_on_a_different_level()
    {
        // Arrange
        var sink = new InMemoryLoggerSink();
        sink.Emit(new LogRecord(Anchor, LogLevel.Warning, "careful"));

        // Act
        var act = () => sink.Should().HaveLogged(LogLevel.Error, "careful");

        // Assert
        act.Should().Throw<Exception>().WithMessage("*error*careful*");
    }

    [Fact]
    public void HaveLogged_should_fail_on_a_different_message()
    {
        // Arrange
        var sink = new InMemoryLoggerSink();
        sink.Emit(new LogRecord(Anchor, LogLevel.Warning, "careful"));

        // Act
        var act = () => sink.Should().HaveLogged(LogLevel.Warning, "other");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveLogged_should_fail_on_an_empty_sink()
    {
        // Arrange
        var sink = new InMemoryLoggerSink();

        // Act
        var act = () => sink.Should().HaveLogged(LogLevel.Info, "anything");

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveSampled_should_pass_on_a_matching_sample()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.Emit(new MetricRecord(Anchor, "app.count", MetricKind.Counter, 1)).Should().BeOk();

        // Act
        var record = collector.Should().HaveSampled("app.count", MetricKind.Counter, 1).Which;

        // Assert
        record.Unit.IsNone().Should().BeTrue();
    }

    [Fact]
    public void HaveSampled_should_fail_on_a_different_name()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.Emit(new MetricRecord(Anchor, "app.count", MetricKind.Counter, 1));

        // Act
        var act = () => collector.Should().HaveSampled("app.other", MetricKind.Counter, 1);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveSampled_should_fail_on_a_different_kind()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.Emit(new MetricRecord(Anchor, "app.count", MetricKind.Counter, 1));

        // Act
        var act = () => collector.Should().HaveSampled("app.count", MetricKind.Gauge, 1);

        // Assert
        act.Should().Throw<Exception>().WithMessage("*gauge*app.count*");
    }

    [Fact]
    public void HaveSampled_should_fail_on_a_different_value()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();
        collector.Emit(new MetricRecord(Anchor, "app.count", MetricKind.Counter, 1));

        // Act
        var act = () => collector.Should().HaveSampled("app.count", MetricKind.Counter, 2);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void HaveSampled_should_fail_on_an_empty_collector()
    {
        // Arrange
        var collector = new InMemoryMetricsCollector();

        // Act
        var act = () => collector.Should().HaveSampled("app.count", MetricKind.Counter, 1);

        // Assert
        act.Should().Throw<Exception>();
    }

    [Fact]
    public void A_passing_contract_case_should_render_ok()
    {
        // Arrange
        var passing = new ContractCase("case", Option.None<string>());

        // Act
        var rendered = passing.ToString();

        // Assert
        rendered.Should().Be("case: ok");
    }

    [Fact]
    public void A_failing_contract_case_should_render_its_failure()
    {
        // Arrange
        var failing = new ContractCase("case", Option.Some("boom"));

        // Act
        var rendered = failing.ToString();

        // Assert
        rendered.Should().Be("case: boom");
    }

    [Fact]
    public void A_failing_contract_case_should_not_pass()
    {
        // Arrange
        var failing = new ContractCase("case", Option.Some("boom"));

        // Act
        var passed = failing.Passed;

        // Assert
        passed.Should().BeFalse();
    }
}
