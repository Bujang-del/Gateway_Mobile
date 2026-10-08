import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/team_member.dart';
import '../models/work_shift.dart';
import '../services/api_service.dart';

class AturJadwalPage extends StatefulWidget {
  const AturJadwalPage({
    super.key,
    required this.accessToken,
    this.departmentId,
    required this.departmentName,
  });

  final String accessToken;
  final String? departmentId;
  final String departmentName;

  @override
  State<AturJadwalPage> createState() => _AturJadwalPageState();
}

class _AturJadwalPageState extends State<AturJadwalPage> {
  bool _isLoading = true;
  List<TeamMember> _members = [];
  List<WorkShift> _shifts = [];
  final Map<String, String?> _memberShiftMap = {}; // memberId -> shiftId

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final membersFuture = ApiService.fetchTeamMembers(
        accessToken: widget.accessToken,
        departmentId: widget.departmentId,
      );
      final shiftsFuture = ApiService.fetchCompanyShifts(widget.accessToken);

      final results = await Future.wait([membersFuture, shiftsFuture]);
      if (!mounted) return;

      setState(() {
        _members = results[0] as List<TeamMember>;
        _shifts = results[1] as List<WorkShift>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _openShiftSelector(TeamMember member) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pilih Shift untuk ${member.fullName}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Jabatan: ${member.positionTitle}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _shifts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final s = _shifts[i];
                  final isSelected = _memberShiftMap[member.id] == s.id ||
                      (_memberShiftMap[member.id] == null && s.isDefault);

                  return InkWell(
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _assignShift(member, s);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.teal.withValues(alpha: 0.08) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.teal : AppColors.cardBorder,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      s.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isSelected ? AppColors.teal : AppColors.navy,
                                      ),
                                    ),
                                    if (s.isDefault) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE2E8F0),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'DEFAULT',
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${s.formattedTimeRange} • ${s.formattedWorkDays}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignShift(TeamMember member, WorkShift shift) async {
    try {
      await ApiService.assignMemberShift(
        accessToken: widget.accessToken,
        memberId: member.id,
        shiftId: shift.id == 'default' ? null : shift.id,
      );
      setState(() {
        _memberShiftMap[member.id] = shift.id;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shift ${member.fullName} berhasil diubah ke ${shift.name}'),
          backgroundColor: AppColors.teal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
    }
  }

  void _openCreateShiftDialog() {
    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController(text: '08:00');
    final endCtrl = TextEditingController(text: '17:00');
    final toleranceCtrl = TextEditingController(text: '15');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tambah Shift Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Shift (Contoh: Shift Pagi)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      decoration: const InputDecoration(labelText: 'Jam Masuk (08:00)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: endCtrl,
                      decoration: const InputDecoration(labelText: 'Jam Pulang (17:00)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toleranceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Toleransi Terlambat (Menit)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                final newShift = await ApiService.createShift(
                  accessToken: widget.accessToken,
                  name: nameCtrl.text.trim(),
                  startTime: startCtrl.text.trim(),
                  endTime: endCtrl.text.trim(),
                  lateToleranceMinutes: int.tryParse(toleranceCtrl.text) ?? 15,
                );
                setState(() {
                  _shifts.add(newShift);
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Shift "${newShift.name}" berhasil ditambahkan!'), backgroundColor: AppColors.teal),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Simpan Shift'),
          ),
        ],
      ),
    );
  }

