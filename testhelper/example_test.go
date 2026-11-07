package testhelper_test

import (
	"errors"
	"fmt"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
	"github.com/ProtoDurian/diene.go-errors-problems/testhelper"
)

type recordT struct{ message string }

func (*recordT) Helper() {}

func (r *recordT) Fatalf(format string, args ...any) { r.message = fmt.Sprintf(format, args...) }

func loadUser() (string, error) {
	return "", problem.NewError(testhelper.SampleProblem())
}

func ExampleTestingT() {
	// Arrange
	recorder := &recordT{}
	var t testhelper.TestingT = recorder

	// Act
	testhelper.AssertProblem(t, testhelper.SampleProblem(), testhelper.ExpectStatus(500))

	// Assert
	fmt.Println(recorder.message)
	// Output: problem assertion failed: status mismatch: expected 500, got 404
}

func ExampleOption() {
	// Arrange
	options := []testhelper.Option{testhelper.ExpectStatus(404), testhelper.ExpectID("entity_not_found")}

	// Act
	err := testhelper.CheckProblem(testhelper.SampleProblem(), options...)

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleExpectType() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectType("https://other"))

	// Assert
	fmt.Println(err != nil)
	// Output: true
}

func ExampleExpectID() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectID("entity_not_found"))

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleExpectTitle() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectTitle("Entity Not Found"))

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleExpectStatus() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectStatus(409))

	// Assert
	fmt.Println(err)
	// Output: status mismatch: expected 409, got 404
}

func ExampleExpectRecoverable() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectRecoverable(false))

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleExpectDetail() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectDetail("User 42 does not exist"))

	// Assert
	fmt.Println(err)
	// Output: detail mismatch: expected "User 42 does not exist", got <nil>
}

func ExampleExpectInstance() {
	// Arrange
	sample := testhelper.SampleProblem()
	instance := "/user/42"
	sample.Instance = &instance

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectInstance("/user/42"))

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleExpectData() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectData(map[string]any{"entityType": "user", "id": "42"}))

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleCheckProblem() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	err := testhelper.CheckProblem(sample, testhelper.ExpectStatus(404), testhelper.ExpectTitle("Wrong"))

	// Assert
	fmt.Println(err)
	// Output: title mismatch: expected "Wrong", got "Entity Not Found"
}

func ExampleAssertProblem() {
	// Arrange
	sample := testhelper.SampleProblem()
	recorder := &recordT{}

	// Act
	testhelper.AssertProblem(recorder, sample, testhelper.ExpectID("conflict"))

	// Assert
	fmt.Println(recorder.message)
	// Output: problem assertion failed: id mismatch: expected "conflict", got "entity_not_found" (from type "https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found")
}

func ExampleCheckError() {
	// Arrange
	_, err := loadUser()

	// Act
	envelope, checkErr := testhelper.CheckError(err, testhelper.ExpectID("entity_not_found"), testhelper.ExpectStatus(404))

	// Assert
	fmt.Println(checkErr, envelope.Title)
	// Output: <nil> Entity Not Found
}

func ExampleAssertError() {
	// Arrange
	err := errors.New("plain")
	recorder := &recordT{}

	// Act
	testhelper.AssertError(recorder, err)

	// Assert
	fmt.Println(recorder.message)
	// Output: problem-error assertion failed: expected a *problem.Error, got *errors.errorString
}

func ExampleSampleErrorPortal() {
	// Arrange
	portal := testhelper.SampleErrorPortal()

	// Act
	uri, _ := problem.TypeURI(portal, "v1", "conflict")

	// Assert
	fmt.Println(uri)
	// Output: https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/conflict
}

func ExampleSampleProblem() {
	// Arrange
	sample := testhelper.SampleProblem()

	// Act
	wire, _ := sample.MarshalJSON()

	// Assert
	fmt.Println(string(wire))
	// Output: {"data":{"entityType":"user","id":"42"},"recoverable":false,"status":404,"title":"Entity Not Found","type":"https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found"}
}
