📸 Screenshot Cleaner (CVSD)
A Privacy-First AI Tool for Gallery Organization
Screenshot Cleaner is an intelligent, cross-platform mobile and desktop application designed to reclaim storage space by automatically detecting and removing unwanted screenshots, memes, and clutter from your photo library.

Unlike cloud-based cleaning tools, this application runs 100% locally on your device. Your photos are processed using an embedded neural network and never leave your phone or computer.

🚀 Key Features
100% On-Device Processing: Utilizes a custom-trained MobileNetV3 model converted to ONNX, enabling offline inference without internet access.

Privacy by Design: No photos, metadata, or thumbnails are ever uploaded to a server or cloud.

Smart Resume: Large gallery? No problem. The app saves your scan progress locally so you can pause and resume at any time.

Safe-List Memory: If you mark a photo as "Keep," its filename is stored locally to ensure it is never flagged again in future scans.

Cross-Platform: Native performance on both Android and macOS using the Flutter framework.

🔒 Privacy & Data Usage
We believe your gallery is private.

No Collection: This application does not collect, store, or transmit your personal photos.

Local Storage: The application only stores two pieces of data on your device's local storage:

The filenames/IDs of photos you have explicitly marked as "Keep" (to prevent re-flagging).

A temporary integer representing your current index in the gallery scan (to allow resuming).

No Analytics: There is no third-party tracking or behavioral analytics SDKs included in this build.

📥 Installation Guide
This application is distributed as a direct download and is not currently available on the App Store or Google Play Store.

🤖 Android
Download the app-release.apk from the Releases section of this repository.

Open the file on your Android device.

If prompted, go to Settings and enable "Install from Unknown Sources" for your browser or file manager.

Tap Install.

🍎 macOS
Download the MacApp.zip from the Releases section.

Unzip the file to reveal the Application.

Important: Because this app is not notarized by Apple, you cannot simply double-click it.

Right-click (or Control-click) the app icon.

Select Open from the context menu.

Click Open in the dialog box that appears to bypass the security warning.

(Optional) Grant "Full Disk Access" if prompted, to allow the app to scan your selected folders.

🛠️ Technical Stack
Framework: Flutter (Dart)

Computer Vision: PyTorch (Training) → ONNX (Inference)

Architecture: MobileNetV3 Small (Transfer Learning on ImageNet)

State Management: Provider / ChangeNotifier

Local Storage: Shared Preferences & PhotoManager API

⚠️ Disclaimer & Liability
PLEASE READ CAREFULLY BEFORE USE.

1. Use at Your Own Risk: This software is provided "as is," without warranty of any kind, express or implied. By using this software, you acknowledge that you are using it at your own risk.

2. Permanent Data Loss: This application is designed to delete files. While the Android version may utilize the system "Trash" (depending on OS version), the desktop versions generally perform a permanent deletion command (rm). Files deleted by this application may not be recoverable.

Always review the "Flagged" items carefully before tapping "Delete All."

We strongly recommend backing up your photo library before running a bulk delete operation.

3. Limitation of Liability: In no event shall the developers, Michael McIntosh, or the organization Golf Gooder LLC, be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software. This includes, but is not limited to, the accidental deletion of beloved photos, important documents, or system files.

📄 License
This project is licensed under the MIT License - see the LICENSE file for details.

Copyright © 2025 Michael McIntosh / Golf Gooder LLC. All Rights Reserved.