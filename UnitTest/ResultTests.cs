using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.DotnetBase.UnitTest;

public class ResultTests
{
    [Fact]
    public void It_should_report_a_success_as_a_success()
    {
        // Arrange
        Result<int, string> success = Result.Ok<int, string>(2);

        // Act
        var actual = success.IsSuccess();

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_report_a_success_as_a_failure()
    {
        // Arrange
        Result<int, string> success = Result.Ok<int, string>(2);

        // Act
        var actual = success.IsFailure();

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_extract_the_value_when_inspecting_a_success()
    {
        // Arrange
        Result<int, string> success = Result.Ok<int, string>(2);

        // Act
        var actual = success.IsSuccess(out var value);

        // Assert
        actual.Should().BeTrue();
        value.Should().Be(2);
    }

    [Fact]
    public void It_should_extract_no_error_when_inspecting_a_success_for_failure()
    {
        // Arrange
        Result<int, string> success = Result.Ok<int, string>(2);

        // Act
        var actual = success.IsFailure(out var absentError);

        // Assert
        actual.Should().BeFalse();
        absentError.Should().BeNull();
    }

    [Fact]
    public void It_should_extract_no_value_when_inspecting_a_failure_for_success()
    {
        // Arrange
        Result<int, string> failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.IsSuccess(out var absentValue);

        // Assert
        actual.Should().BeFalse();
        absentValue.Should().Be(0);
    }

    [Fact]
    public void It_should_extract_the_error_when_inspecting_a_failure()
    {
        // Arrange
        Result<int, string> failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.IsFailure(out var error);

        // Assert
        actual.Should().BeTrue();
        error.Should().Be("bad");
    }

    [Fact]
    public void It_should_map_the_value_of_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Map(x => x * 2);

        // Assert
        actual.Should().BeOk(4);
    }

    [Fact]
    public void It_should_not_map_the_value_of_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Map(x => x * 2);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_not_map_the_failure_of_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.MapFailure(errorValue => errorValue.Length);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_map_the_failure_of_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.MapFailure(errorValue => errorValue.Length);

        // Assert
        actual.Should().BeErr(3);
    }

    [Fact]
    public void It_should_get_the_value_of_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Get();

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_get_the_error_of_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.GetFailure();

