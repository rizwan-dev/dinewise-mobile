/// The one error type every API call throws.
///
/// The server answers every failure with `{"error": {"code", "message", "field"?}}`. [code] is
/// stable and safe to switch on; [message] is written for the person using the app and is shown
/// as it is. Failures that never reached the server (no network, timeout, a body that is not the
/// error shape) get a client-side [code] from [ApiErrorCode] and a friendly message.
class ApiException implements Exception {
  const ApiException({required this.status, required this.code, required this.message, this.field});

  /// Builds the exception from a failed response's status and decoded JSON body.
  factory ApiException.fromResponse(int status, Object? body) {
    if (body is Map<String, Object?>) {
      final error = body['error'];
      if (error is Map<String, Object?>) {
        final code = error['code'];
        final message = error['message'];
        if (code is String && message is String) {
          return ApiException(status: status, code: code, message: message, field: error['field'] as String?);
        }
      }
    }
    return ApiException(status: status, code: _fallbackCode(status), message: _fallbackMessage(status));
  }

  /// The request never got an answer: offline, DNS, timeout, connection reset.
  const ApiException.network([String? detail])
    : status = 0,
      code = ApiErrorCode.network,
      message = 'Could not reach Tadka Lane. Check your connection and try again.',
      field = detail;

  /// HTTP status, or 0 when the request never got a response.
  final int status;

  /// The server's stable code (`WRONG_CODE`, `SLOT_FULL`…) or a client-side [ApiErrorCode].
  final String code;

  /// Plain-English text to show the user as it is.
  final String message;

  /// The input at fault, when there is one (`phone`, `pincode`, `slot`, `lines.0.quantity`).
  final String? field;

  /// The token is missing, expired or revoked: drop it and sign in again.
  bool get isUnauthenticated => status == 401 && code == ApiErrorCode.unauthenticated;

  /// Not found, or not yours (`ORDER_NOT_FOUND`, `ADDRESS_NOT_FOUND`, `NOT_FOUND`).
  bool get isNotFound => status == 404;

  /// "The world moved on": refresh and try again.
  bool get isConflict => status == 409;

  /// A slot problem at checkout: refresh `/slots` and ask the customer to pick again.
  bool get isSlotProblem => code == 'SLOT_FULL' || code == 'SLOT_UNAVAILABLE' || code == 'KITCHEN_FULL';

  /// A coupon rule said no (`COUPON_…`).
  bool get isCouponProblem => code.startsWith('COUPON_');

  /// No response at all: worth an automatic retry.
  bool get isNetwork => code == ApiErrorCode.network;

  static String _fallbackCode(int status) => switch (status) {
    400 => 'VALIDATION_FAILED',
    401 => ApiErrorCode.unauthenticated,
    403 => 'FORBIDDEN',
    404 => 'NOT_FOUND',
    409 => 'INVALID_TRANSITION',
    429 => 'TOO_MANY_CODES',
    >= 500 => 'INTERNAL',
    _ => ApiErrorCode.unexpected,
  };

  static String _fallbackMessage(int status) => switch (status) {
    401 => 'Please sign in again.',
    403 => 'You are not allowed to do that.',
    404 => 'We could not find that.',
    409 => 'This has changed in the meantime. Refresh and try again.',
    429 => 'Too many attempts. Please wait a few minutes and try again.',
    >= 500 => 'Something went wrong on our side. Please try again.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'ApiException($status $code: $message${field == null ? '' : ' [$field]'})';
}

/// Codes the app relies on by name. Server codes not listed here are still passed through.
abstract final class ApiErrorCode {
  static const unauthenticated = 'UNAUTHENTICATED';
  static const network = 'NETWORK';
  static const unexpected = 'UNEXPECTED';
}
