# Flutter DocuSign App

## Overview
The Flutter DocuSign App is a mobile application that allows users to read and edit fillable PDF forms. It includes features for capturing signatures and placing them over specific fields in the PDF, making it ideal for document signing and form filling.

## Features
- View PDF documents
- Edit fillable PDF fields
- Capture and draw signatures
- Place signatures over specified read-only fields in the PDF
- Support for multiple editable fields

## Project Structure
```
flutter_docusign_app
├── android                # Android-specific files
├── lib                    # Flutter application code
│   ├── main.dart          # Entry point of the application
│   ├── screens            # UI screens for the app
│   ├── services           # Services for PDF and signature handling
│   ├── widgets            # Reusable widgets
│   └── models             # Data models
├── assets                 # Assets like fonts and sample forms
├── test                   # Unit and widget tests
├── pubspec.yaml           # Flutter project configuration
├── .gitignore             # Files to ignore in version control
└── analysis_options.yaml   # Dart analysis options
```

## Getting Started

### Prerequisites
- Flutter SDK installed
- Android Studio or another IDE for Flutter development
- An emulator or physical device for testing

### Installation
1. Clone the repository:
   ```
   git clone <repository-url>
   ```
2. Navigate to the project directory:
   ```
   cd flutter_docusign_app
   ```
3. Install dependencies:
   ```
   flutter pub get
   ```

### Running the App
To run the app on an emulator or connected device, use:
```
flutter run
```

### Usage
- Open the app and navigate to the home screen.
- Select a PDF form to view and edit.
- Use the signature capture screen to draw your signature.
- Place the signature over the desired fields in the PDF.

## Contributing
Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes.

## License
This project is licensed under the MIT License. See the LICENSE file for details.