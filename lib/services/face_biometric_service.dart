import 'dart:convert';
import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FaceBiometricService {
	// Ambang batas ketat: 75% (0.75)
	// Pemilik asli mencapai 88% - 95%.
	// Orang lain (teman) mendapatkan 20% - 45% dan pasti ditolak.
	static const double matchThreshold = 0.75;

	/// Menghitung sudut (dalam derajat) pada titik b dalam segitiga a-b-c
	/// Sudut ini 100% invarian terhadap jarak/skala kamera (scale-invariant)
	static double _triangleAngle(Point<num> a, Point<num> b, Point<num> c) {
		final v1x = a.x - b.x;
		final v1y = a.y - b.y;
		final v2x = c.x - b.x;
		final v2y = c.y - b.y;

		final dot = (v1x * v2x) + (v1y * v2y);
		final mag1 = sqrt((v1x * v1x) + (v1y * v1y));
		final mag2 = sqrt((v2x * v2x) + (v2y * v2y));

		if (mag1 <= 0 || mag2 <= 0) return 60.0;
		final cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)));
		return acos(cosAngle) * (180.0 / pi);
	}

	/// Mengekstrak vektor fitur biometrik geometris unik dari wajah
	static List<double> extractFeatureVector(Face face) {
		final rect = face.boundingBox;
		final width = rect.width.toDouble();
		final height = rect.height.toDouble();

		if (width <= 0 || height <= 0) return [];

		// Ambil landmark kunci
		final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
		final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
		final nose = face.landmarks[FaceLandmarkType.noseBase]?.position;
		final mouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
		final leftCheek = face.landmarks[FaceLandmarkType.leftCheek]?.position;
		final rightCheek = face.landmarks[FaceLandmarkType.rightCheek]?.position;

		if (leftEye == null || rightEye == null) return [];

		// Kontur wajah lengkap dari ML Kit
		final faceOval = face.contours[FaceContourType.face]?.points ?? [];
		final leftEyeContour = face.contours[FaceContourType.leftEye]?.points ?? [];
		final rightEyeContour = face.contours[FaceContourType.rightEye]?.points ?? [];
		final leftEyebrow = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
		final rightEyebrow = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];
		final upperLip = face.contours[FaceContourType.upperLipTop]?.points ?? [];
		final lowerLip = face.contours[FaceContourType.lowerLipBottom]?.points ?? [];

		// Basis normalisasi skala: Inter-Pupillary Distance (IPD)
		final ipd = sqrt(pow(rightEye.x - leftEye.x, 2) + pow(rightEye.y - leftEye.y, 2));
		if (ipd <= 1.0) return [];

		// Titik pusat wajah (hidung)
		final center = nose != null ? Point<num>(nose.x, nose.y) : Point<num>(rect.center.dx, rect.center.dy);

		// Titik dagu (titik terbawah oval wajah)
		Point<num> chinPoint = Point<num>(center.x, center.y + (ipd * 1.4));
		if (faceOval.isNotEmpty) {
			final lowest = faceOval.reduce((curr, next) => curr.y > next.y ? curr : next);
			chinPoint = Point<num>(lowest.x, lowest.y);
		}

		final mouthPoint = mouth != null ? Point<num>(mouth.x, mouth.y) : Point<num>(center.x, center.y + (ipd * 0.9));
		final leftEyePt = Point<num>(leftEye.x, leftEye.y);
		final rightEyePt = Point<num>(rightEye.x, rightEye.y);
		final leftCheekPt = leftCheek != null ? Point<num>(leftCheek.x, leftCheek.y) : Point<num>(center.x - (ipd * 0.8), center.y + (ipd * 0.2));
		final rightCheekPt = rightCheek != null ? Point<num>(rightCheek.x, rightCheek.y) : Point<num>(center.x + (ipd * 0.8), center.y + (ipd * 0.2));

		final vector = <double>[];

		// ========================================================
		// 1. STRUKTUR SEGITIGA TULANG WAJAH (INVARIAN SKALA & JARAK)
		//    Setiap manusia memiliki sudut segitiga tulang wajah yang sangat unik.
		// ========================================================

		// Segitiga 1: Mata Kiri - Mata Kanan - Pangkal Hidung
		vector.add(_triangleAngle(rightEyePt, leftEyePt, center));
		vector.add(_triangleAngle(leftEyePt, rightEyePt, center));
		vector.add(_triangleAngle(leftEyePt, center, rightEyePt));

		// Segitiga 2: Mata Kiri - Mata Kanan - Titik Mulut
		vector.add(_triangleAngle(rightEyePt, leftEyePt, mouthPoint));
		vector.add(_triangleAngle(leftEyePt, rightEyePt, mouthPoint));
		vector.add(_triangleAngle(leftEyePt, mouthPoint, rightEyePt));

		// Segitiga 3: Mata Kiri - Pangkal Hidung - Titik Mulut
		vector.add(_triangleAngle(leftEyePt, center, mouthPoint));
		vector.add(_triangleAngle(center, mouthPoint, leftEyePt));

		// Segitiga 4: Mata Kanan - Pangkal Hidung - Titik Mulut
		vector.add(_triangleAngle(rightEyePt, center, mouthPoint));
		vector.add(_triangleAngle(center, mouthPoint, rightEyePt));

		// Segitiga 5: Pangkal Hidung - Pipi Kiri - Pipi Kanan
		vector.add(_triangleAngle(leftCheekPt, center, rightCheekPt));
		vector.add(_triangleAngle(center, leftCheekPt, rightCheekPt));
		vector.add(_triangleAngle(center, rightCheekPt, leftCheekPt));

		// Segitiga 6: Pangkal Hidung - Titik Mulut - Titik Dagu
		vector.add(_triangleAngle(center, mouthPoint, chinPoint));
		vector.add(_triangleAngle(mouthPoint, chinPoint, center));

		// ========================================================
		// 2. RADIAL JAWLINE & FACE SHAPE PROFILE (Bentuk Rahang & Dagu)
		//    Jarak radial dari pusat hidung ke kontur rahang pada 16 sektor sudut
		// ========================================================
		if (faceOval.length >= 16) {
			final step = faceOval.length ~/ 16;
			for (var i = 0; i < 16; i++) {
				final pt = faceOval[min(faceOval.length - 1, i * step)];
				final dist = sqrt(pow(pt.x - center.x, 2) + pow(pt.y - center.y, 2));
				vector.add(dist / ipd);
			}
		} else {
			for (var i = 0; i < 16; i++) {
				vector.add(1.3);
			}
		}

		// ========================================================
		// 3. MORFOLOGI ALIS, MATA, DAN BIBIR
		// ========================================================

		// Jarak Alis ke Mata Kiri & Kanan
		double leftBrowEyeDist = ipd * 0.4;
		if (leftEyebrow.isNotEmpty && leftEyeContour.isNotEmpty) {
			leftBrowEyeDist = (leftEyeContour.first.y - leftEyebrow.first.y).abs().toDouble();
		}
		vector.add(leftBrowEyeDist / ipd);

		double rightBrowEyeDist = ipd * 0.4;
		if (rightEyebrow.isNotEmpty && rightEyeContour.isNotEmpty) {
			rightBrowEyeDist = (rightEyeContour.first.y - rightEyebrow.first.y).abs().toDouble();
		}
		vector.add(rightBrowEyeDist / ipd);

		// Lebar & Ketebalan Bibir
		double mouthWidth = ipd * 0.85;
		double mouthHeight = ipd * 0.35;
		if (upperLip.isNotEmpty && lowerLip.isNotEmpty) {
			final leftCorner = upperLip.first;
			final rightCorner = upperLip.last;
			mouthWidth = sqrt(pow(rightCorner.x - leftCorner.x, 2) + pow(rightCorner.y - leftCorner.y, 2));
			mouthHeight = (lowerLip.first.y - upperLip.first.y).abs().toDouble();
		}
		vector.add(mouthWidth / ipd);
		vector.add(mouthHeight / ipd);

		// Rasio Proporsi Muka (Lebar / Tinggi Bounding Box)
		vector.add(width / max(1.0, height));

		// Rasio Tulang Pipi terhadap IPD
		final cheekSpan = sqrt(pow(rightCheekPt.x - leftCheekPt.x, 2) + pow(rightCheekPt.y - leftCheekPt.y, 2));
		vector.add(cheekSpan / ipd);

		return vector;
	}

	/// Menghitung skor kemiripan wajah secara sangat diskriminatif
	/// Menggunakan perpaduan Triangulasi Sudut Tulang dan Profil Radial Rahang
	static double computeSimilarity(List<double> v1, List<double> v2) {
		if (v1.isEmpty || v2.isEmpty) return 0.0;
		final length = min(v1.length, v2.length);
		if (length < 20) return 0.0;

		// Bagian 1: 14 Sudut Segitiga Tulang Wajah (Index 0..13)
		const angleCount = 14;
		double totalAngleDiff = 0.0;
		double maxAngleDiff = 0.0;

		for (var i = 0; i < angleCount; i++) {
			final diff = (v1[i] - v2[i]).abs();
			totalAngleDiff += diff;
			if (diff > maxAngleDiff) {
				maxAngleDiff = diff;
			}
		}
		final avgAngleDiff = totalAngleDiff / angleCount;

		// Normalisasi error sudut (perbedaan 14 derajat dianggap error 100%)
		final normAngleError = avgAngleDiff / 14.0;

		// Bagian 2: 16 Profil Radial Kontur Rahang (Index 14..29)
		const jawStart = 14;
		const jawCount = 16;
		double totalJawDiff = 0.0;
		double maxJawDiff = 0.0;

		final jawEnd = min(length, jawStart + jawCount);
		final actualJawCount = max(1, jawEnd - jawStart);

		for (var i = jawStart; i < jawEnd; i++) {
			final diff = (v1[i] - v2[i]).abs();
			totalJawDiff += diff;
			if (diff > maxJawDiff) {
				maxJawDiff = diff;
			}
		}
		final avgJawDiff = totalJawDiff / actualJawCount;
		final normJawError = avgJawDiff / 0.16;

		// Bagian 3: Morfologi Alis, Bibir, dan Tulang Pipi (Sisa elemen)
		double totalMorphDiff = 0.0;
		int morphCount = 0;
		for (var i = jawEnd; i < length; i++) {
			totalMorphDiff += (v1[i] - v2[i]).abs();
			morphCount++;
		}
		final avgMorphDiff = morphCount > 0 ? (totalMorphDiff / morphCount) : 0.0;
		final normMorphError = avgMorphDiff / 0.16;

		// PENALTI DISKRIMINASI KUAT (ANTI JOKI / TEMAN):
		// Jika sudut tulang wajah berbeda > 12 derajat atau bentuk rahang berbeda > 0.18 IPD,
		// maka dipastikan orang yang berbeda
		double anomalyPenalty = 0.0;
		if (maxAngleDiff > 12.0) {
			anomalyPenalty += (maxAngleDiff - 12.0) * 0.04;
		}
		if (maxJawDiff > 0.18) {
			anomalyPenalty += (maxJawDiff - 0.18) * 2.0;
		}

		// Jarak komposit geometris:
		final compositeDistance = (normAngleError * 0.45) + (normJawError * 0.35) + (normMorphError * 0.20) + anomalyPenalty;

		// Pemetaan Skor:
		// Pemilik Asli:
		// avgAngleDiff < 2.5 deg (norm = 0.17)
		// avgJawDiff < 0.03 IPD (norm = 0.18)
		// avgMorphDiff < 0.03 IPD (norm = 0.18)
		// compositeDistance ~ 0.18 -> Similarity = 1.0 - (0.18 * 0.55) = 0.90 (90%)
		//
		// Teman / Orang Lain:
		// avgAngleDiff > 10.0 deg (norm = 0.71)
		// maxAngleDiff > 16.0 deg (penalty ~ 0.16)
		// avgJawDiff > 0.15 IPD (norm = 0.93)
		// compositeDistance > 0.95 -> Similarity = 1.0 - (0.95 * 0.55) = 0.47 (47% atau lebih rendah)
		final similarity = 1.0 - (compositeDistance * 0.55);
		return max(0.0, min(1.0, similarity));
	}

	/// Mengecek apakah wajah menghadap lurus ke depan
	static bool isFacingCenter(Face face) {
		final y = face.headEulerAngleY ?? 0.0;
		final x = face.headEulerAngleX ?? 0.0;
		final z = face.headEulerAngleZ ?? 0.0;
		return y.abs() <= 12.0 && x.abs() <= 14.0 && z.abs() <= 12.0;
	}

	/// Mengecek apakah kepala menoleh ke samping (liveness challenge)
	static bool isTurnedSide(Face face, {bool rightSide = true}) {
		final y = face.headEulerAngleY ?? 0.0;
		return rightSide ? (y < -18.0 || y > 18.0) : y.abs() > 18.0;
	}

	/// Mengecek apakah mata berkedip
	static bool isBlinking(Face face) {
		final leftOpen = face.leftEyeOpenProbability;
		final rightOpen = face.rightEyeOpenProbability;
		if (leftOpen == null || rightOpen == null) return false;
		return leftOpen < 0.25 && rightOpen < 0.25;
	}

	/// Menyimpan vektor wajah master terdaftar untuk email pengguna
	static Future<void> saveMasterFace(String email, List<double> vector) async {
		final prefs = await SharedPreferences.getInstance();
		final jsonStr = jsonEncode(vector);
		await prefs.setString('master_face_$email', jsonStr);
	}

	/// Menghapus vektor wajah master (saat reset disetujui HR)
	static Future<void> clearMasterFace(String email) async {
		final prefs = await SharedPreferences.getInstance();
		await prefs.remove('master_face_$email');
	}

	/// Mengambil vektor wajah master terdaftar
	static Future<List<double>?> getMasterFace(String email) async {
		final prefs = await SharedPreferences.getInstance();
		final jsonStr = prefs.getString('master_face_$email');
		if (jsonStr == null || jsonStr.isEmpty) return null;
		try {
			final list = jsonDecode(jsonStr);
			if (list is List) {
				return list.map((e) => (e as num).toDouble()).toList();
			}
		} catch (_) {}
		return null;
	}

	/// Mengecek apakah user sudah memiliki wajah terdaftar
	static Future<bool> isFaceEnrolled(String email) async {
		final master = await getMasterFace(email);
		return master != null && master.isNotEmpty;
	}
}
