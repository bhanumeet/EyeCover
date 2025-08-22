# EyeCover Test - Automated Eye Cover App for ophthalmologists 

<img width="1536" height="1024" alt="ChatGPT Image Aug 22, 2025 at 05_29_42 PM" src="https://github.com/user-attachments/assets/78fe0a3f-a41b-4541-98aa-6dd2c438af1c" />

## Overview

EyeCover is an iOS application designed specifically for ophthalmologists and eye care professionals to capture standardized eye cover test photographs. The app automatically detects when an eye cover is removed and captures the image at the precise moment, ensuring consistent and reliable documentation of eye examinations.

## Features

### 🔍 **Automatic Eye Detection**
- Real-time eye detection using custom trainer CoreML model
- Intelligent detection of one or both eyes
- Confidence-based filtering for accurate results

### 📸 **Smart Capture System**
- **Automatic Capture**: Takes photo automatically when both eyes are detected after cover removal
- **Flash Control**: Toggle flash for optimal lighting conditions
- **Front/Back Camera Support**: Switch between cameras for different examination needs

### 👁️ **Eye Cover Modes**
- **LC (Left Covered)**: For left eye cover tests
- **RC (Right Covered)**: For right eye cover tests  
- **AC (Alternating Cover)**: For alternating cover tests

### ✨ **Additional Features**
- **Text Overlay**: Add patient ID or notes directly on captured images
- **Validation System**: Alerts when selected mode doesn't match detected eye pattern
- **Save to Photo Library**: Easy storage and retrieval of examination photos
- **Visual Feedback**: Real-time bounding boxes around detected eyes

## Requirements

- iOS 13.0+
- Xcode 12.0+
- Swift 5.0+
- iPhone/iPad with camera
- CoreML model file (`bestNMS.mlmodel`)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/EyeDetector.git
```

2. Open the project in Xcode:
```bash
cd EyeDetector
open EyeDetector.xcodeproj
```

3. Add the CoreML model:
   - Place your `bestNMS.mlmodel` file in the project directory
   - Ensure it's added to the app target

4. Configure permissions in `Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to capture eye examination photos</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs photo library access to save examination photos</string>
```

5. Build and run the project on a physical device (camera not available in simulator)

## Usage

### Basic Operation

1. **Launch the app** - Camera preview will start automatically

2. **Select examination mode**:
   - Tap the segmented control to choose LC, RC, or AC mode
   - Enter patient ID or notes in the text field (optional)

3. **Position the patient**:
   - Ensure patient's face is within the white guide box
   - Maintain proper distance for optimal detection

4. **Enable capture mode**:
   - Tap the capture button to enable flash/capture mode
   - Button turns yellow when active

5. **Perform the cover test**:
   - Cover the appropriate eye(s) based on selected mode
   - Remove the cover - photo captures automatically when both eyes are detected

6. **Review and save**:
   - Review the captured image with overlaid information
   - Tap "Save" to store in photo library
   - Tap "Retake" to capture again



**Last Updated**: 2024  
**Developed for**: Ophthalmology Professionals
