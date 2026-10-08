class WorkShift {
  final String id;
  final String companyId;
  final String name;
  final String startTime;
  final String endTime;
  final int lateToleranceMinutes;
  final List<int> workDays; // 1=Monday, 7=Sunday
  final bool isDefault;

  WorkShift({
    required this.id,
    required this.companyId,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.lateToleranceMinutes = 15,
    required this.workDays,
    this.isDefault = false,
  });

  String get formattedStartTime {
    final parts = startTime.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return startTime;
  }

  String get formattedEndTime {
    final parts = endTime.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return endTime;
  }

  String get formattedTimeRange => '$formattedStartTime - $formattedEndTime';

  String get formattedWorkDays {
    if (workDays.length == 5 &&
        workDays.contains(1) &&
        workDays.contains(2) &&
        workDays.contains(3) &&
        workDays.contains(4) &&
        workDays.contains(5)) {
      return 'Senin - Jumat';
    }
    if (workDays.length == 6 &&
        workDays.contains(1) &&
        workDays.contains(2) &&
        workDays.contains(3) &&
        workDays.contains(4) &&
        workDays.contains(5) &&
        workDays.contains(6)) {
      return 'Senin - Sabtu';
    }
    if (workDays.length == 7) {
      return 'Setiap Hari (Senin - Minggu)';
    }

    const dayNames = {
      1: 'Senin',
      2: 'Selasa',
      3: 'Rabu',
      4: 'Kamis',
      5: 'Jumat',
      6: 'Sabtu',
      7: 'Minggu',
    };
    final sorted = List<int>.from(workDays)..sort();
    return sorted.map((d) => dayNames[d] ?? '').where((n) => n.isNotEmpty).join(', ');
  }

  bool isWorkDay(int weekday) => workDays.contains(weekday);

  factory WorkShift.fromJson(Map<String, dynamic> json) {
    List<int> days = [1, 2, 3, 4, 5];
    final rawDays = json['work_days'];
    if (rawDays is List) {
      days = rawDays.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 1).toList();
    }

    return WorkShift(
      id: json['id'] as String? ?? 'default',
      companyId: json['company_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Shift Reguler',
      startTime: json['start_time'] as String? ?? '08:00:00',
      endTime: json['end_time'] as String? ?? '17:00:00',
      lateToleranceMinutes: json['late_tolerance_minutes'] as int? ?? 15,
      workDays: days,
      isDefault: json['is_default'] == true,
    );
  }

  static WorkShift get defaultShift => WorkShift(
        id: 'default',
        companyId: '',
        name: 'Shift Reguler (Pagi - Sore)',
        startTime: '08:00:00',
        endTime: '17:00:00',
        lateToleranceMinutes: 15,
        workDays: [1, 2, 3, 4, 5],
        isDefault: true,
      );
}
