import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ErrorUtils {
  static Map<String, dynamic> decodeResponse(String responseBody) {
    if (responseBody.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String getErrorMessage(Map<String, dynamic> body, {String defaultMessage = 'Terjadi kesalahan pada server.'}) {
    final error = body['error'];
    if (error is Map<String, dynamic> && error['message'] is String) {
      return error['message'] as String;
    }
    if (body['msg'] is String) return body['msg'] as String;
    return defaultMessage;
  }

  static String getFriendlyError(Object error) {
    if (error is http.ClientException || error is TimeoutException) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi dan alamat API.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}