  void _openEditShiftDialog(WorkShift shift) {
    final nameCtrl = TextEditingController(text: shift.name);
    final startParts = shift.startTime.split(':');
    final startStr = startParts.length >= 2 ? '${startParts[0]}:${startParts[1]}' : shift.startTime;
    final endParts = shift.endTime.split(':');
    final endStr = endParts.length >= 2 ? '${endParts[0]}:${endParts[1]}' : shift.endTime;

    final startCtrl = TextEditingController(text: startStr);
    final endCtrl = TextEditingController(text: endStr);
    final toleranceCtrl = TextEditingController(text: shift.lateToleranceMinutes.toString());

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Shift "${shift.name}"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Shift'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startCtrl,
                      decoration: const InputDecoration(labelText: 'Jam Masuk (08:00)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: endCtrl,
                      decoration: const InputDecoration(labelText: 'Jam Pulang (17:00)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toleranceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Toleransi Terlambat (Menit)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                final startVal = startCtrl.text.trim().length == 5 ? '${startCtrl.text.trim()}:00' : startCtrl.text.trim();
                final endVal = endCtrl.text.trim().length == 5 ? '${endCtrl.text.trim()}:00' : endCtrl.text.trim();

                final updated = await ApiService.updateShift(
                  accessToken: widget.accessToken,
                  shiftId: shift.id,
                  name: nameCtrl.text.trim(),
                  startTime: startVal,
                  endTime: endVal,
                  lateToleranceMinutes: int.tryParse(toleranceCtrl.text) ?? 15,
                );
                setState(() {
                  final idx = _shifts.indexWhere((s) => s.id == shift.id);
                  if (idx >= 0) {
                    _shifts[idx] = updated;
                  }
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Shift "${updated.name}" berhasil diperbarui!'), backgroundColor: AppColors.teal),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Simpan Perubahan'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteShift(WorkShift shift) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Shift?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
        content: Text(
          'Apakah Anda yakin ingin menghapus shift "${shift.name}"? Karyawan yang terdaftar pada shift ini akan otomatis beralih ke shift default.',
          style: const TextStyle(fontSize: 13, color: AppColors.navy),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ApiService.deleteShift(
                  accessToken: widget.accessToken,
                  shiftId: shift.id,
                );
                setState(() {
                  _shifts.removeWhere((s) => s.id == shift.id);
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Shift "${shift.name}" berhasil dihapus!'), backgroundColor: AppColors.teal),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Atur Jadwal Tim',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              widget.departmentName,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.teal),
            tooltip: 'Tambah Shift Baru',
            onPressed: _openCreateShiftDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
            : RefreshIndicator(
                onRefresh: _loadData,
                color: AppColors.teal,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded, color: Color(0xFF2563EB), size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Manajemen Shift Anggota',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_shifts.length} shift terdaftar. Ketuk shift untuk edit/hapus, atau ketuk anggota untuk menetapkan shift.',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF3B82F6)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Daftar Shift Card Overview
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Daftar Shift Perusahaan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                          InkWell(
                            onTap: _openCreateShiftDialog,
                            child: const Text(
                              '+ Tambah Shift',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.teal),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      SizedBox(
                        height: 125,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _shifts.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final s = _shifts[index];
                            return Container(
                              width: 220,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: s.isDefault ? AppColors.teal : AppColors.cardBorder,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppColors.navy,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () => _openEditShiftDialog(s),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 2),
                                              child: Icon(Icons.edit_outlined, size: 16, color: AppColors.teal),
                                            ),
                                          ),
                                          if (!s.isDefault)
                                            InkWell(
                                              onTap: () => _confirmDeleteShift(s),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 2),
                                                child: Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.formattedTimeRange,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: AppColors.teal,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Tol: ${s.lateToleranceMinutes}m • ${s.formattedWorkDays}',
                                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Anggota Tim Departemen',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            '${_members.length} orang',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _members.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final member = _members[index];
                          final shiftId = _memberShiftMap[member.id];
                          final assignedShift = _shifts.firstWhere(
                            (s) => s.id == shiftId,
                            orElse: () => _shifts.isNotEmpty ? _shifts.first : WorkShift.defaultShift,
                          );

                          final initials = member.fullName.isNotEmpty
                              ? member.fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                              : 'U';

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openShiftSelector(member),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: AppColors.teal.withValues(alpha: 0.12),
                                      child: Text(
                                        initials,
                                        style: const TextStyle(
                                          color: AppColors.teal,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            member.fullName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: AppColors.navy,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${member.positionTitle} • @${member.username}',
                                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Shift: ${assignedShift.name} (${assignedShift.formattedTimeRange})',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF334E68),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.edit_calendar_rounded, size: 20, color: AppColors.teal),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
