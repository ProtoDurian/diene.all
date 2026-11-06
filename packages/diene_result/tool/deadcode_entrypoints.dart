// Production dead-code root: references every public export.
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';

Future<void> main() async {
  final Problem problem = Problem(
    type: 'about:blank',
    title: 'Dead-code entrypoint',
    status: 500,
  );

  expectOk(const Result<int>.ok(1));
  expectErr<int>(Result<int>.err(problem));
  expectSome(const Option<int>.some(1));
  expectNone(const Option<int>.none());
  expectOk(const Option<Problem>.none().errOr(1));
  expectOk(await Future<Result<int>>.value(const Ok<int>(1)).map((int v) => v));
}
