# CardioScope: AI-Powered Heart Sound Analysis 🩺

**CardioScope** is a deep learning-integrated system featuring a custom-built wireless stethoscope and a mobile application for the real-time, non-invasive detection of Mitral Valve Disease (MVD).

This project aims to bridge the diagnostic gap in underserved regions by providing an affordable and accurate alternative to traditional auscultation and expensive echocardiograms[cite: 56, 63, 293]. [cite_start]The system is designed to classify heart sounds into four categories: **Normal**, **Mitral Regurgitation (MR)**, **Mitral Stenosis (MS)**, and **Mitral Valve Prolapse (MVP)**[cite: 305, 310].

---
## 📋 Key Features

* [cite_start]**Real-Time Classification**: Utilizes a novel hybrid **Temporal Convolutional Network (TCN) and Spiking Neural Network (SNN)** model for instant, on-device diagnosis[cite: 309, 950].
* [cite_start]**Low-Latency Wireless Stethoscope**: Features a custom-built stethoscope that transmits audio via a **2.4 GHz RF protocol** and a USB-C receiver for minimal delay, which is critical for accurate cardiac analysis [cite: 1019-1021].
* [cite_start]**Offline Functionality**: All recording, analysis, and data storage are performed locally on the device, ensuring the app is fully functional without an internet connection and maintains patient privacy[cite: 430, 1101].
* [cite_start]**Real-Time Waveform Visualization**: The app displays heart sound waveforms as they are being captured, providing immediate visual feedback to the healthcare provider[cite: 1104].
* **Local Data & Report Management**: Patient data and diagnostic results are stored in a local **SQLite database**. [cite_start]The app can generate and export detailed PDF reports for medical records or consultations[cite: 951, 1143, 1181].

---
## 🛠️ Technology Stack

* **Mobile Framework**: Flutter
* **Programming Language**: Dart
* **AI Model Deployment**: TensorFlow Lite (TFLite)
* **Local Database**: SQLite
* **Audio Preprocessing (for model training)**: Librosa (Python)

---
## ⚙️ System Architecture & Workflow

[cite_start]The CardioScope system follows a streamlined workflow to ensure efficient and accurate analysis from sound capture to diagnosis [cite: 1054-1055]:

1.  [cite_start]**Capture**: The stethoscope's chestpiece captures acoustic heart sounds[cite: 1057].
2.  [cite_start]**Digitize & Transmit**: An embedded microphone converts the sound to an electrical signal, which is then digitized and transmitted wirelessly via a 2.4 GHz RF signal [cite: 1059-1060, 1062].
3.  [cite_start]**Receive**: A compact USB-C receiver plugs into the mobile device, capturing the wireless signal and delivering the digital audio stream to the app [cite: 1063-1064, 1066].
4.  [cite_start]**Analyze & Classify**: The mobile app preprocesses the audio and feeds it into the onboard **TCN-SNN model**, which classifies the heart sound in real-time (~220 ms inference latency)[cite: 950, 1266].
5.  **Display & Store**: The final diagnosis, confidence score, and waveform are displayed to the user. [cite_start]The results can then be saved locally to the device[cite: 951, 1069].

---
## 📱 Application Screenshots

*(You can replace the empty spaces with your own app screenshots)*

| Onboarding | Dashboard | Recording |
| :---: | :---: | :---: |
| | | |
| **Results (Normal)** | **Results (Mitral Regurgitation)** | **Saved Reports** |
| | | |

---
## 🚀 Getting Started

To get a local copy up and running, follow these simple steps.

### Prerequisites
* Flutter SDK
* Android Studio or VS Code

### Installation
1.  Clone the repo
    ```sh
    git clone [https://github.com/LadyJo02/cardioscope_app.git](https://github.com/LadyJo02/cardioscope_app.git)
    ```
2.  Navigate to the project directory
    ```sh
    cd cardioscope_app
    ```
3.  Install dependencies
    ```sh
    flutter pub get
    ```
4.  Run the app
    ```sh
    flutter run
    ```

---
## 🧑‍💻 Authors

[cite_start]This capstone project was developed by[cite: 6]:
* **Genheylou Deligero Felisilda**
* **Nicole Suerte Menorias**
* **Kobe Marco Gamus Olaguir**
* **Joanna Reyda Daquipel Santos**

---
## ⚖️ License

Distributed under the MIT License. See `LICENSE` for more information.
