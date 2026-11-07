/// Sealed [Result] and [Option] values with a cross-language wire codec.
///
/// The error channel uses `Problem` from `package:diene_problems`; that
/// canonical type is deliberately not re-exported from this library.
library;

export 'src/option.dart';
export 'src/result.dart';
export 'src/unwrap_error.dart';
export 'src/wire.dart' show OptionSerial, ResultSerial;
