enum AttendanceStatus {
  hadir,
  izin,
  sakit,
  belumAbsen,
}

class TeamMember {
  final String id;
  final String userId;
  final String email;
  final String fullName;
  final String username;
  final String role;
  final String positionTitle;
  final AttendanceStatus status;
  final String? clockInTime;
  final String? clockOutTime;
  final String? notes;

  TeamMember({
    required this.id,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.username,
    required this.role,
    required this.positionTitle,
    required this.status,
    this.clockInTime,
    this.clockOutTime,
    this.notes,
  });

  factory TeamMember.fromMemberJson(Map<String, dynamic> json, int index) {
    final id = json['id'] as String? ?? '';
    final userId = json['user_id'] as String? ?? '';
    final role = json['role'] as String? ?? 'employee';
    final positionTitle = json['position_title'] as String? ?? 'Anggota Tim';

    String email = 'user@company.com';
    String fullName = '';
    String username = '';

    final profiles = json['profiles'];
    if (profiles is List && profiles.isNotEmpty && profiles[0] is Map<String, dynamic>) {
      final p = profiles[0] as Map<String, dynamic>;
      email = p['email'] as String? ?? email;
      final rawName = p['full_name'] as String?;
      final rawUser = p['username'] as String?;
      if (rawName != null && rawName.trim().isNotEmpty) {
        fullName = rawName.trim();
      }
      if (rawUser != null && rawUser.trim().isNotEmpty) {
        username = rawUser.trim();
      }
    } else if (profiles is Map<String, dynamic>) {
      email = profiles['email'] as String? ?? email;
      final rawName = profiles['full_name'] as String?;
      final rawUser = profiles['username'] as String?;
      if (rawName != null && rawName.trim().isNotEmpty) {
        fullName = rawName.trim();
      }
      if (rawUser != null && rawUser.trim().isNotEmpty) {
        username = rawUser.trim();
      }
    }

    if (username.isEmpty && email.isNotEmpty) {
      username = email.split('@').first;
    }
    if (fullName.isEmpty) {
      fullName = username.isNotEmpty ? username : 'Anggota Tim';
    }

    final mockStatuses = [
      AttendanceStatus.hadir,
      AttendanceStatus.hadir,
      AttendanceStatus.izin,
      AttendanceStatus.belumAbsen,
      AttendanceStatus.sakit,
    ];
    final mockTimes = ['08:14', '08:29', '07:55', '08:42'];
    final status = mockStatuses[index % mockStatuses.length];
    final clockIn = status == AttendanceStatus.hadir ? mockTimes[index % mockTimes.length] : null;
    final notes = status == AttendanceStatus.izin
        ? 'Izin keperluan keluarga'
        : (status == AttendanceStatus.sakit ? 'Sakit demam' : null);

    return TeamMember(
      id: id,
      userId: userId,
      email: email,
      fullName: fullName,
      username: username,
      role: role,
      positionTitle: positionTitle,
      status: status,
      clockInTime: clockIn,
      notes: notes,
    );
  }
}
