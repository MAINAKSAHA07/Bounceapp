# BounceBackTrainer

BounceBackTrainer is an iOS application designed to help athletes improve their ball control and accuracy through real-time video analysis and feedback. The app uses computer vision techniques to detect impacts, analyze ball trajectories, and provide instant feedback to users.

## Features

### Real-time Video Analysis
- **Pink Tape Detection**: Automatically detects fluorescent pink tape markers in the video feed
- **Impact Detection**: Identifies when and where the ball makes contact with the target
- **Target Tracking**: Detects and tracks the red bullseye target
- **Distance Measurement**: Calculates and displays the distance between impact points and target

### Smart Feedback System
- **Zone Analysis**: Divides the target area into 9 zones (3x3 grid) for precise impact analysis
- **Directional Feedback**: Provides specific feedback on how to adjust shots:
  - Vertical adjustments ("Try to kick higher/lower")
  - Horizontal adjustments ("Try to kick left/right")
  - Perfect shot recognition ("Nice shot! Right on target!")

### Technical Features
- **OpenCV Integration**: Utilizes OpenCV for advanced computer vision processing
- **Real-time Processing**: Processes video frames in real-time for instant feedback
- **Motion Detection**: Sophisticated motion detection algorithms to track ball movement
- **Color-based Detection**: Uses HSV color space for reliable pink tape and red target detection

## Requirements

### Hardware
- iOS device with camera
- Sufficient lighting for proper color detection
- Pink fluorescent tape for marking the target area
- Red bullseye target

### Software
- iOS 13.0 or later
- Xcode 12.0 or later
- OpenCV framework

## Setup Instructions

1. **Clone the Repository**
   ```bash
   git clone https://github.com/yourusername/Bounceapp.git
   cd BounceBackTrainer
   ```

2. **Install Dependencies**
   - Open the project in Xcode
   - Ensure OpenCV framework is properly linked
   - Install any required pods (if using CocoaPods)

3. **Build and Run**
   - Select your target device
   - Build and run the application

## Usage Guide

### Setting Up the Training Environment
1. Mark the target area with fluorescent pink tape
2. Place the red bullseye target in the desired location
3. Ensure proper lighting for optimal detection

### Using the App
1. Launch the app and grant camera permissions
2. Position the camera to capture both the target area and the training space
3. Start training:
   - The app will automatically detect the pink tape boundaries
   - The red bullseye will be tracked
   - Impacts will be detected and analyzed
   - Real-time feedback will be provided

### Understanding the Feedback
- **Green Rectangle**: Detected pink tape boundary
- **Yellow Circle**: Detected red bullseye target
- **Red Dot**: Impact point
- **Yellow Line**: Distance measurement
- **Text Overlay**: Zone information and feedback

## Technical Details

### Color Detection
- Pink Tape: HSV range (140-160, 100-255, 100-255)
- Red Target: HSV ranges (0-10, 100-255, 100-255) and (160-179, 100-255, 100-255)

### Motion Detection
- Minimum contour area: 500 pixels
- Frame difference threshold: 25

### Target Zones
The target area is divided into 9 zones:
```
Upper Left    | Upper Center    | Upper Right
Center Left   | Center          | Center Right
Lower Left    | Lower Center    | Lower Right
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- OpenCV community for the computer vision framework
- Contributors and testers who helped improve the application

## Support

For support, please open an issue in the GitHub repository or contact the development team.


