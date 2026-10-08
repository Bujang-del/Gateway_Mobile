import 'work_shift.dart';

class UserProfile {
  final String id;
  final String email;
  final String? fullName;
  final String? username;
  final String? companyName;
  final String? companyCode;
  final String? departmentName;
  final String? departmentCode;
  final String? positionTitle;
  final String? role;
  final bool isManager;
  final String? managedDeptId;
  final String? managedDeptName;
  final String? managedDeptCode;
  final WorkShift? shift;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.username,
    this.companyName,
    this.companyCode,
    this.departmentName,
    this.departmentCode,
    this.positionTitle,
    this.role,
    this.isManager = false,
    this.managedDeptId,
    this.managedDeptName,
    this.managedDeptCode,
    this.shift,
  });

  String get displayName {
    if (fullName != null && fullName!.trim().isNotEmpty) {
      return fullName!.trim();
    }
    return email;
  }

  String get displayUsername {
    if (username != null && username!.trim().isNotEmpty) {
      return '@${username!.trim()}';
    }
    return '@${email.split('@').first}';
  }

  factory UserProfile.fromJson(Map<String, dynamic> json, String fallbackEmail) {
    final user = json['user'] as Map<String, dynamic>?;
    final id = user?['id'] as String? ?? '';
    final email = user?['email'] as String? ?? fallbackEmail;
    final fullName = user?['full_name'] as String?;
    final username = user?['username'] as String?;

    final membership = json['membership'] as Map<String, dynamic>?;
    String? compName;
    String? compCode;
    String? deptName;
    String? deptCode;
    String? posTitle;
    String? role;
    bool isManager = false;
    String? managedDeptId;
    String? managedDeptName;
    String? managedDeptCode;
    WorkShift? shift;

    if (membership != null) {
      final comp = membership['company'] as Map<String, dynamic>?;
      compName = (membership['company_name'] as String?) ?? comp?['name'] as String?;
      compCode = comp?['code'] as String?;

      final dept = membership['department'] as Map<String, dynamic>?;
      deptName = dept?['name'] as String?;
      deptCode = dept?['code'] as String?;

      isManager = membership['is_manager'] == true;
      final managedDept = membership['managed_department'] as Map<String, dynamic>?;
      managedDeptId = managedDept?['id'] as String?;
      managedDeptName = managedDept?['name'] as String?;
      managedDeptCode = managedDept?['code'] as String?;

      final displayPosition = membership['display_position'] as String?;
      posTitle = (displayPosition != null && displayPosition.isNotEmpty)
          ? displayPosition
          : membership['position_title'] as String?;
      role = membership['role'] as String?;

      final shiftRaw = membership['shift'];
      if (shiftRaw is Map<String, dynamic>) {
        shift = WorkShift.fromJson(shiftRaw);
      }
    }

    return UserProfile(
      id: id,
      email: email,
      fullName: fullName,
      username: username,
      companyName: compName,
      companyCode: compCode,
      departmentName: deptName,
      departmentCode: deptCode,
      positionTitle: posTitle,
      role: role,
      isManager: isManager,
      managedDeptId: managedDeptId,
      managedDeptName: managedDeptName,
      managedDeptCode: managedDeptCode,
      shift: shift ?? WorkShift.defaultShift,
    );
  }
}