        // Assert
        actual.Should().Be("bad");
    }

    [Fact]
    public void It_should_ignore_the_fallback_value_for_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.GetOr(9);

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_return_the_fallback_value_for_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.GetOr(9);

        // Assert
        actual.Should().Be(9);
    }

    [Fact]
    public void It_should_ignore_the_fallback_factory_for_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.GetOr(errorValue => errorValue.Length);

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_compute_the_fallback_from_the_error_of_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.GetOr(errorValue => errorValue.Length);

        // Assert
        actual.Should().Be(3);
    }

    [Fact]
    public void It_should_return_the_value_from_success_or_default_for_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.SuccessOrDefault(9);

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_return_the_default_from_success_or_default_for_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.SuccessOrDefault(9);

        // Assert
        actual.Should().Be(9);
    }

    [Fact]
    public void It_should_return_the_default_from_failure_or_default_for_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.FailureOrDefault("fallback");

        // Assert
        actual.Should().Be("fallback");
    }

    [Fact]
    public void It_should_return_the_error_from_failure_or_default_for_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.FailureOrDefault("fallback");

        // Assert
        actual.Should().Be("bad");
    }

    [Fact]
    public void It_should_convert_a_success_to_some_value()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Ok();

        // Assert
        actual.Should().BeSome(2);
    }

    [Fact]
    public void It_should_convert_a_success_to_no_error()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Err();

        // Assert
        actual.Should().BeNone();
    }

    [Fact]
    public void It_should_convert_a_failure_to_no_value()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Ok();

        // Assert
        actual.Should().BeNone();
    }

    [Fact]
    public void It_should_convert_a_failure_to_some_error()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Err();

        // Assert
        actual.Should().BeSome("bad");
    }

    [Fact]
    public void It_should_chain_a_success_into_the_next_result()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Then(x => Result.Ok<int, string>(x + 1));

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public void It_should_not_chain_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Then(x => Result.Ok<int, string>(x + 1));

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_chain_a_success_through_a_capturing_function()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Then(x => x + 2, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(4);
    }

    [Fact]
    public void It_should_not_chain_a_failure_through_a_capturing_function()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Then(x => x + 2, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_capture_a_matching_exception_thrown_while_chaining()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Then<int>(_ => throw new InvalidOperationException("captured"), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("captured");
    }

    [Fact]
    public void It_should_rethrow_an_unmatched_exception_thrown_while_chaining()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var uncaptured = () => success.Then<int>(_ => throw new InvalidOperationException("escaped"), Errors.MapNone, exception => exception.Message);

        // Assert
        uncaptured.Should().Throw<InvalidOperationException>().WithMessage("escaped");
    }

    [Fact]
    public void It_should_chain_a_success_through_a_capturing_action()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);
        var observed = 0;

        // Act
        var actual = success.Then(value => { observed = value; }, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(new Unit());
        observed.Should().Be(2);
    }

    [Fact]
    public void It_should_capture_a_matching_exception_thrown_by_a_chained_action()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Then(_ => throw new InvalidOperationException("action"), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("action");
    }

    [Fact]
    public void It_should_keep_a_success_when_recovering()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.OrElse(error => Result.Ok<int, string>(error.Length));

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_recover_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.OrElse(error => Result.Ok<int, string>(error.Length));

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public void It_should_run_a_side_effect_on_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);
        var observed = 0;

        // Act
        var actual = success.Do(value => observed = value);

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be(2);
    }

    [Fact]
    public void It_should_skip_a_side_effect_on_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");
        var observed = 0;

        // Act
        var actual = failure.Do(value => observed = value);

        // Assert
        actual.Should().BeErr("bad");
        observed.Should().Be(0);
    }

    [Fact]
    public void It_should_capture_a_matching_exception_thrown_by_a_side_effect()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Do(_ => throw new InvalidOperationException("side"), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("side");
    }

    [Fact]
    public void It_should_run_a_capturing_side_effect_and_keep_the_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);
        var observed = 0;

        // Act
        var actual = success.Do(value => observed = value + 1, Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be(3);
    }

    [Fact]
    public void It_should_skip_a_capturing_side_effect_on_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Do(_ => throw new InvalidOperationException(), Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_rethrow_an_unmatched_exception_thrown_by_a_side_effect()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var sideEscape = () => success.Do(_ => throw new InvalidOperationException("escaped"), Errors.MapNone, exception => exception.Message);

        // Assert
        sideEscape.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public void It_should_run_a_failure_side_effect_on_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");
        var observed = 0;

        // Act
        var actual = failure.DoFailure(error => observed = error.Length);

        // Assert
        actual.Should().BeErr("bad");
        observed.Should().Be(3);
    }

    [Fact]
    public void It_should_skip_a_failure_side_effect_on_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);
        var observed = 0;

        // Act
        var actual = success.DoFailure(error => observed = error.Length);

        // Assert
        actual.Should().BeOk(2);
        observed.Should().Be(0);
    }

    [Fact]
    public void It_should_keep_a_success_whose_result_assertion_holds()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Assert(x => Result.Ok<bool, string>(x == 2), _ => "assert");

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_fail_a_success_whose_result_assertion_is_false()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Assert(_ => Result.Ok<bool, string>(false), _ => "assert");

        // Assert
        actual.Should().BeErr("assert");
    }

    [Fact]
    public void It_should_propagate_the_error_of_a_failing_result_assertion()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Assert(_ => Result.Err<bool, string>("predicate"), _ => "assert");

        // Assert
        actual.Should().BeErr("predicate");
    }

    [Fact]
    public void It_should_not_assert_on_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Assert(_ => Result.Ok<bool, string>(true), _ => "assert");

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_keep_a_success_whose_capturing_assertion_holds()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Assert(x => x == 2, _ => "assert", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_fail_a_success_whose_capturing_assertion_is_false()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Assert(_ => false, _ => "assert", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("assert");
    }

    [Fact]
    public void It_should_capture_a_matching_exception_thrown_by_an_assertion()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Assert(_ => throw new InvalidOperationException("assert-throw"), _ => "assert", Errors.MapAll, exception => exception.Message);

        // Assert
        actual.Should().BeErr("assert-throw");
    }

    [Fact]
    public void It_should_take_the_then_branch_when_the_predicate_holds()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.If(_ => Result.Ok<bool, string>(true), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"));

        // Assert
        actual.Should().BeOk("yes2");
    }

    [Fact]
    public void It_should_take_the_else_branch_when_the_predicate_is_false()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.If(_ => Result.Ok<bool, string>(false), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"));

        // Assert
        actual.Should().BeOk("no2");
    }

    [Fact]
    public void It_should_propagate_the_error_of_a_failing_branch_predicate()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.If(_ => Result.Err<bool, string>("predicate"), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"));

        // Assert
        actual.Should().BeErr("predicate");
    }

    [Fact]
    public void It_should_not_branch_on_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.If(_ => Result.Ok<bool, string>(true), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"));

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_match_a_success_into_a_value()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Match(x => x.ToString(), error => error);

        // Assert
        actual.Should().Be("2");
    }

    [Fact]
    public void It_should_match_a_failure_into_a_value()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Match(x => x.ToString(), error => error);

        // Assert
        actual.Should().Be("bad");
    }

    [Fact]
    public void It_should_match_a_success_into_an_action()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);
        var observed = "";

        // Act
        success.Match(x => observed = x.ToString(), error => observed = error);

        // Assert
        observed.Should().Be("2");
    }

    [Fact]
    public void It_should_match_a_failure_into_an_action()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");
        var observed = "";

        // Act
        failure.Match(x => observed = x.ToString(), error => observed = error);

        // Assert
        observed.Should().Be("bad");
    }

    [Fact]
    public void It_should_fail_loudly_when_getting_the_value_of_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var getFailure = () => failure.Get();

        // Assert
        getFailure.Should().Throw<UnwrapException>()
            .Which.Should().Match<UnwrapException>(exception => exception.ExpectedVariant == "Success" && Equals(exception.ActualValue, "bad"));
    }

    [Fact]
    public void It_should_fail_loudly_when_getting_the_error_of_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var getSuccess = () => success.GetFailure();

        // Assert
        getSuccess.Should().Throw<UnwrapException>()
            .Which.Should().Match<UnwrapException>(exception => exception.ExpectedVariant == "Failure" && Equals(exception.ActualValue, 2));
    }

    [Fact]
    public void It_should_name_the_expected_variant_in_an_unwrap_exception()
    {
        // Arrange
        var subject = new UnwrapException("Some", null);

        // Act
        var actual = subject.Message;

        // Assert
        actual.Should().Contain("Some");
    }

    [Fact]
    public void It_should_explain_default_initialization_in_an_invalid_result_exception()
    {
        // Arrange
        var subject = new InvalidResultException();

        // Act
        var actual = subject.Message;

        // Assert
        actual.Should().Contain("default-initialized");
    }

    [Fact]
    public void It_should_fail_loudly_when_inspecting_a_default_result()
    {
        // Arrange
        var invalid = default(Result<int, string>);

        // Act
        var inspect = () => invalid.IsSuccess();

        // Assert
        inspect.Should().Throw<InvalidResultException>();
    }

    [Fact]
    public void It_should_fail_loudly_when_comparing_a_default_result()
    {
        // Arrange
        var invalid = default(Result<int, string>);
        var success = Result.Ok<int, string>(2);

        // Act
        var equality = () => invalid.Equals(success);

        // Assert
        equality.Should().Throw<InvalidResultException>();
    }

    [Fact]
    public void It_should_convert_a_value_implicitly_into_an_equal_success()
    {
        // Arrange
        Result<int, string> success = 2;
        var twin = Result.Ok<int, string>(2);

        // Act
        var actual = success == twin;

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_treat_a_success_and_an_implicit_failure_as_unequal()
    {
        // Arrange
        Result<int, string> success = 2;
        Result<int, string> failure = "bad";

        // Act
        var actual = success != failure;

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_equal_a_boxed_twin()
    {
        // Arrange
        Result<int, string> success = 2;
        var twin = Result.Ok<int, string>(2);

        // Act
        var actual = success.Equals((object)twin);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_equal_an_object_that_is_not_a_result()
    {
        // Arrange
        Result<int, string> success = 2;

        // Act
        var actual = success.Equals("not a result");

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_share_a_hash_code_with_an_equal_result()
    {
        // Arrange
        Result<int, string> success = 2;
        var twin = Result.Ok<int, string>(2);

        // Act
        var actual = success.GetHashCode();

        // Assert
        actual.Should().Be(twin.GetHashCode());
    }

    [Fact]
    public void It_should_describe_a_success()
    {
        // Arrange
        Result<int, string> success = 2;

        // Act
        var actual = success.ToString();

        // Assert
        actual.Should().Be("Success(2)");
    }

    [Fact]
    public void It_should_describe_a_failure()
    {
        // Arrange
        Result<int, string> failure = "bad";

        // Act
        var actual = failure.ToString();

        // Assert
        actual.Should().Be("Failure(bad)");
    }

    [Fact]
    public void It_should_give_different_variants_different_hash_codes()
    {
        // Arrange
        Result<int, string> success = 2;
        Result<int, string> failure = "bad";

        // Act
        var actual = failure.GetHashCode();

        // Assert
        actual.Should().NotBe(success.GetHashCode());
    }

    [Fact]
    public void It_should_map_every_exception_with_map_all()
    {
        // Arrange
        var exception = new Exception();

        // Act
        var actual = Errors.MapAll(exception);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_map_no_exception_with_map_none()
    {
        // Arrange
        var exception = new Exception();

        // Act
        var actual = Errors.MapNone(exception);

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_match_the_first_type_of_a_composed_filter()
    {
        // Arrange
        var filter = Errors.MapIfExceptionIs<InvalidOperationException>().Or<ArgumentException>();

        // Act
        var actual = filter(new InvalidOperationException());

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_match_the_second_type_of_a_composed_filter()
    {
        // Arrange
        var filter = Errors.MapIfExceptionIs<InvalidOperationException>().Or<ArgumentException>();

        // Act
        var actual = filter(new ArgumentException());

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_match_other_types_with_a_composed_filter()
    {
        // Arrange
        var filter = Errors.MapIfExceptionIs<InvalidOperationException>().Or<ArgumentException>();

        // Act
        var actual = filter(new IOException());

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_reject_composing_a_null_filter()
    {
        // Act
        var act = () => Errors.Or<Exception>(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_chain_a_success_through_a_function_capturing_exceptions_as_is()
    {
        // Arrange
        Result<int, Exception> success = Result.Ok<int, Exception>(2);

        // Act
        var actual = success.Then(value => value + 1, Errors.MapAll);

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public void It_should_chain_a_success_through_an_action_capturing_exceptions_as_is()
    {
        // Arrange
        Result<int, Exception> success = Result.Ok<int, Exception>(2);

        // Act
        var actual = success.Then(value => { _ = value; }, Errors.MapAll);

        // Assert
        actual.Should().BeOk(new Unit());
    }

    [Fact]
    public void It_should_capture_a_side_effect_exception_as_is()
    {
        // Arrange
        Result<int, Exception> success = Result.Ok<int, Exception>(2);

        // Act
        var actual = success.Do(_ => throw new InvalidOperationException("side"), Errors.MapAll);

        // Assert
        actual.Should().BeErr()
            .Which.Message.Should().Be("side");
    }

    [Fact]
    public void It_should_keep_a_success_whose_assertion_holds_capturing_exceptions_as_is()
    {
        // Arrange
        Result<int, Exception> success = Result.Ok<int, Exception>(2);

        // Act
        var actual = success.Assert(value => value == 2, Errors.MapAll);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_fail_a_false_assertion_with_an_assertion_exception()
    {
        // Arrange
        Result<int, Exception> success = Result.Ok<int, Exception>(2);

        // Act
        var actual = success.Assert(_ => false, Errors.MapAll, "assertion");

        // Assert
        actual.Should().BeErr()
            .Which.Should().BeOfType<AssertionException>().Which.Message.Should().Be("assertion");
    }

    [Fact]
    public void It_should_give_a_default_assertion_exception_a_message()
    {
        // Arrange
        var subject = new AssertionException();

        // Act
        var actual = subject.Message;

        // Assert
        actual.Should().NotBeNull();
    }

    [Fact]
    public void It_should_try_a_function_that_returns()
    {
        // Act
        var actual = Result.Try(() => 2);

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_capture_the_exception_of_a_tried_function()
    {
        // Act
        var actual = Result.Try<int>(() => throw new InvalidOperationException("bad"));

        // Assert
        actual.Should().BeErr()
            .Which.Should().BeOfType<InvalidOperationException>();
    }

    [Fact]
    public void It_should_rethrow_an_unmatched_exception_of_a_tried_function()
    {
        // Act
        var escaped = () => Result.Try<int>(() => throw new InvalidOperationException(), Errors.MapNone);

        // Assert
        escaped.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public async Task It_should_try_an_async_function_that_returns()
    {
        // Act
        var actual = await Result.TryAsync(() => Task.FromResult(3));

        // Assert
        actual.Should().BeOk(3);
    }

    [Fact]
    public async Task It_should_capture_the_exception_of_a_tried_async_function()
    {
        // Act
        var actual = await Result.TryAsync<int>(() => Task.FromException<int>(new InvalidOperationException("async")));

        // Assert
        actual.Should().BeErr()
            .Which.Should().BeOfType<InvalidOperationException>();
    }

    [Fact]
    public async Task It_should_rethrow_an_unmatched_exception_of_a_tried_async_function()
    {
        // Act
        var asyncEscape = async () => await Result.TryAsync<int>(() => Task.FromException<int>(new InvalidOperationException()), Errors.MapNone);

        // Assert
        await asyncEscape.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public void It_should_combine_successes_into_all_values()
    {
        // Arrange
        Result<int, string>[] successfulResults = [Result.Ok<int, string>(1), Result.Ok<int, string>(2)];

        // Act
        var actual = Result.All(successfulResults);

        // Assert
        actual.Should().BeOk()
            .Which.Should().Equal(1, 2);
    }

    [Fact]
    public void It_should_combine_mixed_results_into_all_errors()
    {
        // Arrange
        Result<int, string>[] mixedResults = [Result.Ok<int, string>(1), Result.Err<int, string>("a"), Result.Err<int, string>("b")];

        // Act
        var actual = Result.All(mixedResults);

        // Assert
        actual.Should().BeErr()
            .Which.Should().Equal("a", "b");
    }

    [Fact]
    public async Task It_should_combine_async_successes()
    {
        // Arrange
        Task<Result<int, string>>[] asyncResults = [Task.FromResult(Result.Ok<int, string>(1)), Task.FromResult(Result.Ok<int, string>(2))];

        // Act
        var actual = await Result.All(asyncResults);

        // Assert
        actual.Should().BeOk();
    }

    [Fact]
    public void It_should_combine_two_successes_into_a_tuple()
    {
        // Arrange
        var first = Result.Ok<int, string>(1);
        var second = Result.Ok<string, string>("two");

        // Act
        var actual = Result.All(first, second);

        // Assert
        actual.Should().BeOk((1, "two"));
    }

    [Fact]
    public void It_should_combine_two_failures_into_all_errors()
    {
        // Arrange
        var first = Result.Err<int, string>("one");
        var second = Result.Err<string, string>("two");

        // Act
        var actual = Result.All(first, second);

        // Assert
        actual.Should().BeErr()
            .Which.Should().Equal("one", "two");
    }

    [Fact]
    public void It_should_combine_three_successes_into_a_tuple()
    {
        // Arrange
        var first = Result.Ok<int, string>(1);
        var second = Result.Ok<string, string>("two");
        var third = Result.Ok<bool, string>(true);

        // Act
        var actual = Result.All(first, second, third);

        // Assert
        actual.Should().BeOk((1, "two", true));
    }

    [Fact]
    public void It_should_combine_three_mixed_results_into_all_errors()
    {
        // Arrange
        var first = Result.Ok<int, string>(1);
        var second = Result.Err<string, string>("two");
        var third = Result.Err<bool, string>("three");

        // Act
        var actual = Result.All(first, second, third);

        // Assert
        actual.Should().BeErr()
            .Which.Should().Equal("two", "three");
    }

    [Fact]
    public void It_should_project_the_successes_of_a_collection()
    {
        // Arrange
        var results = new[] { Result.Ok<int, string>(1), Result.Err<int, string>("bad"), Result.Ok<int, string>(3) };

        // Act
        var actual = results.GetSuccesses();

        // Assert
        actual.Should().Equal(1, 3);
    }

    [Fact]
    public void It_should_project_the_failures_of_a_collection()
    {
        // Arrange
        var results = new[] { Result.Ok<int, string>(1), Result.Err<int, string>("bad"), Result.Ok<int, string>(3) };

        // Act
        var actual = results.GetFailures();

        // Assert
        actual.Should().Equal("bad");
    }

    [Fact]
    public void It_should_not_report_a_mixed_collection_as_all_succeeding()
    {
        // Arrange
        var results = new[] { Result.Ok<int, string>(1), Result.Err<int, string>("bad"), Result.Ok<int, string>(3) };

        // Act
        var actual = results.AllSucceed();

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_report_a_mixed_collection_as_any_succeeding()
    {
        // Arrange
        var results = new[] { Result.Ok<int, string>(1), Result.Err<int, string>("bad"), Result.Ok<int, string>(3) };

        // Act
        var actual = results.AnySucceed();

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_report_an_all_failed_collection_as_any_succeeding()
    {
        // Arrange
        var results = new[] { Result.Err<int, string>("bad") };

        // Act
        var actual = results.AnySucceed();

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_report_an_all_successful_collection_as_all_succeeding()
    {
        // Arrange
        var results = new[] { Result.Ok<int, string>(1) };

        // Act
        var actual = results.AllSucceed();

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_compose_successes_with_query_syntax()
    {
        // Arrange
        var left = Result.Ok<int, string>(2);
        var right = Result.Ok<int, string>(3);

        // Act
        var actual = from l in left
                     from r in right
                     select l + r;

        // Assert
        actual.Should().BeOk(5);
    }

    [Fact]
    public void It_should_not_select_from_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Select(value => value * 2);

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_treat_two_units_as_equal()
    {
        // Arrange
        var left = new Unit();
        var right = new Unit();

        // Act
        var actual = left.Equals(right);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_treat_a_boxed_unit_as_equal()
    {
        // Arrange
        var left = new Unit();
        var right = new Unit();

        // Act
        var actual = left.Equals((object)right);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_treat_a_unit_as_equal_to_another_type()
    {
        // Arrange
        var left = new Unit();

        // Act
        var actual = left.Equals("unit");

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_give_a_unit_a_zero_hash_code()
    {
        // Arrange
        var left = new Unit();

        // Act
        var actual = left.GetHashCode();

        // Assert
        actual.Should().Be(0);
    }

    [Fact]
    public void It_should_describe_a_unit_as_empty_parentheses()
    {
        // Arrange
        var left = new Unit();

        // Act
        var actual = left.ToString();

        // Assert
        actual.Should().Be("()");
    }

    [Fact]
    public void It_should_compare_units_as_equal_with_the_equality_operator()
    {
        // Arrange
        var left = new Unit();
        var right = new Unit();

        // Act
        var actual = left == right;

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_compare_units_as_not_unequal_with_the_inequality_operator()
    {
        // Arrange
        var left = new Unit();
        var right = new Unit();

        // Act
        var actual = left != right;

        // Assert
        actual.Should().BeFalse();
    }
}
