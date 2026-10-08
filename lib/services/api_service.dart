import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../core/utils/error_utils.dart';
import '../models/user_profile.dart';
import '../models/team_member.dart';
import '../models/work_shift.dart';

class ApiService {
  static Future<String> login(String email, String password) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final body = ErrorUtils.decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Email atau password tidak valid.'));
    }

    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw Exception('Respons login tidak memiliki access token.');
    }
    return token;
  }

  static Future<UserProfile> fetchProfile(String accessToken, String email) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return UserProfile.fromJson(body, email);
      }
    }
    throw Exception('Gagal memuat profil & departemen');
  }

  static Future<void> updateProfile({
    required String accessToken,
    required String fullName,
    required String username,
  }) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/me/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'full_name': fullName.trim(),
        'username': username.trim(),
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = ErrorUtils.decodeResponse(response.body);
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal memperbarui profil.'));
    }
  }

  static Future<List<TeamMember>> fetchTeamMembers({
    required String accessToken,
    String? departmentId,
  }) async {
    String endpoint;
    if (departmentId != null && departmentId.isNotEmpty) {
      endpoint = '$apiBaseUrl/companies/current/departments/$departmentId';
    } else {
      endpoint = '$apiBaseUrl/companies/current/departments';
    }

    final response = await http.get(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      List<dynamic> membersRaw = [];

      if (decoded is Map<String, dynamic>) {
        if (decoded['members'] is List) {
          membersRaw = decoded['members'] as List;
        }
      } else if (decoded is List && decoded.isNotEmpty) {
        if (departmentId != null && departmentId.isNotEmpty) {
          final match = decoded.firstWhere(
            (d) => d is Map<String, dynamic> && d['id'] == departmentId,
            orElse: () => decoded.first,
          );
          if (match is Map<String, dynamic> && match['members'] is List) {
            membersRaw = match['members'] as List;
          }
        } else {
          final first = decoded.first;
          if (first is Map<String, dynamic> && first['members'] is List) {
            membersRaw = first['members'] as List;
          }
        }
      }

      final List<TeamMember> list = [];
      for (var i = 0; i < membersRaw.length; i++) {
        if (membersRaw[i] is Map<String, dynamic>) {
          list.add(TeamMember.fromMemberJson(membersRaw[i] as Map<String, dynamic>, i));
        }
      }
      return list;
    }

    throw Exception('Gagal mengambil data anggota tim');
  }

  static Future<List<WorkShift>> fetchCompanyShifts(String accessToken) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/companies/current/shifts'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((s) => WorkShift.fromJson(s))
            .toList();
      }
    }
    return [WorkShift.defaultShift];
  }

  static Future<WorkShift> createShift({
    required String accessToken,
    required String name,
    required String startTime,
    required String endTime,
    int lateToleranceMinutes = 15,
    List<int> workDays = const [1, 2, 3, 4, 5],
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/companies/current/shifts'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'name': name.trim(),
        'start_time': startTime,
        'end_time': endTime,
        'late_tolerance_minutes': lateToleranceMinutes,
        'work_days': workDays,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return WorkShift.fromJson(decoded);
      }
    }
    final body = ErrorUtils.decodeResponse(response.body);
    throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal membuat shift kerja.'));
  }

  static Future<void> assignMemberShift({
    required String accessToken,
    required String memberId,
    required String? shiftId,
  }) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/companies/current/members/$memberId/shift'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'shift_id': shiftId,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = ErrorUtils.decodeResponse(response.body);
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal mengubah shift anggota.'));
    }
  }

  static Future<WorkShift> updateShift({
    required String accessToken,
    required String shiftId,
    String? name,
    String? startTime,
    String? endTime,
    int? lateToleranceMinutes,
    List<int>? workDays,
    bool? isDefault,
  }) async {
    final Map<String, dynamic> bodyMap = {};
    if (name != null) bodyMap['name'] = name;
    if (startTime != null) bodyMap['start_time'] = startTime;
    if (endTime != null) bodyMap['end_time'] = endTime;
    if (lateToleranceMinutes != null) bodyMap['late_tolerance_minutes'] = lateToleranceMinutes;
    if (workDays != null) bodyMap['work_days'] = workDays;
    if (isDefault != null) bodyMap['is_default'] = isDefault;

    final response = await http.patch(
      Uri.parse('$apiBaseUrl/companies/current/shifts/$shiftId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(bodyMap),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return WorkShift.fromJson(decoded);
      }
    }
    final body = ErrorUtils.decodeResponse(response.body);
    throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal mengubah data shift.'));
  }

  static Future<void> deleteShift({
    required String accessToken,
    required String shiftId,
  }) async {
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/companies/current/shifts/$shiftId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = ErrorUtils.decodeResponse(response.body);
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal menghapus shift.'));
    }
  }

  static Future<Map<String, dynamic>> fetchBiometricStatus(String accessToken) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/biometrics/my-face'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return {'is_enrolled': false};
  }

  static Future<Map<String, dynamic>> enrollFace({
    required String accessToken,
    required List<double> faceEmbedding,
    required String photoBase64,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/biometrics/face-enroll'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'face_embedding': faceEmbedding,
        'photo_base64': photoBase64,
      }),
    ).timeout(const Duration(seconds: 30));

    final body = ErrorUtils.decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal mendaftarkan wajah biometrik.'));
    }
    return body;
  }

  static Future<Map<String, dynamic>> clockIn({
    required String accessToken,
    required double similarityScore,
    required bool livenessVerified,
    required String photoBase64,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/attendances/clock-in'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'similarity_score': similarityScore,
        'liveness_verified': livenessVerified,
        'photo_base64': photoBase64,
      }),
    ).timeout(const Duration(seconds: 30));

    final body = ErrorUtils.decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal melakukan Clock In.'));
    }
    return body;
  }

  static Future<Map<String, dynamic>> clockOut({
    required String accessToken,
    required double similarityScore,
    required bool livenessVerified,
    required String photoBase64,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/attendances/clock-out'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'similarity_score': similarityScore,
        'liveness_verified': livenessVerified,
        'photo_base64': photoBase64,
      }),
    ).timeout(const Duration(seconds: 30));

    final body = ErrorUtils.decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal melakukan Clock Out.'));
    }
    return body;
  }

  static Future<Map<String, dynamic>?> fetchTodayAttendance(String accessToken) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/attendances/my-today'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['has_attendance'] == true) {
        return decoded['attendance'] as Map<String, dynamic>?;
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> fetchAttendanceHistory(String accessToken) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/attendances/my-history'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['attendances'] is List) {
        return (decoded['attendances'] as List).cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  static Future<Map<String, dynamic>> requestFaceReset({
    required String accessToken,
    required String reason,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/biometrics/reset-request'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'reason': reason.trim(),
      }),
    ).timeout(const Duration(seconds: 15));

    final body = ErrorUtils.decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(ErrorUtils.getErrorMessage(body, defaultMessage: 'Gagal mengajukan daftar ulang wajah.'));
    }
    return body;
  }

  static Future<Map<String, dynamic>?> fetchMyFaceResetRequest(String accessToken) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/biometrics/my-reset-request'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['has_request'] == true) {
        return decoded['request'] as Map<String, dynamic>?;
      }
    }
    return null;
  }
}

