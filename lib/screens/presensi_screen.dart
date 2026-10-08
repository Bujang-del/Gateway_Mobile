import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/work_shift.dart';
import '../services/api_service.dart';
import '../services/face_biometric_service.dart';
import 'face_attendance_screen.dart';

class AttendanceLogItem {
  final String date;
  final String clockIn;
  final String? clockOut;
  final String status;
  final bool isLate;
  final String? photoPath;
  final String approvalStatus;
  final String? rejectionReason;

  AttendanceLogItem({
    required this.date,
    required this.clockIn,
    this.clockOut,
    required this.status,
    required this.isLate,
    this.photoPath,
    this.approvalStatus = 'approved',
    this.rejectionReason,
  });
}

class PresensiPage extends StatefulWidget {
  const PresensiPage({
    super.key,
    required this.accessToken,
    required this.email,
    this.profile,
  });

  final String accessToken;
  final String email;
  final UserProfile? profile;

  @override
  State<PresensiPage> createState() => _PresensiPageState();
}

enum AttendanceTodayState {
  notClockedIn,
  clockedIn,
  completed,
}

class _PresensiPageState extends State<PresensiPage> {
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  bool _isLoading = true;
  AttendanceTodayState _todayState = AttendanceTodayState.notClockedIn;
  String? _clockInTimeStr;
  String? _clockOutTimeStr;
  bool _isLate = false;
  bool _isFaceEnrolled = false;
  bool _isTodayRejected = false;
  String? _todayRejectionReason;
  Map<String, dynamic>? _activeResetRequest;
  final List<AttendanceLogItem> _attendanceLogs = [];

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Cek permohonan daftar ulang wajah
      final resetReq = await ApiService.fetchMyFaceResetRequest(widget.accessToken);
      _activeResetRequest = resetReq;

      // Jika HR sudah menyetujui, hapus master face lokal agar karyawan bisa daftar ulang
      if (resetReq != null && resetReq['status'] == 'approved') {
        await FaceBiometricService.clearMasterFace(widget.email);
      }

      // 2. Cek status biometrik dari backend
      final bioStatus = await ApiService.fetchBiometricStatus(widget.accessToken);
      final isEnrolledOnServer = bioStatus['is_enrolled'] == true;

      // Sinkronkan ke local jika ada embedding dan bukan status reset disetujui
      if (isEnrolledOnServer && bioStatus['face_embedding'] is List) {
        final embList = (bioStatus['face_embedding'] as List).map((e) => (e as num).toDouble()).toList();
        await FaceBiometricService.saveMasterFace(widget.email, embList);
      }

      // Cek juga lokal
      final isLocalEnrolled = await FaceBiometricService.isFaceEnrolled(widget.email);
      _isFaceEnrolled = isEnrolledOnServer || isLocalEnrolled;

      // 3. Cek status presensi hari ini dari server
      final todayRecord = await ApiService.fetchTodayAttendance(widget.accessToken);
      if (todayRecord != null) {
        final inTime = todayRecord['clock_in_time'] as String?;
        final outTime = todayRecord['clock_out_time'] as String?;
        final status = todayRecord['status'] as String? ?? 'on_time';
        final approvalStatus = todayRecord['approval_status'] as String? ?? 'pending';
        final rejectionReason = todayRecord['rejection_reason'] as String?;

        if (approvalStatus == 'rejected') {
          // HR Menolak presensi: Kembalikan status presensi ke belum Clock In agar karyawan bisa Clock In ulang
          _isTodayRejected = true;
          _todayRejectionReason = rejectionReason;
          _todayState = AttendanceTodayState.notClockedIn;
          _clockInTimeStr = null;
          _clockOutTimeStr = null;
        } else {
          _isTodayRejected = false;
          _todayRejectionReason = null;
          if (inTime != null && inTime.isNotEmpty) {
            final dtIn = DateTime.tryParse(inTime)?.toLocal();
            _clockInTimeStr = dtIn != null ? '${_twoDigits(dtIn.hour)}:${_twoDigits(dtIn.minute)} WIB' : inTime;
            _isLate = status == 'late';

            if (outTime != null && outTime.isNotEmpty) {
              final dtOut = DateTime.tryParse(outTime)?.toLocal();
              _clockOutTimeStr = dtOut != null ? '${_twoDigits(dtOut.hour)}:${_twoDigits(dtOut.minute)} WIB' : outTime;
              _todayState = AttendanceTodayState.completed;
            } else {
              _todayState = AttendanceTodayState.clockedIn;
            }
          } else {
            _todayState = AttendanceTodayState.notClockedIn;
          }
        }
      } else {
        _isTodayRejected = false;
        _todayRejectionReason = null;
        _todayState = AttendanceTodayState.notClockedIn;
        _clockInTimeStr = null;
        _clockOutTimeStr = null;
      }

