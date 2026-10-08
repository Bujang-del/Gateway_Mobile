import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/work_shift.dart';
import '../services/api_service.dart';
import 'atur_jadwal_screen.dart';
import 'jadwal_kerja_screen.dart';
import 'kelola_tim_screen.dart';
import 'login_screen.dart';
import 'presensi_screen.dart';
import 'profile_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.email,
    required this.accessToken,
  });

  final String email;
  final String accessToken;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = true;
  String? _errorMessage;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await ApiService.fetchProfile(widget.accessToken, widget.email);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat profil & departemen';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _profile?.displayName ?? widget.email;
    final displayUsername = _profile?.displayUsername ?? '@${widget.email.split('@').first}';
    final companyName = (_profile?.companyName != null && _profile!.companyName!.trim().isNotEmpty)
        ? _profile!.companyName!.trim()
        : 'Portal Karyawan';
    final role = _profile?.role;
    final isManager = _profile?.isManager ?? false;
    final deptName = _profile?.departmentName;
    final deptCode = _profile?.departmentCode;
    final posTitle = _profile?.positionTitle;

    final initials = displayName.trim().isNotEmpty
        ? displayName.trim().split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          companyName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Muat ulang data',
            onPressed: _fetchProfile,
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Keluar',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const LoginPage()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchProfile,
          color: AppColors.teal,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kartu Profil Utama
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => ProfilePage(
                            email: widget.email,
                            accessToken: widget.accessToken,
                            initialFullName: _profile?.fullName,
                            initialUsername: _profile?.username,
                            companyName: _profile?.companyName,
                            role: _profile?.role,
                            positionTitle: _profile?.positionTitle,
                            departmentName: _profile?.departmentName,
                          ),
                        ),
                      );
                      if (updated == true || mounted) {
                        _fetchProfile();
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.navy, AppColors.navyLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AppColors.teal, Color(0xFF064E3B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$displayUsername • ${widget.email}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.teal,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        role != null && role.isNotEmpty
                                            ? role.toUpperCase()
                                            : 'KARYAWAN',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    if (isManager)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.amber,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'MANAGER',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),


                const SizedBox(height: 16),

                // Kartu Informasi Departemen & Jabatan
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.tealLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.apartment_rounded,
                              color: AppColors.teal,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Departemen',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (_isLoading)
                                  const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                                  )
                                else if (deptName != null && deptName.isNotEmpty)
                                  Row(
                                    children: [
                                      Text(
                                        deptName,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                      if (deptCode != null && deptCode.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF0F4F8),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppColors.cardBorder),
                                          ),
                                          child: Text(
                                            deptCode,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF334E68),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                else
                                  const Text(
                                    'Belum ditempatkan di departemen',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                      color: Color(0xFF829AB1),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: Color(0xFFF0F4F8), height: 1),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.badge_outlined,
                              color: Color(0xFF2563EB),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Posisi / Jabatan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (_isLoading)
                                  const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                                  )
                                else
                                  Text(
                                    posTitle != null && posTitle.isNotEmpty
                                        ? posTitle
                                        : 'Karyawan',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.navy,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: _fetchProfile,
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 14, color: AppColors.amber),
                              const SizedBox(width: 6),
                              Text(
                                '${_errorMessage!}. Ketuk untuk coba lagi.',
                                style: const TextStyle(fontSize: 11, color: AppColors.amber),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Kartu Manager — tampil hanya jika user adalah manager
                if (isManager && !_isLoading) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD97706), Color(0xFFB45309)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.supervisor_account_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Anda adalah Manager',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (_profile?.managedDeptName != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Departemen: ${_profile!.managedDeptName}${_profile?.managedDeptCode != null ? ' (${_profile!.managedDeptCode})' : ''}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text(
                  'Menu Utama',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _buildMenuCard(
                      context,
                      icon: Icons.fingerprint,
                      title: 'Presensi',
                      subtitle: 'Clock In / Out',
                      color: AppColors.teal,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PresensiPage(
                              accessToken: widget.accessToken,
                              email: widget.email,
                              profile: _profile,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      icon: Icons.calendar_month_outlined,
                      title: 'Jadwal Kerja',
                      subtitle: 'Shift & Hari Kerja',
                      color: const Color(0xFF2563EB),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => JadwalKerjaPage(
                              shift: _profile?.shift ?? WorkShift.defaultShift,
                              companyName: companyName,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      icon: Icons.history,
                      title: 'Riwayat Absensi',
                      subtitle: 'Log kehadiran',
                      color: AppColors.amber,
                    ),
                    _buildMenuCard(
                      context,
                      icon: Icons.beach_access_outlined,
                      title: 'Pengajuan Cuti',
                      subtitle: 'Izin & sakit',
                      color: const Color(0xFF7C3AED),
                    ),
                  ],
                ),

                // Menu Manager — tampil hanya jika user adalah manager
                if (isManager && !_isLoading) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Menu Manager',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      _buildMenuCard(
                        context,
                        icon: Icons.group_outlined,
                        title: 'Kelola Tim',
                        subtitle: 'Anggota departemen',
                        color: AppColors.amber,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => KelolaTimPage(
                                accessToken: widget.accessToken,
                                departmentId: _profile?.managedDeptId,
                                departmentName: _profile?.managedDeptName ?? _profile?.departmentName ?? 'Departemen Tim',
                                departmentCode: _profile?.managedDeptCode ?? _profile?.departmentCode,
                              ),
                            ),
                          );
                        },
                      ),
                      _buildMenuCard(
                        context,
                        icon: Icons.check_circle_outline,
                        title: 'Approval Cuti',
                        subtitle: 'Setujui / tolak izin',
                        color: const Color(0xFF059669),
                      ),
                      _buildMenuCard(
                        context,
                        icon: Icons.bar_chart_rounded,
                        title: 'Laporan Tim',
                        subtitle: 'Rekap kehadiran',
                        color: const Color(0xFF7C3AED),
                      ),
                      _buildMenuCard(
                        context,
                        icon: Icons.schedule_rounded,
                        title: 'Atur Jadwal',
                        subtitle: 'Shift anggota tim',
                        color: const Color(0xFF2563EB),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AturJadwalPage(
                                accessToken: widget.accessToken,
                                departmentId: _profile?.managedDeptId,
                                departmentName: _profile?.managedDeptName ?? _profile?.departmentName ?? 'Departemen Tim',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
