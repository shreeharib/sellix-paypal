import 'package:dio/dio.dart';

/// An API failure with a message that's safe to show the merchant.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  factory ApiException.from(DioException error) {
    final data = error.response?.data;
    final detail = data is Map<String, dynamic> ? data['detail'] : null;
    return ApiException(
      detail is String ? detail : _fallback(error),
      statusCode: error.response?.statusCode,
    );
  }

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

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
