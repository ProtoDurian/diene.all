using System.Text.Json;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OptionSerialTests
{
    [Fact]
    public void It_should_report_some_as_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.IsSome();

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_report_some_as_none()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.IsNone();

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_extract_the_value_when_inspecting_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.IsSome(out var value);

        // Assert
        actual.Should().BeTrue();
        value.Should().Be(2);
    }

    [Fact]
    public void It_should_extract_no_value_when_inspecting_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.IsSome(out var absent);

        // Assert
        actual.Should().BeFalse();
        absent.Should().Be(0);
    }

    [Fact]
    public void It_should_report_none_as_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.IsNone();

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_map_the_value_of_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Map(x => x * 2);

        // Assert
        actual.Should().BeSome(4);
    }

    [Fact]
    public void It_should_not_map_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.Map(x => x * 2);

        // Assert
        actual.Should().BeNone();
    }

    [Fact]
    public void It_should_chain_some_into_the_next_option()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Then(x => Option.Some(x.ToString()));

        // Assert
        actual.Should().BeSome("2");
    }

    [Fact]
    public void It_should_not_chain_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.Then(x => Option.Some(x.ToString()));

        // Assert
        actual.Should().BeNone();
    }

    [Fact]
    public void It_should_match_some_into_a_value()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Match(x => x.ToString(), () => "none");

        // Assert
        actual.Should().Be("2");
    }

    [Fact]
    public void It_should_match_none_into_a_value()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.Match(x => x.ToString(), () => "none");

        // Assert
        actual.Should().Be("none");
    }

    [Fact]
    public void It_should_get_the_value_of_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Get();

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_ignore_the_fallback_value_for_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.GetOr(9);

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_return_the_fallback_value_for_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.GetOr(9);

        // Assert
        actual.Should().Be(9);
    }

    [Fact]
    public void It_should_ignore_the_fallback_factory_for_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.GetOr(() => 9);

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_compute_the_fallback_factory_for_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.GetOr(() => 9);

        // Assert
        actual.Should().Be(9);
    }

    [Fact]
    public void It_should_convert_some_to_its_value()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.ToNullable();

        // Assert
        actual.Should().Be(2);
    }

    [Fact]
    public void It_should_convert_none_to_the_default_value()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.ToNullable();

        // Assert
        actual.Should().Be(0);
    }

    [Fact]
    public void It_should_convert_some_to_a_success()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.OkOr("bad");

        // Assert
        actual.Should().BeOk(2);
    }

    [Fact]
    public void It_should_convert_none_to_a_failure()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.OkOr("bad");

        // Assert
        actual.Should().BeErr("bad");
    }

    [Fact]
    public void It_should_create_none_from_null()
    {
        // Arrange
        string? input = null;

        // Act
        var actual = Option.FromNullable<string>(input);

        // Assert
        actual.Should().BeNone();
    }

    [Fact]
    public void It_should_create_some_from_a_non_null_value()
    {
        // Arrange
        var input = "value";

        // Act
        var actual = Option.FromNullable(input);

        // Assert
        actual.Should().BeSome("value");
    }

    [Fact]
    public void It_should_fail_loudly_when_getting_the_value_of_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var get = () => none.Get();

        // Assert
        get.Should().Throw<UnwrapException>().Which.ExpectedVariant.Should().Be("Some");
    }

    [Fact]
    public void It_should_compare_equal_options_with_the_equality_operator()
    {
        // Arrange
        var some = Option.Some(2);
        var twin = Option.Some(2);

        // Act
        var actual = some == twin;

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_compare_some_and_none_with_the_inequality_operator()
    {
        // Arrange
        var some = Option.Some(2);
        var none = Option.None<int>();

        // Act
        var actual = some != none;

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_equal_a_boxed_twin_option()
    {
        // Arrange
        var some = Option.Some(2);
        var twin = Option.Some(2);

        // Act
        var actual = some.Equals((object)twin);

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_equal_an_object_that_is_not_an_option()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.Equals("not option");

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_share_a_hash_code_with_an_equal_option()
    {
        // Arrange
        var some = Option.Some(2);
        var twin = Option.Some(2);

        // Act
        var actual = some.GetHashCode();

        // Assert
        actual.Should().Be(twin.GetHashCode());
    }

    [Fact]
    public void It_should_describe_some()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var actual = some.ToString();

        // Assert
        actual.Should().Be("Some(2)");
    }

    [Fact]
    public void It_should_describe_none()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var actual = none.ToString();

        // Assert
        actual.Should().Be("None");
    }

    [Fact]
    public void It_should_fail_loudly_when_inspecting_a_default_option()
    {
        // Arrange
        var invalid = default(Option<int>);

        // Act
        var inspect = () => invalid.IsSome();

        // Assert
        inspect.Should().Throw<InvalidResultException>();
    }

    [Fact]
    public void It_should_fail_loudly_when_comparing_a_default_option()
    {
        // Arrange
        var invalid = default(Option<int>);
        var some = Option.Some(2);

        // Act
        var equality = () => invalid.Equals(some);

        // Assert
        equality.Should().Throw<InvalidResultException>();
    }

    [Fact]
    public void It_should_serialize_a_success_like_the_c0_fixture()
    {
        // Arrange
        var expected = FixtureCase("ok");

        // Act
        var okJson = JsonSerializer.Serialize(Result.Ok<int, string>(42).ToSerial());

        // Assert
        JsonElement.DeepEquals(JsonDocument.Parse(okJson).RootElement, expected).Should().BeTrue();
    }

    [Fact]
    public void It_should_serialize_a_failure_like_the_c0_fixture()
    {
        // Arrange
        var expected = FixtureCase("err");

        // Act
        var errJson = JsonSerializer.Serialize(Result.Err<int, string>("boom").ToSerial());

        // Assert
        JsonElement.DeepEquals(JsonDocument.Parse(errJson).RootElement, expected).Should().BeTrue();
    }

    [Fact]
    public void It_should_serialize_some_like_the_c0_fixture()
    {
        // Arrange
        var expected = FixtureCase("some");

        // Act
        var someJson = JsonSerializer.Serialize(Option.Some("value").ToSerial());

        // Assert
        JsonElement.DeepEquals(JsonDocument.Parse(someJson).RootElement, expected).Should().BeTrue();
    }

    [Fact]
    public void It_should_serialize_none_like_the_c0_fixture()
    {
        // Arrange
        var expected = FixtureCase("none");

        // Act
        var noneJson = JsonSerializer.Serialize(Option.None<string>().ToSerial());

        // Assert
        JsonElement.DeepEquals(JsonDocument.Parse(noneJson).RootElement, expected).Should().BeTrue();
    }

    [Fact]
    public void It_should_round_trip_a_serialized_success()
    {
        // Arrange
        var okJson = JsonSerializer.Serialize(Result.Ok<int, string>(42).ToSerial());

        // Act
        var actual = Result.FromSerial(JsonSerializer.Deserialize<ResultSerial<int, string>>(okJson)!);

        // Assert
        actual.Should().BeOk(42);
    }

    [Fact]
    public void It_should_round_trip_a_serialized_failure()
    {
        // Arrange
        var errJson = JsonSerializer.Serialize(Result.Err<int, string>("boom").ToSerial());

        // Act
        var actual = Result.FromSerial(JsonSerializer.Deserialize<ResultSerial<int, string>>(errJson)!);

        // Assert
        actual.Should().BeErr("boom");
    }

    [Fact]
    public void It_should_round_trip_a_serialized_some()
    {
        // Arrange
        var someJson = JsonSerializer.Serialize(Option.Some("value").ToSerial());

        // Act
        var actual = Option.FromSerial(JsonSerializer.Deserialize<OptionSerial<string>>(someJson)!);

        // Assert
        actual.Should().BeSome("value");
    }

    [Fact]
    public void It_should_round_trip_a_serialized_none()
    {
        // Arrange
        var noneJson = JsonSerializer.Serialize(Option.None<string>().ToSerial());

        // Act
        var actual = Option.FromSerial(JsonSerializer.Deserialize<OptionSerial<string>>(noneJson)!);

        // Assert
        actual.Should().BeNone();
    }

    [Fact]
    public void It_should_match_a_serial_success()
    {
        // Arrange
        var subject = ResultSerial<int, string>.Ok(4);

        // Act
        var actual = subject.Match(value => value, _ => 0);

        // Assert
        actual.Should().Be(4);
    }

    [Fact]
    public void It_should_match_a_serial_failure()
    {
        // Arrange
        var subject = ResultSerial<int, string>.Err("bad");

        // Act
        var actual = subject.Match(value => value, error => error.Length);

        // Assert
        actual.Should().Be(3);
    }

    [Fact]
    public void It_should_match_a_serial_some()
    {
        // Arrange
        var subject = OptionSerial<int>.Some(5);

        // Act
        var actual = subject.Match(value => value, () => 0);

        // Assert
        actual.Should().Be(5);
    }

    [Fact]
    public void It_should_match_a_serial_none()
    {
        // Arrange
        var subject = OptionSerial<int>.None();

        // Act
        var actual = subject.Match(value => value, () => 0);

        // Assert
        actual.Should().Be(0);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("[\"wat\",1]")]
    [InlineData("[\"ok\"]")]
    [InlineData("[\"ok\",1,2]")]
    public void It_should_reject_malformed_result_serial(string json)
    {
        // Act
        var act = () => JsonSerializer.Deserialize<ResultSerial<int, string>>(json);

        // Assert
        act.Should().Throw<JsonException>();
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("[\"wat\",null]")]
    [InlineData("[\"none\",1]")]
    [InlineData("[\"some\"]")]
    [InlineData("[\"some\",1,2]")]
    public void It_should_reject_malformed_option_serial(string json)
    {
        // Act
        var act = () => JsonSerializer.Deserialize<OptionSerial<int>>(json);

        // Assert
        act.Should().Throw<JsonException>();
    }

    [Fact]
    public void It_should_let_the_serial_factory_convert_result_serials()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var actual = subject.CanConvert(typeof(ResultSerial<int, string>));

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_let_the_serial_factory_convert_option_serials()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var actual = subject.CanConvert(typeof(OptionSerial<int>));

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_let_the_serial_factory_convert_other_types()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var actual = subject.CanConvert(typeof(string));

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_create_a_result_serial_converter()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var actual = subject.CreateConverter(typeof(ResultSerial<int, string>), new JsonSerializerOptions());

        // Assert
        actual.Should().NotBeNull();
    }

    [Fact]
    public void It_should_create_an_option_serial_converter()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var actual = subject.CreateConverter(typeof(OptionSerial<int>), new JsonSerializerOptions());

        // Assert
        actual.Should().NotBeNull();
    }

    [Fact]
    public void It_should_reject_a_null_type_in_the_serial_factory()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var nullType = () => subject.CreateConverter(null!, new JsonSerializerOptions());

        // Assert
        nullType.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_null_options_in_the_serial_factory()
    {
        // Arrange
        var subject = new MonadSerialJsonConverterFactory();

        // Act
        var nullOptions = () => subject.CreateConverter(typeof(OptionSerial<int>), null!);

        // Assert
        nullOptions.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_let_the_result_value_factory_convert_results()
    {
        // Arrange
        var valueFactory = new ResultValueJsonConverterFactory();

        // Act
        var actual = valueFactory.CanConvert(typeof(Result<int, string>));

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_let_the_result_value_factory_convert_other_types()
    {
        // Arrange
        var valueFactory = new ResultValueJsonConverterFactory();

        // Act
        var actual = valueFactory.CanConvert(typeof(string));

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_create_a_result_value_converter()
    {
        // Arrange
        var valueFactory = new ResultValueJsonConverterFactory();

        // Act
        var actual = valueFactory.CreateConverter(typeof(Result<int, string>), new JsonSerializerOptions());

        // Assert
        actual.Should().NotBeNull();
    }

    [Fact]
    public void It_should_reject_a_null_type_in_the_result_value_factory()
    {
        // Arrange
        var valueFactory = new ResultValueJsonConverterFactory();

        // Act
        var nullValueType = () => valueFactory.CreateConverter(null!, new JsonSerializerOptions());

        // Assert
        nullValueType.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_null_options_in_the_result_value_factory()
    {
        // Arrange
        var valueFactory = new ResultValueJsonConverterFactory();

        // Act
        var nullValueOptions = () => valueFactory.CreateConverter(typeof(Result<int, string>), null!);

        // Assert
        nullValueOptions.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_refuse_to_serialize_a_success_directly()
    {
        // Arrange
        var success = Result.Ok<int, string>(2);

        // Act
        var serializeValue = () => JsonSerializer.Serialize(success);

        // Assert
        serializeValue.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
    }

    [Fact]
    public void It_should_refuse_to_deserialize_a_result_directly()
    {
        // Arrange
        var json = "[\"ok\",2]";

        // Act
        var deserializeValue = () => JsonSerializer.Deserialize<Result<int, string>>(json);

        // Assert
        deserializeValue.Should().Throw<NotSupportedException>().WithMessage("*ResultSerial*");
    }

    [Fact]
    public void It_should_let_the_option_value_factory_convert_options()
    {
        // Arrange
        var optionValueFactory = new OptionValueJsonConverterFactory();

        // Act
        var actual = optionValueFactory.CanConvert(typeof(Option<int>));

        // Assert
        actual.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_let_the_option_value_factory_convert_other_types()
    {
        // Arrange
        var optionValueFactory = new OptionValueJsonConverterFactory();

        // Act
        var actual = optionValueFactory.CanConvert(typeof(string));

        // Assert
        actual.Should().BeFalse();
    }

    [Fact]
    public void It_should_create_an_option_value_converter()
    {
        // Arrange
        var optionValueFactory = new OptionValueJsonConverterFactory();

        // Act
        var actual = optionValueFactory.CreateConverter(typeof(Option<int>), new JsonSerializerOptions());

        // Assert
        actual.Should().NotBeNull();
    }

    [Fact]
    public void It_should_reject_a_null_type_in_the_option_value_factory()
    {
        // Arrange
        var optionValueFactory = new OptionValueJsonConverterFactory();

        // Act
        var nullOptionValueType = () => optionValueFactory.CreateConverter(null!, new JsonSerializerOptions());

        // Assert
        nullOptionValueType.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_null_options_in_the_option_value_factory()
    {
        // Arrange
        var optionValueFactory = new OptionValueJsonConverterFactory();

        // Act
        var nullOptionValueOptions = () => optionValueFactory.CreateConverter(typeof(Option<int>), null!);

        // Assert
        nullOptionValueOptions.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_refuse_to_serialize_some_directly()
    {
        // Arrange
        var some = Option.Some(2);

        // Act
        var serializeSome = () => JsonSerializer.Serialize(some);

        // Assert
        serializeSome.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
    }

    [Fact]
    public void It_should_refuse_to_serialize_none_directly()
    {
        // Arrange
        var none = Option.None<int>();

        // Act
        var serializeNone = () => JsonSerializer.Serialize(none);

        // Assert
        serializeNone.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
    }

    [Fact]
    public void It_should_refuse_to_deserialize_an_option_directly()
    {
        // Arrange
        var json = "[\"some\",2]";

        // Act
        var deserializeOption = () => JsonSerializer.Deserialize<Option<int>>(json);

        // Assert
        deserializeOption.Should().Throw<NotSupportedException>().WithMessage("*OptionSerial*");
    }

    [Fact]
    public void It_should_refuse_to_serialize_a_failure_directly()
    {
        // Arrange
        var failure = Result.Err<int, string>("bad");

        // Act
        var serializeFailure = () => JsonSerializer.Serialize(failure);

        // Assert
        serializeFailure.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
    }

    private static JsonElement FixtureCase(string name)
    {
        var fixturePath = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "monad-v1.json");
        using var document = JsonDocument.Parse(File.ReadAllText(fixturePath));
        return document.RootElement.GetProperty("cases").GetProperty(name).Clone();
    }
}
