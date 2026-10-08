import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/team_member.dart';
import '../services/api_service.dart';

class KelolaTimPage extends StatefulWidget {
  const KelolaTimPage({
    super.key,
    required this.accessToken,
    this.departmentId,
    required this.departmentName,
    this.departmentCode,
  });

  final String accessToken;
  final String? departmentId;
  final String departmentName;
  final String? departmentCode;

  @override
  State<KelolaTimPage> createState() => _KelolaTimPageState();
}

class _KelolaTimPageState extends State<KelolaTimPage> {
  bool _isLoading = true;
  List<TeamMember> _allMembers = [];
  String _searchQuery = '';
  AttendanceStatus? _filterStatus;

  @override
  void initState() {
    super.initState();
    _fetchDepartmentMembers();
  }

  Future<void> _fetchDepartmentMembers() async {
    setState(() => _isLoading = true);
    try {
      final members = await ApiService.fetchTeamMembers(
        accessToken: widget.accessToken,
        departmentId: widget.departmentId,
      );
      if (!mounted) return;
      setState(() {
        _allMembers = members;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      _useFallbackMockData();
    }
  }

  void _useFallbackMockData() {
    final mockMembers = [
      TeamMember(
        id: '1',
        userId: 'u1',
        email: 'ahmad.fauzi@company.com',
        fullName: 'Ahmad Fauzi',
        username: 'ahmad.fauzi',
        role: 'employee',
        positionTitle: 'Senior Developer',
        status: AttendanceStatus.hadir,
        clockInTime: '08:15',
      ),
      TeamMember(
        id: '2',
        userId: 'u2',
        email: 'dian.lestari@company.com',
        fullName: 'Dian Lestari',
        username: 'dian.lestari',
        role: 'employee',
        positionTitle: 'UI/UX Designer',
        status: AttendanceStatus.hadir,
        clockInTime: '08:27',
      ),
      TeamMember(
        id: '3',
        userId: 'u3',
        email: 'budi.santoso@company.com',
        fullName: 'Budi Santoso',
        username: 'budi.santoso',
        role: 'employee',
        positionTitle: 'Backend Engineer',
        status: AttendanceStatus.izin,
        notes: 'Izin urusan dinas luar kantor',
      ),
      TeamMember(
        id: '4',
        userId: 'u4',
        email: 'siti.rahma@company.com',
        fullName: 'Siti Rahma',
        username: 'siti.rahma',
        role: 'employee',
        positionTitle: 'Quality Assurance',
        status: AttendanceStatus.belumAbsen,
      ),
      TeamMember(
        id: '5',
        userId: 'u5',
        email: 'eko.prasetyo@company.com',
        fullName: 'Eko Prasetyo',
        username: 'eko.prasetyo',
        role: 'employee',
        positionTitle: 'Junior Developer',
        status: AttendanceStatus.sakit,
        notes: 'Sakit demam & surat dokter terlampir',
      ),
    ];

    setState(() {
      _allMembers = mockMembers;
      _isLoading = false;
    });
  }

  List<TeamMember> get _filteredMembers {
    return _allMembers.where((member) {
      final matchesSearch = _searchQuery.isEmpty ||
          member.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          member.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          member.positionTitle.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          member.email.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesFilter = _filterStatus == null || member.status == _filterStatus;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  int get _hadirCount => _allMembers.where((m) => m.status == AttendanceStatus.hadir).length;
  int get _izinCount => _allMembers.where((m) => m.status == AttendanceStatus.izin || m.status == AttendanceStatus.sakit).length;
  int get _belumAbsenCount => _allMembers.where((m) => m.status == AttendanceStatus.belumAbsen).length;

  void _openMemberDetail(TeamMember member) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDetailSheet(
        member: member,
        departmentName: widget.departmentName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navy, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kelola Tim & Absensi',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.departmentName + (widget.departmentCode != null ? ' (${widget.departmentCode})' : ''),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDepartmentMembers,
        color: AppColors.teal,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Summary Kartu Absensi Hari Ini
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF102A43), Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF102A43).withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.today_rounded, color: Colors.white70, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Absensi Hari Ini',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Total: ${_allMembers.length} Tim',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Hadir',
                            count: _hadirCount,
                            color: const Color(0xFF10B981),
                            icon: Icons.check_circle_rounded,
                            isActive: _filterStatus == AttendanceStatus.hadir,
                            onTap: () {
                              setState(() {
                                _filterStatus = (_filterStatus == AttendanceStatus.hadir) ? null : AttendanceStatus.hadir;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Izin/Sakit',
                            count: _izinCount,
                            color: const Color(0xFFF59E0B),
                            icon: Icons.access_time_filled_rounded,
                            isActive: _filterStatus == AttendanceStatus.izin,
                            onTap: () {
                              setState(() {
                                _filterStatus = (_filterStatus == AttendanceStatus.izin) ? null : AttendanceStatus.izin;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricTile(
                            label: 'Belum Absen',
                            count: _belumAbsenCount,
                            color: const Color(0xFFEF4444),
                            icon: Icons.cancel_rounded,
                            isActive: _filterStatus == AttendanceStatus.belumAbsen,
                            onTap: () {
                              setState(() {
                                _filterStatus = (_filterStatus == AttendanceStatus.belumAbsen) ? null : AttendanceStatus.belumAbsen;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Search Box & Reset Filter
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Cari nama atau jabatan...',
                        hintStyle: const TextStyle(color: Color(0xFF9FB3C8), fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF829AB1), size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.cardBorder),
                        ),
                      ),
                    ),
                  ),
                  if (_filterStatus != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _filterStatus = null),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.filter_alt_off_rounded, size: 16, color: AppColors.navy),
                            SizedBox(width: 4),
                            Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navy)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // Subtitle Daftar Anggota
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Daftar Anggota Tim',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    '${_filteredMembers.length} anggota',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: AppColors.teal),
                  ),
                )
              else if (_filteredMembers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.person_search_rounded, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'Tidak ada anggota yang sesuai',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Coba kata kunci lain atau ubah filter status.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF829AB1)),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filteredMembers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final member = _filteredMembers[index];
                    return _buildMemberCard(member);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color : Colors.white.withValues(alpha: 0.2),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isActive ? color : Colors.white, size: 18),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(
                color: isActive ? AppColors.navy : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF334E68) : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(TeamMember member) {
    Color badgeBg;
    Color badgeTextColor;
    String statusText;
    IconData statusIcon;

    switch (member.status) {
      case AttendanceStatus.hadir:
        badgeBg = const Color(0xFFD1FAE5);
        badgeTextColor = const Color(0xFF065F46);
        statusText = 'Hadir ${member.clockInTime ?? ""}';
        statusIcon = Icons.check_circle_rounded;
        break;
      case AttendanceStatus.izin:
        badgeBg = const Color(0xFFFEF3C7);
        badgeTextColor = const Color(0xFF92400E);
        statusText = 'Izin';
        statusIcon = Icons.info_rounded;
        break;
      case AttendanceStatus.sakit:
        badgeBg = const Color(0xFFFEE2E2);
        badgeTextColor = const Color(0xFF991B1B);
        statusText = 'Sakit';
        statusIcon = Icons.medical_services_rounded;
        break;
      case AttendanceStatus.belumAbsen:
        badgeBg = const Color(0xFFF1F5F9);
        badgeTextColor = const Color(0xFF64748B);
        statusText = 'Belum Absen';
        statusIcon = Icons.schedule_rounded;
        break;
    }

    final initials = member.fullName.isNotEmpty
        ? member.fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : 'U';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openMemberDetail(member),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.teal.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${member.username} • ${member.positionTitle}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: badgeTextColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class MemberDetailSheet extends StatelessWidget {
  const MemberDetailSheet({
    super.key,
    required this.member,
    required this.departmentName,
  });

  final TeamMember member;
  final String departmentName;

  @override
  Widget build(BuildContext context) {
    final initials = member.fullName.isNotEmpty
        ? member.fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : 'U';

    return Container(
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
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${member.positionTitle} • $departmentName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Informasi Kontak & Akun',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.alternate_email_rounded, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '@${member.username}',
                        style: const TextStyle(fontSize: 13, color: AppColors.navy, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        member.email,
                        style: const TextStyle(fontSize: 13, color: AppColors.navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.badge_outlined, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Role: ${member.role.toUpperCase()}',
                        style: const TextStyle(fontSize: 13, color: AppColors.navy),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aksi Cepat Manager',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Menghubungi ${member.fullName} via Email (${member.email})')),
                    );
                  },
                  icon: const Icon(Icons.send_rounded, size: 16, color: AppColors.navy),
                  label: const Text('Kirim Pesan', style: TextStyle(color: AppColors.navy, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Membuka rekap absensi untuk ${member.fullName}')),
                    );
                  },
                  icon: const Icon(Icons.history_rounded, size: 16, color: Colors.white),
                  label: const Text('Riwayat Absen', style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
