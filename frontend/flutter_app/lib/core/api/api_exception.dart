import 'package:dio/dio.dart';

/// An API failure with a message that's safe to show the merchant.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  factory ApiException.from(DioException error) {
    final data = error.response?.data;
    final detail = data is Map<String, dynamic> ? data['detail'] : null;
    return ApiException(
      detail is String ? detail : _validationMessage(detail) ?? _fallback(error),
      statusCode: error.response?.statusCode,
    );
  }

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  /// FastAPI's request validation error: `{"detail": [{"loc": [...], "msg": "...", ...}]}`.
  /// Routers raise `{"detail": "..."}`, which is written for the merchant; this form isn't, so it
  /// names the first field and problem instead of pretending to be friendly copy.
  static String? _validationMessage(Object? detail) {
    if (detail is! List || detail.isEmpty) return null;
    final first = detail.first;
    if (first is! Map) return null;
    final message = first['msg'];
    if (message is! String) return null;
    final location = first['loc'];
    final field = location is List && location.isNotEmpty ? location.last : null;
    return field is String ? 'Please check $field: $message' : message;
  }

  static String _fallback(DioException error) => switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout =>
          "Can't reach sellix. Check your internet connection.",
        DioExceptionType.receiveTimeout => 'sellix took too long to answer. Please try again.',
        _ => 'Something went wrong. Please try again.',
      };

  @override
  String toString() => message;
}