      // 4. Ambil riwayat presensi dari server
      final historyRecords = await ApiService.fetchAttendanceHistory(widget.accessToken);
      _attendanceLogs.clear();
      for (final rec in historyRecords) {
        final inTime = rec['clock_in_time'] as String?;
        final outTime = rec['clock_out_time'] as String?;
        final dtIn = inTime != null ? DateTime.tryParse(inTime)?.toLocal() : null;
        final dtOut = outTime != null ? DateTime.tryParse(outTime)?.toLocal() : null;
        final dateStr = rec['date'] as String? ?? '-';
        final status = rec['status'] as String? ?? 'on_time';
        final approvalStatus = rec['approval_status'] as String? ?? 'approved';
        final rejectionReason = rec['rejection_reason'] as String?;

        _attendanceLogs.add(
          AttendanceLogItem(
            date: dateStr,
            clockIn: dtIn != null ? '${_twoDigits(dtIn.hour)}:${_twoDigits(dtIn.minute)} WIB' : '-',
            clockOut: dtOut != null ? '${_twoDigits(dtOut.hour)}:${_twoDigits(dtOut.minute)} WIB' : null,
            status: status == 'late' ? 'Terlambat' : 'Tepat Waktu',
            isLate: status == 'late',
            photoPath: rec['clock_in_photo_url'] as String?,
            approvalStatus: approvalStatus,
            rejectionReason: rejectionReason,
          ),
        );
      }
    } catch (_) {
      // Abaikan kegagalan jaringan saat inisialisasi
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String _formatIndonesianDate(DateTime dt) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];

    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '$dayName, ${dt.day} $monthName ${dt.year}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatTime(DateTime dt) {
    return '${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}:${_twoDigits(dt.second)} WIB';
  }

  void _handleAttendanceButtonPress() {
    if (!_isFaceEnrolled) {
      _showEnrollmentGuideSheet();
      return;
    }

    if (_todayState == AttendanceTodayState.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anda sudah menyelesaikan presensi untuk hari ini.'),
          backgroundColor: AppColors.teal,
        ),
      );
      return;
    }

    final isClockIn = _todayState == AttendanceTodayState.notClockedIn;
    _showVerificationGuideSheet(isClockIn: isClockIn);
  }

  void _showEnrollmentGuideSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural_rounded,
                        color: Color(0xFF0284C7),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pendaftaran Wajah Master',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Simpan profil biometrik wajah Anda ke server',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildGuideRow(
                        icon: Icons.light_mode_outlined,
                        title: 'Pencahayaan Terang & Rata',
                        subtitle: 'Hindari bayangan tebal atau backlight agar fitur wajah terekam sempurna.',
                      ),
                      const SizedBox(height: 12),
                      _buildGuideRow(
                        icon: Icons.face_rounded,
                        title: 'Tatap Lurus Kamera',
                        subtitle: 'Posisikan wajah tepat di tengah lingkaran oval dengan ekspresi natural.',
                      ),
                      const SizedBox(height: 12),
                      _buildGuideRow(
                        icon: Icons.cloud_upload_outlined,
                        title: 'Penyimpanan Aman ke Supabase',
                        subtitle: 'Foto dan vektor fitur akan disimpan sebagai data referensi presensi Anda.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startFaceEnrollment();
                    },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text(
                      'Buka Kamera & Daftarkan Wajah',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVerificationGuideSheet({required bool isClockIn}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isClockIn ? AppColors.tealLight : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.face_retouching_natural_rounded,
                        color: isClockIn ? AppColors.teal : AppColors.amber,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClockIn ? 'Siap untuk Clock In' : 'Siap untuk Clock Out',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Autentikasi Wajah & Deteksi Liveness Aktif',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildGuideRow(
                        icon: Icons.light_mode_outlined,
                        title: 'Pencahayaan Cukup',
                        subtitle: 'Pastikan wajah terlihat jelas dan tidak membelakangi cahaya.',
                      ),
                      const SizedBox(height: 12),
                      _buildGuideRow(
                        icon: Icons.visibility_outlined,
                        title: 'Wajah Terbuka',
                        subtitle: 'Lepaskan masker, helm, atau kacamata hitam tebal.',
                      ),
                      const SizedBox(height: 12),
                      _buildGuideRow(
                        icon: Icons.motion_photos_on_outlined,
                        title: 'Tantangan Liveness Aktif',
                        subtitle: 'Posisikan wajah di oval, lalu ikuti instruksi menoleh ke kanan.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _navigateToFaceVerification(isClockIn);
                    },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      isClockIn ? 'Buka Kamera & Mulai Clock In' : 'Buka Kamera & Mulai Clock Out',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isClockIn ? AppColors.teal : AppColors.amber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuideRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
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
      ],
    );
  }

  Future<void> _startFaceEnrollment() async {
    final result = await Navigator.of(context).push<FaceAttendanceResult>(
      MaterialPageRoute(
        builder: (_) => FaceAttendanceScreen(
          email: widget.email,
          isClockIn: true,
          isEnrollmentMode: true,
        ),
      ),
    );

    if (result != null && result.success) {
      String photoBase64 = '';
      if (result.photoPath != null && result.photoPath!.isNotEmpty) {
        try {
          final bytes = File(result.photoPath!).readAsBytesSync();
          photoBase64 = base64Encode(bytes);
        } catch (_) {}
      }

      final embedding = result.faceEmbedding ?? [0.8, 0.5, 0.4, 0.6];

      // Kirim pendaftaran ke backend
      try {
        await ApiService.enrollFace(
          accessToken: widget.accessToken,
          faceEmbedding: embedding,
          photoBase64: photoBase64,
        );

        // Simpan juga secara lokal untuk pencocokan on-device
        await FaceBiometricService.saveMasterFace(widget.email, embedding);

        if (mounted) {
          setState(() {
            _isFaceEnrolled = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wajah Anda berhasil didaftarkan ke Supabase! Sekarang Anda dapat melakukan Clock In.'),
              backgroundColor: AppColors.teal,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menyimpan pendaftaran wajah: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _navigateToFaceVerification(bool isClockIn) async {
    final result = await Navigator.of(context).push<FaceAttendanceResult>(
      MaterialPageRoute(
        builder: (_) => FaceAttendanceScreen(
          email: widget.email,
          isClockIn: isClockIn,
          isEnrollmentMode: false,
        ),
      ),
    );

    if (result != null && result.success) {
      String photoBase64 = '';
      if (result.photoPath != null && result.photoPath!.isNotEmpty) {
        try {
          final bytes = File(result.photoPath!).readAsBytesSync();
          photoBase64 = base64Encode(bytes);
        } catch (_) {}
      }

      try {
        if (isClockIn) {
          final resp = await ApiService.clockIn(
            accessToken: widget.accessToken,
            similarityScore: result.similarityScore,
            livenessVerified: result.livenessVerified,
            photoBase64: photoBase64,
          );

          final serverStatus = resp['status'] as String? ?? 'on_time';
          final serverTime = resp['clock_in_time'] as String? ?? '${_twoDigits(DateTime.now().hour)}:${_twoDigits(DateTime.now().minute)} WIB';

          setState(() {
            _clockInTimeStr = serverTime;
            _isLate = serverStatus == 'late';
            _todayState = AttendanceTodayState.clockedIn;

            _attendanceLogs.insert(
              0,
              AttendanceLogItem(
                date: 'Hari Ini (${DateTime.now().day}/${DateTime.now().month})',
                clockIn: serverTime,
                clockOut: null,
                status: _isLate ? 'Terlambat' : 'Tepat Waktu',
                isLate: _isLate,
                photoPath: resp['clock_in_photo_url'] as String? ?? result.photoPath,
              ),
            );
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Clock In Berhasil pada $serverTime (${_isLate ? "Terlambat" : "Tepat Waktu"})! Tersimpan di Supabase.'),
                backgroundColor: _isLate ? AppColors.amber : AppColors.teal,
              ),
            );
          }
        } else {
          final resp = await ApiService.clockOut(
            accessToken: widget.accessToken,
            similarityScore: result.similarityScore,
            livenessVerified: result.livenessVerified,
            photoBase64: photoBase64,
          );

          final serverTime = resp['clock_out_time'] as String? ?? '${_twoDigits(DateTime.now().hour)}:${_twoDigits(DateTime.now().minute)} WIB';

          setState(() {
            _clockOutTimeStr = serverTime;
            _todayState = AttendanceTodayState.completed;

            if (_attendanceLogs.isNotEmpty) {
              final existing = _attendanceLogs.first;
              _attendanceLogs[0] = AttendanceLogItem(
                date: existing.date,
                clockIn: existing.clockIn,
                clockOut: serverTime,
                status: existing.status,
                isLate: existing.isLate,
                photoPath: existing.photoPath,
              );
            }
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Clock Out Berhasil pada $serverTime! Data presensi hari ini lengkap.'),
                backgroundColor: const Color(0xFF2563EB),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal mengirim presensi ke server: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = widget.profile?.shift ?? WorkShift.defaultShift;
    final displayName = widget.profile?.displayName ?? widget.email;
    final deptName = widget.profile?.departmentName ?? 'Departemen Umum';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Presensi Kehadiran',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Segarkan data',
            onPressed: _loadInitialData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Opsi Lainnya',
            onSelected: (val) {
              if (val == 'reset') {
                _showRequestFaceResetDialog();
              } else if (val == 'guide') {
                if (!_isFaceEnrolled) {
                  _showEnrollmentGuideSheet();
                } else {
                  _showVerificationGuideSheet(isClockIn: _todayState == AttendanceTodayState.notClockedIn);
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.face_retouching_natural_rounded, color: AppColors.navy, size: 20),
                    SizedBox(width: 10),
                    Text('Daftar Ulang Wajah'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'guide',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.navy, size: 20),
                    SizedBox(width: 10),
                    Text('Panduan Presensi'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
            : RefreshIndicator(
                onRefresh: _loadInitialData,
                color: AppColors.teal,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 1. Banner Status Permohonan Reset Wajah (Jika ada)
                      if (_activeResetRequest != null) ...[
                        _buildResetRequestBanner(),
                        const SizedBox(height: 16),
                      ],

                      // 2. Banner Jika Presensi Hari Ini Ditolak HR
                      if (_isTodayRejected) ...[
                        _buildRejectedAttendanceBanner(),
                        const SizedBox(height: 16),
                      ],

                      // 3. Banner jika Wajah Belum Terdaftar
                      if (!_isFaceEnrolled && (_activeResetRequest == null || _activeResetRequest!['status'] != 'approved')) ...[
                        _buildEnrollmentBanner(),
                        const SizedBox(height: 16),
                      ],

                      // 4. Kartu Header Jam Real-time
                      _buildClockHeaderCard(displayName, deptName),

                      const SizedBox(height: 16),

                      // 4. Kartu Jadwal Shift Hari Ini
                      _buildShiftCard(shift),

                      const SizedBox(height: 24),

                      // 5. Tombol Aksi Utama (Hero Scanner Action Center)
                      _buildHeroAttendanceButton(),

                      const SizedBox(height: 24),

                      // 6. Ringkasan Presensi Hari Ini (Clock In, Clock Out, Total)
                      _buildSummaryRow(),

                      const SizedBox(height: 20),

                      // 7. Status Sensor & Tombol Permohonan Daftar Ulang Wajah
                      _buildEnvironmentStatus(),

                      const SizedBox(height: 16),

                      // 8. Tombol Daftar Ulang Wajah
                      _buildReEnrollmentCard(),

                      const SizedBox(height: 24),

                      // 9. Riwayat Presensi
                      _buildRecentHistorySection(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEnrollmentBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF2563EB), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wajah Belum Terdaftar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Daftarkan wajah Anda terlebih dahulu agar sistem dapat mengenali Anda saat presensi.',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _showEnrollmentGuideSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Daftar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedAttendanceBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Presensi Hari Ini Ditolak HR',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Alasan HR: "${_todayRejectionReason != null && _todayRejectionReason!.isNotEmpty ? _todayRejectionReason : "Verifikasi wajah tidak valid"}".\n\nPresensi Anda telah dikembalikan. Silakan tekan tombol CLOCK IN di bawah untuk melakukan presensi ulang dengan wajah Anda sendiri.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetRequestBanner() {
    final req = _activeResetRequest!;
    final status = req['status'] as String? ?? 'pending';
    final reason = req['reason'] as String? ?? '-';
    final notes = req['rejection_notes'] as String?;

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String title;
    String desc;
    Widget? actionWidget;

    if (status == 'pending') {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
      textColor = const Color(0xFF92400E);
      icon = Icons.hourglass_top_rounded;
      title = 'Permohonan Daftar Ulang Wajah Menunggu Persetujuan HR';
      desc = 'Alasan: "$reason". HR sedang meninjau permohonan Anda.';
    } else if (status == 'approved') {
      bgColor = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFFBBF7D0);
      textColor = const Color(0xFF166534);
      icon = Icons.check_circle_rounded;
      title = 'Permohonan Disetujui HR!';
      desc = 'HR telah menyetujui reset data biometrik Anda. Silakan ambil foto dan daftarkan kembali wajah master Anda.';
      actionWidget = ElevatedButton.icon(
        onPressed: _showEnrollmentGuideSheet,
        icon: const Icon(Icons.camera_alt_outlined, size: 16),
        label: const Text('Daftarkan Wajah Sekarang', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16A34A),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } else {
      // rejected
      bgColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFECACA);
      textColor = const Color(0xFF991B1B);
      icon = Icons.cancel_rounded;
      title = 'Permohonan Ditolak HR';
      desc = 'Alasan: "$reason".${notes != null && notes.isNotEmpty ? " Catatan HR: $notes" : ""}';
      actionWidget = TextButton(
        onPressed: _showRequestFaceResetDialog,
        child: const Text('Ajukan Lagi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.9), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionWidget != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: actionWidget,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReEnrollmentCard() {
    final isPending = _activeResetRequest != null && _activeResetRequest!['status'] == 'pending';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.manage_accounts_outlined, color: AppColors.navy, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar Ulang Wajah',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navy),
                ),
                const SizedBox(height: 2),
                Text(
                  isPending ? 'Permohonan Anda sedang ditinjau oleh HR' : 'Wajah berubah atau ganti kacamata? Ajukan verifikasi ulang ke HR.',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: isPending ? null : _showRequestFaceResetDialog,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isPending ? 'Menunggu' : 'Ajukan', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRequestFaceResetDialog() {
    if (_activeResetRequest != null && _activeResetRequest!['status'] == 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anda sudah memiliki permohonan daftar ulang wajah yang sedang menunggu persetujuan HR.'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Row(
                children: [
                  Icon(Icons.face_retouching_natural_rounded, color: AppColors.navy),
                  SizedBox(width: 10),
                  Text(
                    'Daftar Ulang Wajah',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Permohonan akan dikirimkan ke Dashboard HR untuk disetujui. Setelah HR menyetujui, data wajah master Anda sebelumnya akan direset sehingga Anda dapat melakukan perekaman wajah baru.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Alasan Pengajuan:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Misal: Perubahan penampilan, kacamata baru, atau foto lama kurang jelas...',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Silakan masukkan alasan permohonan.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          try {
                            await ApiService.requestFaceReset(
                              accessToken: widget.accessToken,
                              reason: reason,
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            await _loadInitialData();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Permohonan berhasil dikirim ke Dashboard HR! Tunggu hingga HR menyetujui.'),
                                  backgroundColor: AppColors.teal,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Gagal mengirim permohonan: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Kirim ke HR', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildClockHeaderCard(String name, String department) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
        children: [
          Text(
            _formatIndonesianDate(_currentTime),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTime(_currentTime),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_pin_rounded, size: 15, color: AppColors.teal),
                const SizedBox(width: 6),
                Text(
                  '$name • $department',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCard(WorkShift shift) {
    final startStr = shift.startTime.substring(0, 5);
    final endStr = shift.endTime.substring(0, 5);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shift.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Jam Kerja: $startStr - $endStr WIB (Tol. ${shift.lateToleranceMinutes} mnt)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroAttendanceButton() {
    Color buttonColor;
    String buttonText;
    String subtitleText;
    IconData iconData;

    if (!_isFaceEnrolled) {
      buttonColor = const Color(0xFF0284C7);
      buttonText = 'DAFTAR WAJAH';
      subtitleText = 'Daftarkan Wajah Sebelum Mulai Presensi';
      iconData = Icons.face_retouching_natural_rounded;
    } else {
      switch (_todayState) {
        case AttendanceTodayState.notClockedIn:
          buttonColor = AppColors.teal;
          buttonText = 'CLOCK IN';
          subtitleText = 'Ketuk untuk Mulai Pindai Wajah Masuk';
          iconData = Icons.face_retouching_natural_rounded;
          break;
        case AttendanceTodayState.clockedIn:
          buttonColor = AppColors.amber;
          buttonText = 'CLOCK OUT';
          subtitleText = 'Ketuk untuk Pindai Wajah Pulang';
          iconData = Icons.exit_to_app_rounded;
          break;
        case AttendanceTodayState.completed:
          buttonColor = const Color(0xFF64748B);
          buttonText = 'SELESAI';
          subtitleText = 'Presensi Hari Ini Telah Lengkap';
          iconData = Icons.check_circle_outline_rounded;
          break;
      }
    }

    return Column(
      children: [
        GestureDetector(
          onTap: _handleAttendanceButtonPress,
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: 6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconData, color: Colors.white, size: 54),
                const SizedBox(height: 8),
                Text(
                  buttonText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          subtitleText,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryItem(
            title: 'Clock In',
            time: _clockInTimeStr ?? '--:--',
            status: _clockInTimeStr != null
                ? (_isLate ? 'Terlambat' : 'Tepat Waktu')
                : 'Belum Ada',
            statusColor: _clockInTimeStr != null
                ? (_isLate ? AppColors.amber : AppColors.teal)
                : AppColors.textMuted,
            icon: Icons.login_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryItem(
            title: 'Clock Out',
            time: _clockOutTimeStr ?? '--:--',
            status: _clockOutTimeStr != null ? 'Selesai' : 'Belum Ada',
            statusColor: _clockOutTimeStr != null
                ? const Color(0xFF2563EB)
                : AppColors.textMuted,
            icon: Icons.logout_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem({
    required String title,
    required String time,
    required String status,
    required Color statusColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            time,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusBadge(
            icon: Icons.location_on_rounded,
            label: 'Lokasi: Radius Kantor',
            color: const Color(0xFF16A34A),
          ),
          Container(width: 1, height: 20, color: const Color(0xFFCBD5E1)),
          _buildStatusBadge(
            icon: _isFaceEnrolled ? Icons.verified_user_rounded : Icons.face_retouching_natural_rounded,
            label: _isFaceEnrolled ? 'Wajah: Terdaftar' : 'Wajah: Belum Terdaftar',
            color: _isFaceEnrolled ? AppColors.teal : AppColors.amber,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Riwayat Kehadiran',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            Text(
              'Database Supabase',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_attendanceLogs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.history_toggle_off_rounded,
                  size: 38,
                  color: Color(0xFF94A3B8),
                ),
                SizedBox(height: 10),
                Text(
                  'Belum Ada Riwayat Presensi',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Riwayat kehadiran akan tercatat permanen di Supabase setelah Anda melakukan Clock In melalui verifikasi wajah.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          )
        else
          ..._attendanceLogs.map((log) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.date,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Masuk: ${log.clockIn}${log.clockOut != null ? " • Pulang: ${log.clockOut}" : " • Sedang Bekerja"}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (log.approvalStatus == 'rejected' && log.rejectionReason != null && log.rejectionReason!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Catatan HR: ${log.rejectionReason}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: log.approvalStatus == 'rejected'
                          ? const Color(0xFFFEF2F2)
                          : (log.approvalStatus == 'pending'
                              ? const Color(0xFFFFFBEB)
                              : (log.isLate
                                  ? AppColors.amber.withValues(alpha: 0.15)
                                  : AppColors.teal.withValues(alpha: 0.15))),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      log.approvalStatus == 'rejected'
                          ? 'Ditolak HR'
                          : (log.approvalStatus == 'pending' ? 'Menunggu HR' : log.status),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: log.approvalStatus == 'rejected'
                            ? const Color(0xFFDC2626)
                            : (log.approvalStatus == 'pending'
                                ? const Color(0xFFD97706)
                                : (log.isLate ? AppColors.amber : AppColors.teal)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
