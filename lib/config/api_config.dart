
String resolveApiBaseUrl() {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  // IP lokal Wi-Fi laptop agar dapat diakses oleh HP fisik maupun emulator
  return 'http://192.168.1.16:3000/api/v1';
}

final apiBaseUrl = resolveApiBaseUrl();
