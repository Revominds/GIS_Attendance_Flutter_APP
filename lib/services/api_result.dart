import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Uniform outcome for any service call that talks to the API.
///
/// `message` is always safe to show the user as-is: it is either the
/// server's own `message`/`error` string or one of the plain-language
/// fallbacks from [describeHttpError] / [describeNetworkError]. Callers
/// check [ok] and, on failure, surface [message]; [data] carries the
/// decoded success payload when there is one.
class ApiResult<T> {
  final bool ok;
  final String message;
  final T? data;
  final int? statusCode;

  const ApiResult._({
    required this.ok,
    required this.message,
    this.data,
    this.statusCode,
  });

  factory ApiResult.success(T? data, {String message = 'Success'}) =>
      ApiResult._(ok: true, message: message, data: data, statusCode: 200);

  factory ApiResult.failure(String message, {int? statusCode, T? data}) =>
      ApiResult._(ok: false, message: message, data: data, statusCode: statusCode);
}

/// Map an exception thrown while making an HTTP request into a
/// user-facing sentence. Use in the `catch` of every service call:
///
/// ```dart
/// } catch (e, st) {
///   AppLog.e('AttendanceService', 'clockIn failed', e, st);
///   return ApiResult.failure(describeNetworkError(e));
/// }
/// ```
String describeNetworkError(Object e) {
  if (e is TimeoutException) {
    return 'The server took too long to respond. Please try again.';
  }
  if (e is SocketException) {
    return 'No internet connection. Check your network and try again.';
  }
  if (e is HandshakeException) {
    return "Couldn't establish a secure connection to the server.";
  }
  if (e is http.ClientException || e is HttpException) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  if (e is FormatException) {
    return 'The server sent a response the app could not read.';
  }
  return 'Something went wrong. Please try again.';
}

/// Map a non-success HTTP response to a user-facing sentence, preferring
/// the server's own message when it sent one.
String describeHttpError(int statusCode, [String? serverMessage]) {
  final msg = serverMessage?.trim();
  if (msg != null && msg.isNotEmpty) return msg;

  switch (statusCode) {
    case 400:
      return 'The request was invalid. Please check your input and try again.';
    case 401:
      return 'Your session has expired. Please log in again.';
    case 403:
      return "You don't have permission to do that.";
    case 404:
      return 'The requested item could not be found.';
    case 409:
      return 'That action conflicts with the current state. Refresh and try again.';
    case 422:
      return 'Some of the information provided was not accepted.';
    case 429:
      return 'Too many attempts. Please wait a moment and try again.';
    case 500:
    case 502:
    case 503:
    case 504:
      return 'The server is having problems right now. Please try again shortly.';
    default:
      return 'Request failed (error $statusCode).';
  }
}

/// Pull a human message out of a decoded JSON body, checking the keys
/// this API actually uses (`message`, then `error`, then `details`).
String? serverMessageOf(Object? decodedBody) {
  if (decodedBody is Map) {
    for (final key in const ['message', 'error', 'details']) {
      final v = decodedBody[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
  }
  return null;
}
