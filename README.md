# CardioScope: AI-Powered Heart Sound Analysis 🩺

**CardioScope** is a deep learning-integrated system featuring a custom-built wireless stethoscope and a mobile application for the real-time, non-invasive detection of Mitral Valve Disease (MVD).

This project aims to bridge the diagnostic gap in underserved regions by providing an affordable and accurate alternative to traditional auscultation and expensive echocardiograms. The system is designed to classify heart sounds into four categories: **Normal**, **Mitral Regurgitation (MR)**, **Mitral Stenosis (MS)**, and **Mitral Valve Prolapse (MVP)**.

---
## 📋 Key Features

**Real-Time Classification**: Utilizes a novel hybrid **Temporal Convolutional Network (TCN) and Spiking Neural Network (SNN)** model for instant, on-device diagnosis.
**Low-Latency Wireless Stethoscope**: Features a custom-built stethoscope that transmits audio via a **2.4 GHz RF protocol** and a USB-C receiver for minimal delay, which is critical for accurate cardiac analysis.
**Offline Functionality**: All recording, analysis, and data storage are performed locally on the device, ensuring the app is fully functional without an internet connection and maintains patient privacy
**Real-Time Waveform Visualization**: The app displays heart sound waveforms as they are being captured, providing immediate visual feedback to the healthcare provider.
**Local Data & Report Management**: Patient data and diagnostic results are stored in a local **SQLite database**. The app can generate and export detailed PDF reports for medical records or consultations.

---
## 🛠️ Technology Stack

* **Mobile Framework**: Flutter
* **Programming Language**: Dart
* **AI Model Deployment**: TensorFlow Lite (TFLite)
* **Local Database**: SQLite
* **Audio Preprocessing (for model training)**: Librosa (Python)

---
## ⚙️ System Architecture & Workflow

The CardioScope system follows a streamlined workflow to ensure efficient and accurate analysis from sound capture to diagnosis:

1. **Capture**: The stethoscope's chestpiece captures acoustic heart sounds.
2.  **Digitize & Transmit**: An embedded microphone converts the sound to an electrical signal, which is then digitized and transmitted wirelessly via a 2.4 GHz RF signal.
3.  **Receive**: A compact USB-C receiver plugs into the mobile device, capturing the wireless signal and delivering the digital audio stream to the app.
4.  **Analyze & Classify**: The mobile app preprocesses the audio and feeds it into the onboard **TCN-SNN model**, which classifies the heart sound in real-time (~220 ms inference latency).
5.  **Display & Store**: The final diagnosis, confidence score, and waveform are displayed to the user. The results can then be saved locally to the device.

---
## 📱 Application Screenshots


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

This capstone project was developed by[cite: 6]:
* **Genheylou Deligero Felisilda**
* **Nicole Suerte Menorias**
* **Kobe Marco Gamus Olaguir**
* **Joanna Reyda Daquipel Santos**

---
## ⚖️ License

Distributed under the MIT License. See `LICENSE` for more information.
