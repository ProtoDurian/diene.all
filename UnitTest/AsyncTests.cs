using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest;

public class AsyncTests
{
    [Fact]
    public async Task It_should_map_a_task_success_with_a_sync_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Map(x => x * 2);

        // Assert
        actual.Should().BeOk(4);
    }

    [Fact]
    public async Task It_should_not_map_a_task_failure_with_a_sync_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Map(x => x * 2);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public async Task It_should_map_a_task_success_with_an_async_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Map(x => Task.FromResult(x * 3));

        // Assert
        actual.Should().BeOk(6);
    }

    [Fact]
    public async Task It_should_not_map_a_task_failure_with_an_async_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Map(x => Task.FromResult(x * 3));

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public async Task It_should_chain_a_task_success_with_a_sync_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Then(x => Result.Ok<int, string>(x + 1));

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public async Task It_should_not_chain_a_task_failure_with_a_sync_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Then(x => Result.Ok<int, string>(x + 1));

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public async Task It_should_chain_a_task_success_with_an_async_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Then(x => Task.FromResult(Result.Ok<int, string>(x + 2)));

        // Assert
        actual.Should().BeOk(4);
    }

    [Fact]
    public async Task It_should_not_chain_a_task_failure_with_an_async_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Then(x => Task.FromResult(Result.Ok<int, string>(x + 2)));

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public async Task It_should_chain_a_task_success_through_a_capturing_sync_function()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Then(x => x + 3, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(5);
    }

    [Fact]
    public async Task It_should_not_chain_a_task_failure_through_a_capturing_sync_function()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Then(x => x + 3, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public async Task It_should_capture_a_matching_exception_from_a_capturing_async_function()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Then(_ => Task.FromException<int>(new InvalidOperationException("async")), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("async");
    }

    [Fact]
    public async Task It_should_not_chain_a_task_failure_through_a_capturing_async_function()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Then(x => Task.FromResult(x + 3), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public async Task It_should_rethrow_an_unmatched_exception_from_a_capturing_async_function()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var escaped = async () => await success.Then(_ => Task.FromException<int>(new InvalidOperationException()), Errors.MapNone, exception => exception.Message);

        // Assert
        await escaped.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task It_should_not_map_the_failure_of_a_task_success_with_a_sync_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.MapFailure(error => error.Length);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_map_the_failure_of_a_task_failure_with_a_sync_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.MapFailure(error => error.Length);

        // Assert
        actual.Should().BeErr(3);
    }

    [Fact]
    public async Task It_should_not_map_the_failure_of_a_task_success_with_an_async_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.MapFailure(error => Task.FromResult(error.Length));

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_map_the_failure_of_a_task_failure_with_an_async_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.MapFailure(error => Task.FromResult(error.Length));

        // Assert
        actual.Should().BeErr(3);
    }

    [Fact]
    public async Task It_should_keep_a_task_success_when_recovering_with_a_sync_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.OrElse(error => Result.Ok<int, string>(error.Length));

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_recover_a_task_failure_with_a_sync_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.OrElse(error => Result.Ok<int, string>(error.Length));

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public async Task It_should_keep_a_task_success_when_recovering_with_an_async_callback()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.OrElse(error => Task.FromResult(Result.Ok<int, string>(error.Length)));

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_recover_a_task_failure_with_an_async_callback()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.OrElse(error => Task.FromResult(Result.Ok<int, string>(error.Length)));

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public async Task It_should_run_a_sync_side_effect_on_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var observed = "";

        // Act
        var actual = await success.Do(value => observed = value.ToString());

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be("2");
    }

    [Fact]
    public async Task It_should_run_an_async_side_effect_on_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var observed = "";

        // Act
        var actual = await success.Do(value => { observed = value.ToString(); return Task.CompletedTask; });

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be("2");
    }

    [Fact]
    public async Task It_should_skip_an_async_side_effect_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var observed = "";

        // Act
        var actual = await failure.Do(value => { observed = value.ToString(); return Task.CompletedTask; });

        // Assert
        actual.Should().BeErr("bad");
        observed.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_run_a_capturing_sync_side_effect_on_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var observed = "";

        // Act
        var actual = await success.Do(value => observed = value.ToString(), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be("2");
    }

    [Fact]
    public async Task It_should_run_a_sync_failure_side_effect_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var observed = "";

        // Act
        var actual = await failure.DoFailure(error => observed = error);

        // Assert
        actual.Should().BeErr("bad");
        observed.Should().Be("bad");
    }

    [Fact]
    public async Task It_should_skip_an_async_failure_side_effect_on_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var observed = "";

        // Act
        var actual = await success.DoFailure(error => { observed = error; return Task.CompletedTask; });

        // Assert
        actual.Should().BeOk(2);
        observed.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_run_an_async_failure_side_effect_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var observed = "";

        // Act
        var actual = await failure.DoFailure(error => { observed = error; return Task.CompletedTask; });

        // Assert
        actual.Should().BeErr("bad");
        observed.Should().Be("bad");
    }

    [Fact]
    public async Task It_should_match_a_task_success_with_sync_callbacks()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Match(value => value.ToString(), error => error);

        // Assert
        actual.Should().Be("2");
    }

    [Fact]
    public async Task It_should_match_a_task_failure_with_sync_callbacks()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Match(value => value.ToString(), error => error);

        // Assert
        actual.Should().Be("bad");
    }

    [Fact]
    public async Task It_should_match_a_task_success_with_async_callbacks()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Match(value => Task.FromResult(value.ToString()), error => Task.FromResult(error));

        // Assert
        actual.Should().Be("2");
    }

    [Fact]
    public async Task It_should_match_a_task_failure_with_async_callbacks()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Match(value => Task.FromResult(value.ToString()), error => Task.FromResult(error));

        // Assert
        actual.Should().Be("bad");
    }

    [Fact]
    public async Task It_should_get_the_value_of_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Get();

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public async Task It_should_get_the_error_of_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.GetFailure();

        // Assert
        actual.Should().Be("bad");
    }

    [Fact]
    public async Task It_should_ignore_the_sync_fallback_for_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.GetOr(error => error.Length);

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public async Task It_should_compute_the_sync_fallback_for_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.GetOr(error => error.Length);

        // Assert
        actual.Should().Be(3);
    }

    [Fact]
    public async Task It_should_ignore_the_async_fallback_for_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.GetOr(error => Task.FromResult(error.Length));

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public async Task It_should_compute_the_async_fallback_for_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.GetOr(error => Task.FromResult(error.Length));

        // Assert
        actual.Should().Be(3);
    }

    [Fact]
    public async Task It_should_run_a_capturing_async_side_effect_on_a_task_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var observed = 0;

        // Act
        var actual = await success.Do(value => { observed = value; return Task.CompletedTask; }, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be(2);
    }

    [Fact]
    public async Task It_should_skip_a_capturing_async_side_effect_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var observed = 0;

        // Act
        var actual = await failure.Do(value => { observed = value; return Task.CompletedTask; }, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
        observed.Should().Be(0);
    }

    [Fact]
    public async Task It_should_capture_a_matching_exception_from_an_async_side_effect()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Do(
            _ => Task.FromException(new InvalidOperationException("mapped")),
            Errors.MapIfExceptionIs<InvalidOperationException>(),
            exception => exception.Message);

        // Assert
        actual.Should().BeErr("mapped");
    }

    [Fact]
    public async Task It_should_rethrow_an_unmatched_exception_from_an_async_side_effect()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var escaped = async () => await success.Do(
            _ => Task.FromException(new InvalidOperationException("escaped")),
            Errors.MapNone,
            exception => exception.Message);

        // Assert
        await escaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("escaped");
    }

    [Fact]
    public async Task It_should_keep_a_task_success_whose_sync_result_assertion_holds()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(value => Result.Ok<bool, string>(value == 2), _ => "false");

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_fail_a_task_success_whose_sync_result_assertion_is_false()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(_ => Result.Ok<bool, string>(false), _ => "false");

        // Assert
        actual.Should().BeErr("false");
    }

    [Fact]
    public async Task It_should_propagate_the_error_of_a_failing_sync_result_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(_ => Result.Err<bool, string>("assertion"), _ => "false");

        // Assert
        actual.Should().BeErr("assertion");
    }

    [Fact]
    public async Task It_should_not_run_a_sync_result_assertion_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        // Act
        var actual = await failure.Assert(value => { calls++; return Result.Ok<bool, string>(value == 2); }, _ => "false");

        // Assert
        actual.Should().BeErr("bad");
        calls.Should().Be(0);
    }

    [Fact]
    public async Task It_should_keep_a_task_success_whose_async_result_assertion_holds()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(
            value => Task.FromResult(Result.Ok<bool, string>(value == 2)),
            _ => "false");

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_fail_a_task_success_whose_async_result_assertion_is_false()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(
            _ => Task.FromResult(Result.Ok<bool, string>(false)),
            _ => "false");

        // Assert
        actual.Should().BeErr("false");
    }

    [Fact]
    public async Task It_should_propagate_the_error_of_a_failing_async_result_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(
            _ => Task.FromResult(Result.Err<bool, string>("assertion")),
            _ => "false");

        // Assert
        actual.Should().BeErr("assertion");
    }

    [Fact]
    public async Task It_should_not_run_an_async_result_assertion_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        // Act
        var actual = await failure.Assert(
            value => { calls++; return Task.FromResult(Result.Ok<bool, string>(value == 2)); },
            _ => "false");

        // Assert
        actual.Should().BeErr("bad");
        calls.Should().Be(0);
    }

    [Fact]
    public async Task It_should_not_capture_an_exception_from_a_sync_result_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var syncEscaped = async () => await success.Assert(ThrowingResultAssertion, _ => "false");

        // Assert
        await syncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("sync escaped");
    }

    [Fact]
    public async Task It_should_not_capture_an_exception_from_an_async_result_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var asyncEscaped = async () => await success.Assert(
            _ => Task.FromException<Result<bool, string>>(new InvalidOperationException("async escaped")),
            _ => "false");

        // Assert
        await asyncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("async escaped");
    }

    [Fact]
    public async Task It_should_keep_a_task_success_whose_capturing_sync_assertion_holds()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(value => value == 2, _ => "false", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_fail_a_task_success_whose_capturing_sync_assertion_is_false()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(_ => false, _ => "false", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("false");
    }

    [Fact]
    public async Task It_should_not_run_a_capturing_sync_assertion_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        // Act
        var actual = await failure.Assert(value => { calls++; return value == 2; }, _ => "false", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
        calls.Should().Be(0);
    }

    [Fact]
    public async Task It_should_capture_a_matching_exception_from_a_sync_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(
            MappedAssertion,
            _ => "false",
            Errors.MapIfExceptionIs<InvalidOperationException>(),
            exception => exception.Message);

        // Assert
        actual.Should().BeErr("mapped sync");
    }

    [Fact]
    public async Task It_should_rethrow_an_unmatched_exception_from_a_sync_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var syncEscaped = async () => await success.Assert(
            EscapedAssertion,
            _ => "false",
            Errors.MapNone,
            exception => exception.Message);

        // Assert
        await syncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("escaped sync");
    }

    [Fact]
    public async Task It_should_keep_a_task_success_whose_capturing_async_assertion_holds()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(value => Task.FromResult(value == 2), _ => "false", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public async Task It_should_fail_a_task_success_whose_capturing_async_assertion_is_false()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(_ => Task.FromResult(false), _ => "false", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("false");
    }

    [Fact]
    public async Task It_should_not_run_a_capturing_async_assertion_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        // Act
        var actual = await failure.Assert(
            value => { calls++; return Task.FromResult(value == 2); },
            _ => "false",
            Errors.MapAll,
            exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
        calls.Should().Be(0);
    }

    [Fact]
    public async Task It_should_capture_a_matching_exception_from_an_async_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Assert(
            _ => Task.FromException<bool>(new InvalidOperationException("mapped async")),
            _ => "false",
            Errors.MapIfExceptionIs<InvalidOperationException>(),
            exception => exception.Message);

        // Assert
        actual.Should().BeErr("mapped async");
    }

    [Fact]
    public async Task It_should_rethrow_an_unmatched_exception_from_an_async_assertion()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var asyncEscaped = async () => await success.Assert(
            _ => Task.FromException<bool>(new InvalidOperationException("escaped async")),
            _ => "false",
            Errors.MapNone,
            exception => exception.Message);

        // Assert
        await asyncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("escaped async");
    }

    [Fact]
    public async Task It_should_take_the_then_branch_of_a_task_success_with_sync_callbacks()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.If(
            value => Result.Ok<bool, string>(value == 2),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"));

        // Assert
        actual.Should().BeOk("then 2");
    }

    [Fact]
    public async Task It_should_take_the_else_branch_of_a_task_success_with_sync_callbacks()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.If(
            _ => Result.Ok<bool, string>(false),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"));

        // Assert
        actual.Should().BeOk("else 2");
    }

    [Fact]
    public async Task It_should_propagate_the_error_of_a_failing_sync_branch_predicate()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.If(
            _ => Result.Err<bool, string>("predicate"),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"));

        // Assert
        actual.Should().BeErr("predicate");
    }

    [Fact]
    public async Task It_should_not_run_a_sync_branch_predicate_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        // Act
        var actual = await failure.If(
            value => { calls++; return Result.Ok<bool, string>(value == 2); },
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"));

        // Assert
        actual.Should().BeErr("bad");
        calls.Should().Be(0);
    }

    [Fact]
    public async Task It_should_take_the_then_branch_of_a_task_success_with_async_callbacks()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.If(
            value => Task.FromResult(Result.Ok<bool, string>(value == 2)),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")));

        // Assert
        actual.Should().BeOk("then 2");
    }

    [Fact]
    public async Task It_should_take_the_else_branch_of_a_task_success_with_async_callbacks()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.If(
            _ => Task.FromResult(Result.Ok<bool, string>(false)),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")));

        // Assert
        actual.Should().BeOk("else 2");
    }

    [Fact]
    public async Task It_should_propagate_the_error_of_a_failing_async_branch_predicate()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.If(
            _ => Task.FromResult(Result.Err<bool, string>("predicate")),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")));

        // Assert
        actual.Should().BeErr("predicate");
    }

    [Fact]
    public async Task It_should_not_run_an_async_branch_predicate_on_a_task_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        // Act
        var actual = await failure.If(
            value => { calls++; return Task.FromResult(Result.Ok<bool, string>(value == 2)); },
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")));

        // Assert
        actual.Should().BeErr("bad");
        calls.Should().Be(0);
    }

    [Fact]
    public async Task It_should_not_capture_an_exception_from_a_sync_branch_predicate()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var syncEscaped = async () => await success.If<int, string, string>(
            _ => throw new InvalidOperationException("sync escaped"),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"));

        // Assert
        await syncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("sync escaped");
    }

    [Fact]
    public async Task It_should_not_capture_an_exception_from_an_async_branch_predicate()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var asyncEscaped = async () => await success.If(
            _ => Task.FromException<Result<bool, string>>(new InvalidOperationException("async escaped")),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")));

        // Assert
        await asyncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("async escaped");
    }

    private static Result<bool, string> ThrowingResultAssertion(int _) =>
        throw new InvalidOperationException("sync escaped");

    private static bool MappedAssertion(int _) => throw new InvalidOperationException("mapped sync");

    private static bool EscapedAssertion(int _) => throw new InvalidOperationException("escaped sync");
}
