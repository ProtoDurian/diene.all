using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest;

public class TestHelperTests
{
    [Fact]
    public void Result_assertions_should_expose_the_subject()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Should().Subject;

        // Assert
        actual.Equals(success).Should().BeTrue();
    }

    [Fact]
    public void Result_assertions_should_yield_the_value_of_a_success()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var actual = success.Should().BeOk();

        // Assert
        actual.Which.Should().Be(2);
    }

    [Fact]
    public void Result_assertions_should_accept_a_success_with_the_expected_value()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var act = () => success.Should().BeOk(2);

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void Result_assertions_should_yield_the_error_of_a_failure()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var actual = failure.Should().BeErr();

        // Assert
        actual.Which.Should().Be("bad");
    }

    [Fact]
    public void Result_assertions_should_accept_a_failure_with_the_expected_error()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var act = () => failure.Should().BeErr(expected: "bad");

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void Result_assertions_should_reject_a_success_expected_to_be_a_failure()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var wrongVariant = () => success.Should().BeErr("because {0}", "test");

        // Assert
        wrongVariant.Should().Throw<Exception>().WithMessage("*because test*");
    }

    [Fact]
    public void Result_assertions_should_reject_a_success_with_another_value()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var wrongValue = () => success.Should().BeOk(3);

        // Assert
        wrongValue.Should().Throw<Exception>();
    }

    [Fact]
    public void Result_assertions_should_reject_a_failure_expected_to_be_a_success()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var wrongSuccess = () => failure.Should().BeOk();

        // Assert
        wrongSuccess.Should().Throw<Exception>();
    }

    [Fact]
    public void Result_assertions_should_reject_a_failure_with_another_error()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var wrongError = () => failure.Should().BeErr(expected: "other");

        // Assert
        wrongError.Should().Throw<Exception>();
    }

    [Fact]
    public void Option_assertions_should_expose_the_subject()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Should().Subject;

        // Assert
        actual.Equals(some).Should().BeTrue();
    }

    [Fact]
    public void Option_assertions_should_yield_the_value_of_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Should().BeSome();

        // Assert
        actual.Which.Should().Be(2);
    }

    [Fact]
    public void Option_assertions_should_accept_some_with_the_expected_value()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var act = () => some.Should().BeSome(2);

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void Option_assertions_should_accept_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var act = () => none.Should().BeNone();

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void Option_assertions_should_reject_some_expected_to_be_none()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var wrongNone = () => some.Should().BeNone("because {0}", "test");

        // Assert
        wrongNone.Should().Throw<Exception>().WithMessage("*because test*");
    }

    [Fact]
    public void Option_assertions_should_reject_none_expected_to_be_some()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var wrongSome = () => none.Should().BeSome();

        // Assert
        wrongSome.Should().Throw<Exception>();
    }

    [Fact]
    public void Option_assertions_should_reject_some_with_another_value()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var wrongValue = () => some.Should().BeSome(3);

        // Assert
        wrongValue.Should().Throw<Exception>();
    }

    [Fact]
    public async Task Task_assertions_should_yield_the_value_of_a_success()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var actual = await success.Should().BeOkAsync();

        // Assert
        actual.Which.Should().Be(2);
    }

    [Fact]
    public async Task Task_assertions_should_yield_the_error_of_a_failure()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var actual = await failure.Should().BeErrAsync();

        // Assert
        actual.Which.Should().Be("bad");
    }

    [Fact]
    public async Task Task_assertions_should_reject_a_failure_expected_to_be_a_success()
    {
        // Arrange
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        // Act
        var wrongSuccess = async () => await failure.Should().BeOkAsync("because {0}", "test");

        // Assert
        await wrongSuccess.Should().ThrowAsync<Exception>().WithMessage("*because test*");
    }

    [Fact]
    public async Task Task_assertions_should_reject_a_success_expected_to_be_a_failure()
    {
        // Arrange
        var success = Task.FromResult(Result.Ok<int, string>(2));

        // Act
        var wrongFailure = async () => await success.Should().BeErrAsync();

        // Assert
        await wrongFailure.Should().ThrowAsync<Exception>();
    }
}
