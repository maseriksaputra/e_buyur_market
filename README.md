<div align="center">
  
  # 🛒 E-Buyur Market
  **Intelligent Agri-Marketplace Powered by AI & Big Data**

  [![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](#)
  [![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](#)
  [![AI Ready](https://img.shields.io/badge/AI_Integration-Hybrid_Computer_Vision-FF6F00?style=for-the-badge&logo=google-gemini&logoColor=white)](#)
  [![UI/UX](https://img.shields.io/badge/Frontend_Only-Repository-8A2BE2?style=for-the-badge&logo=appveyor&logoColor=white)](#)

  <p align="center">
    Sebuah platform revolusioner yang menghubungkan petani, penjual, dan pembeli melalui sistem <i>marketplace</i> berbasis Kecerdasan Buatan (AI) untuk mendeteksi kelayakan buah dan sayuran, serta didukung oleh analitik Big Data untuk memantau tren pasar.
  </p>

</div>

---

## ⚠️ Repository Scope (Frontend Only)

> **Important Note:** This repository contains **strictly the Frontend/UI implementation** built with Flutter and Dart. 
> The Backend API (Laravel/PHP), Database architectures, Big Data pipelines, and the proprietary AI Inference models (YOLO / MobileNet for object detection and quality segmentation) are hosted on private servers and are **not included** in this public repository.

---

## ✨ Key Features & Capabilities

<details>
<summary><b>🤖 1. AI-Powered Quality Detection (Hybrid AI)</b></summary>

* **Computer Vision Integration:** Sellers and buyers can scan agricultural products using their device camera.
* **Freshness Grading:** The app communicates with external AI APIs to segment and classify the freshness, ripeness, and quality of fruits/vegetables in real-time.
</details>

<details>
<summary><b>📈 2. Big Data & Analytics Dashboard</b></summary>

* **Seller Insights:** Visualizes market demands, sales velocity, and product performance using complex data aggregations.
* **Buyer Stats:** Personalized shopping habits, favorite categories, and dynamic product recommendations driven by backend big data algorithms.
</details>

<details>
<summary><b>👥 3. Multi-Role Architecture</b></summary>

* **Unified App:** A single codebase seamlessly handles both `Buyer` and `Seller` roles using robust Route Resolvers and Role Guards (`AuthGate`).
* **Seller Tools:** Inventory management, order tracking, and a feature to "Create Product from Scan".
* **Buyer Experience:** Modern checkout flow, cart state management, and real-time search filtering.
</details>

<details>
<summary><b>⚡ 4. Modern Tech Stack & State Management</b></summary>

* **Provider Pattern:** Efficient UI rendering using scoped providers (`AuthProvider`, `CartProvider`, `CheckoutProvider`, etc.).
* **Network Handling:** Robust API communication handled via `Dio` with custom interceptors and `.env` configuration for secure credential management.
</details>

---

## 📱 App Previews (UI Showcase)

| Buyer Dashboard | AI Scanner Mode | AI Analysis Detail | Seller Dashboard |
|:---:|:---:|:---:|:---:|
| <img src="https://github.com/user-attachments/assets/ba537116-dce0-4e04-bdcb-82c93e22e6c8" width="200"/> | <img src="https://github.com/user-attachments/assets/0ee100f0-ef1b-4892-82bc-ab5dfec784df" width="200"/> | <img src="https://github.com/user-attachments/assets/10b698fe-1f86-4ed4-91b2-e5e84f2145a5" width="200"/> | <img src="https://github.com/user-attachments/assets/24e36cd4-dc62-4829-be03-90c36a189a60" width="200"/> |
---

## 🏗️ Project Structure Highlights

The architecture strictly follows a modular, feature-based design:

```text
lib/
├── app/
│   ├── common/         # Shared UI components and models
│   ├── core/           # Routing, Theme, and API network configs
│   ├── features/       # Feature-driven modules (e.g., Seller Products)
│   └── presentation/   # State Providers and Application Screens
│       ├── auth/       # Login, Register, Token Store
│       ├── buyer/      # Cart, Checkout, Dashboard
│       └── seller/     # Dashboard, Management, Scan UI
├── ml/                 # AI Service Integrations & Ping utilities
└── main.dart           # App entry point & dependency injection
🚀 Getting Started (Mock Environment)
Since the backend is not included, you will need to set up a mock server or update the API base URLs to run this frontend locally.

Prerequisites
Flutter SDK (Version 3.10+ recommended)

Dart SDK

Installation
Clone the repository:

Bash
git clone [https://github.com/maseriksaputra/e-buyur-market-frontend.git](https://github.com/maseriksaputra/e-buyur-market-frontend.git)
cd e-buyur-market-frontend
Setup Environment Variables:
Create a .env file in the root directory and add your mock API URLs:

Cuplikan kode
API_BASE_URL=http://localhost:8000/api/v1/
API_BEARER=your_mock_token_here
AI_PING=true
Install Dependencies:

Bash
flutter pub get
Run the Application:

Bash
flutter run
👨‍💻 Developer & Author
Erika Dwi Saputra Full Stack Developer | Software Engineer

I specialize in building intelligent applications combining modern web/mobile frameworks (Flutter, Laravel, JS) with cutting-edge AI architectures (YOLO, MobileNet).

📫 Connect with me:

LinkedIn
https://www.linkedin.com/in/erika-dwi-saputra-811403262/


Built with passion and ☕ in Grobogan, Central Java.
