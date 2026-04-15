/// Konfigurasi ML terpusat agar konsisten di semua service.
class MlConfig {
  // Ambang penentuan "Layak"
  static const int ambangLayak = 70;

  // YOLO → ROI (pakai ketika deteksi cukup yakin)
  static const double yoloMinConf = 0.40;   // sebelumnya 0.55; turunkan agar lebih sering terpakai

  // Heuristik luma (0..1) untuk ngecek ROI gelap
  static const double roiDarkThresh = 0.40;     // ROI < 0.40 = gelap
  static const double fullBrightThresh = 0.50;  // full-frame >= 0.50 = cukup terang

  // Kapan LLM dipanggil
  static const int llmCooldownSec = 5; // sudah ada di UI; catatan saja
  static const int borderlineMin = 50;
  static const int borderlineMax = 70;

  // Bobot fusing
  // Borderline: bobot LLM 0.30..0.50 (naik mengikuti confidence LLM)
  static const double fuseBorderlineLlmBase = 0.30;
  static const double fuseBorderlineLlmGain = 0.20;

  // Non-borderline: bobot LLM 0.15..0.25
  static const double fuseNonBorderlineLlmBase = 0.15;
  static const double fuseNonBorderlineLlmGain = 0.10;
}
