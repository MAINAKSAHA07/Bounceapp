#import "OpenCVWrapper.h"

// Workaround Apple 'NO' macro conflict with OpenCV stitching
#ifdef NO
    #undef NO
    #define __RESTORE_NO_MACRO__
#endif

#import <opencv2/opencv.hpp>

#ifdef __RESTORE_NO_MACRO__
    #define NO 0
    #undef __RESTORE_NO_MACRO__
#endif

// Structure to hold target information
struct Target {
    cv::Rect boundingBox;
    bool isCircular;
    int targetNumber;
    cv::Point center;
    double radius;  // Only used for circular targets
    std::vector<cv::Vec3f> circles;  // For storing circular patterns
    int quadrant;
    
    Target() : boundingBox(-1, -1, -1, -1), isCircular(false), targetNumber(0), 
               center(-1, -1), radius(0), quadrant(0) {}
};

// Forward declarations for helper functions
static std::string analyzeTrajectory(const std::vector<cv::Point>& trajectory, 
                                    const Target& target, int frameWidth, int frameHeight);
static cv::Point predictNextPosition(const std::vector<cv::Point>& trajectory);
static cv::Point detectBallByShape(const cv::Mat& frame);
static cv::Point detectBallByColor(const cv::Mat& frame);
static cv::Point detectBallByMotion(const cv::Mat& gray, cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2);
static std::vector<Target> detectTargets(const cv::Mat& frame, std::vector<cv::Rect>& tapeRects);
static Target detectCircularTarget(const cv::Mat& frame);

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    std::string version = CV_VERSION;
    return [NSString stringWithUTF8String:version.c_str()];
}

+ (void)analyzeVideo:(NSString *)inputPath outputPath:(NSString *)outputPath {
    if (!inputPath || !outputPath) {
        NSLog(@"[OpenCV] Nil input or output path received");
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            std::string input = [inputPath UTF8String];
            std::string output = [outputPath UTF8String];
            
            cv::VideoCapture cap(input);
            if (!cap.isOpened()) {
                NSLog(@"Error: Could not open input video.");
                return;
            }
            
            int width = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
            int height = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));
            double fps = cap.get(cv::CAP_PROP_FPS);
            
            NSLog(@"[OpenCV] Video properties - Width: %d, Height: %d, FPS: %f", width, height, fps);
            
            // Target and goal boundary detection variables
            std::vector<Target> targets;
            std::vector<cv::Rect> tapeRects;
            cv::Rect goalBoundary(0, 0, width, height); // Default to full frame
            bool goalBoundaryLocked = false;
            bool targetsDetected = false;
            int targetDetectionAttempts = 0;
            const int MAX_DETECTION_ATTEMPTS = 30; // Increased attempts for scene setup
            
            // Quadrant definitions - will be updated once goal is locked
            int midX = width / 2;
            int midY = height / 2;
            auto getQuadrant = [&](cv::Point pt) -> int {
                if (pt.x < midX && pt.y < midY) return 1; // Top-Left
                if (pt.x >= midX && pt.y < midY) return 2; // Top-Right
                if (pt.x < midX && pt.y >= midY) return 3; // Bottom-Left
                return 4; // Bottom-Right
            };

            // Try 'MJPG' codec for .avi compatibility
            cv::VideoWriter writer(output, cv::VideoWriter::fourcc('M','J','P','G'), fps, cv::Size(width, height));
            if (!writer.isOpened()) {
                NSLog(@"Error: Could not create output video writer. Path: %s, Size: %dx%d, FPS: %f", output.c_str(), width, height, fps);
                return;
            }
            NSLog(@"[OpenCV] Output writer created. Path: %s, Size: %dx%d, FPS: %f", output.c_str(), width, height, fps);
            
            // Background Subtractor for motion detection
            cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2 = cv::createBackgroundSubtractorMOG2();
            
            // Ball tracking variables
            std::vector<cv::Point> ballTrajectory;
            cv::Point lastBallPosition(-1, -1);
            bool ballDetected = false;
            int framesWithoutBall = 0;
            const int MAX_FRAMES_WITHOUT_BALL = 30;
            
            // Kalman filter for ball prediction
            cv::KalmanFilter kalman(4, 2, 0);
            kalman.transitionMatrix = (cv::Mat_<float>(4, 4) << 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1);
            kalman.measurementMatrix = (cv::Mat_<float>(2, 4) << 1, 0, 0, 0, 0, 1, 0, 0);
            kalman.processNoiseCov = cv::Mat::eye(4, 4, CV_32F) * 1e-4;
            kalman.measurementNoiseCov = cv::Mat::eye(2, 2, CV_32F) * 1e-1;
            kalman.errorCovPost = cv::Mat::eye(4, 4, CV_32F);
            
            cv::Mat frame, outputFrame;
            cv::Mat prevGray;
            int frameCount = 0;
            
            NSLog(@"[OpenCV] Input path: %s", input.c_str());
            
            while (cap.read(frame)) {
                frameCount++;
                outputFrame = frame.clone();
                
                // Detect targets and goal boundary in first few frames
                if (!targetsDetected && targetDetectionAttempts < MAX_DETECTION_ATTEMPTS) {
                    std::vector<Target> detectedTargets = detectTargets(frame, tapeRects);
                    
                    // Lock goal boundary if found. This is the highest priority.
                    if (!tapeRects.empty() && !goalBoundaryLocked) {
                        goalBoundary = tapeRects[0];
                        midX = goalBoundary.x + goalBoundary.width / 2;
                        midY = goalBoundary.y + goalBoundary.height / 2;
                        goalBoundaryLocked = true;
                        NSLog(@"[OpenCV] Goal boundary locked.");
                    }

                    // Populate targets list if not already done.
                    if (targets.empty() && !detectedTargets.empty()) {
                        targets = detectedTargets;
                        NSLog(@"[OpenCV] Targets found.");
                    }
                    
                    // If we have BOTH the boundary AND the targets, we can finalize scene setup.
                    if (goalBoundaryLocked && !targets.empty()) {
                        // Assign quadrants to targets using the now-correct `getQuadrant`
                        for (auto& target : targets) {
                            if (target.quadrant == 0) { // Assign only once
                                cv::Point center = target.isCircular ? target.center :
                                    cv::Point(target.boundingBox.x + target.boundingBox.width / 2,
                                              target.boundingBox.y + target.boundingBox.height / 2);
                                target.quadrant = getQuadrant(center);
                                NSLog(@"[OpenCV] Target %d assigned to quadrant %d", target.targetNumber, target.quadrant);
                            }
                        }
                        targetsDetected = true; // Stop further scene detection
                        NSLog(@"[OpenCV] Scene setup complete.");
                    }
                    targetDetectionAttempts++;
                }
                
                // Convert to grayscale for motion detection
                cv::Mat gray;
                cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
                cv::GaussianBlur(gray, gray, cv::Size(9, 9), 2);
                
                cv::Point currentBallPosition(-1, -1);
                std::string detectionMethod = "None";
                
                // Try multiple detection methods in order of preference
                // 1. Shape detection (most accurate)
                currentBallPosition = detectBallByShape(frame);
                if (currentBallPosition.x >= 0) {
                    detectionMethod = "Shape";
                }

                // 2. Motion detection (if shape fails)
                if (currentBallPosition.x < 0) {
                    cv::Point motionBall = detectBallByMotion(gray, pMOG2);
                    if (motionBall.x >= 0) {
                        currentBallPosition = motionBall;
                        detectionMethod = "Motion";
                    }
                }
                
                // 3. Color detection (last resort)
                if (currentBallPosition.x < 0) {
                    cv::Point colorBall = detectBallByColor(frame);
                    if (colorBall.x >= 0) {
                        currentBallPosition = colorBall;
                        detectionMethod = "Color";
                    }
                }
                
                // Update ball tracking
                if (currentBallPosition.x >= 0 && currentBallPosition.y >= 0) {
                    ballDetected = true;
                    framesWithoutBall = 0;
                    
                    // Update Kalman filter
                    cv::Mat measurement = (cv::Mat_<float>(2, 1) << currentBallPosition.x, currentBallPosition.y);
                    cv::Mat prediction = kalman.predict();
                    cv::Mat estimated = kalman.correct(measurement);
                    
                    // Add to trajectory with a distance check to prevent jumps
                    if (ballTrajectory.empty() || cv::norm(currentBallPosition - ballTrajectory.back()) < 80) {
                        ballTrajectory.push_back(currentBallPosition);
                    }
                    
                    // Keep only recent trajectory points (last 30 frames)
                    if (ballTrajectory.size() > 30) {
                        ballTrajectory.erase(ballTrajectory.begin());
                    }
                    
                    lastBallPosition = currentBallPosition;
                } else {
                    framesWithoutBall++;
                    if (framesWithoutBall > MAX_FRAMES_WITHOUT_BALL) {
                        ballDetected = false;
                        ballTrajectory.clear();
                    }
                }
                
                // Draw tape frame and targets
                if (goalBoundaryLocked) {
                    cv::rectangle(outputFrame, goalBoundary, cv::Scalar(0, 255, 0), 2);
                }
                for (const auto& target : targets) {
                    if (target.isCircular) {
                        // Draw circular target
                        cv::circle(outputFrame, target.center, target.radius, cv::Scalar(0, 255, 0), 2);
                        cv::putText(outputFrame, "TARGET " + std::to_string(target.targetNumber),
                                  cv::Point(target.center.x - 40, target.center.y - target.radius - 10),
                                  cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 0), 2);
                        
                        // Draw target center
                        cv::Point targetCenter = target.isCircular ? target.center : 
                            cv::Point(target.boundingBox.x + target.boundingBox.width/2,
                                    target.boundingBox.y + target.boundingBox.height/2);
                        cv::circle(outputFrame, targetCenter, 5, cv::Scalar(0, 255, 255), -1);
                    }
                }
                
                // Draw ball trajectory
                if (ballTrajectory.size() > 1) {
                    for (size_t i = 1; i < ballTrajectory.size(); i++) {
                        cv::line(outputFrame, ballTrajectory[i-1], ballTrajectory[i], 
                                cv::Scalar(255, 0, 0), 2);
                    }
                }
                
                // Draw ball and check hits
                if (currentBallPosition.x >= 0 && currentBallPosition.y >= 0) {
                    cv::circle(outputFrame, currentBallPosition, 8, cv::Scalar(0, 0, 255), -1);
                    cv::putText(outputFrame, "BALL (" + detectionMethod + ")",
                              cv::Point(currentBallPosition.x + 10, currentBallPosition.y - 10),
                              cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 255), 2);
                    
                    // Quadrant-based hit detection
                    int ballQuadrant = getQuadrant(currentBallPosition);
                    double minDistance = 1e9;
                    int bestTargetIndex = -1;

                    for (size_t i = 0; i < targets.size(); ++i) {
                        if (targets[i].quadrant != ballQuadrant) continue;

                        const auto& target = targets[i];
                        bool isHit = false;
                        double distance;

                        if (target.isCircular) {
                            distance = cv::norm(currentBallPosition - target.center);
                            isHit = distance <= target.radius;
                        } else {
                            isHit = target.boundingBox.contains(currentBallPosition);
                            cv::Point center(target.boundingBox.x + target.boundingBox.width / 2,
                                             target.boundingBox.y + target.boundingBox.height / 2);
                            distance = cv::norm(currentBallPosition - center);
                        }

                        if (isHit && distance < minDistance) {
                            minDistance = distance;
                            bestTargetIndex = i;
                        }
                    }
                    
                    // Only annotate best-matching target
                    if (bestTargetIndex >= 0) {
                        const auto& bestTarget = targets[bestTargetIndex];
                        cv::putText(outputFrame, "HIT TARGET " + std::to_string(bestTarget.targetNumber) + "!",
                            cv::Point(30, 30 + bestTarget.targetNumber * 40),
                            cv::FONT_HERSHEY_SIMPLEX, 1.0, cv::Scalar(0, 255, 255), 3);

                        if (ballTrajectory.size() > 5) {
                            std::string feedback = analyzeTrajectory(ballTrajectory, bestTarget, width, height);
                            cv::putText(outputFrame, "Target " + std::to_string(bestTarget.targetNumber) + 
                                          " Feedback: " + feedback,
                                cv::Point(30, 70 + bestTarget.targetNumber * 40),
                                cv::FONT_HERSHEY_SIMPLEX, 0.7, cv::Scalar(255, 255, 255), 2);
                        }
                    }
                }
                
                // Draw trajectory prediction if ball is detected
                if (ballDetected && ballTrajectory.size() > 3) {
                    cv::Point predictedPosition = predictNextPosition(ballTrajectory);
                    if (predictedPosition.x >= 0 && predictedPosition.y >= 0) {
                        cv::circle(outputFrame, predictedPosition, 6, cv::Scalar(255, 255, 0), 2);
                        cv::putText(outputFrame, "PREDICTED", cv::Point(predictedPosition.x + 10, predictedPosition.y - 10),
                                    cv::FONT_HERSHEY_SIMPLEX, 0.4, cv::Scalar(255, 255, 0), 1);
                    }
                }
                
                // Update status display
                cv::putText(outputFrame, "Targets Detected: " + std::to_string(targets.size()),
                           cv::Point(10, height - 100), cv::FONT_HERSHEY_SIMPLEX, 0.5,
                           cv::Scalar(255, 255, 255), 1);
                
                // Draw frame info
                cv::putText(outputFrame, "Frame: " + std::to_string(frameCount), 
                            cv::Point(10, height - 80), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                cv::putText(outputFrame, "Ball Detected: " + std::string(ballDetected ? "YES" : "NO"), 
                            cv::Point(10, height - 60), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                cv::putText(outputFrame, "Trajectory Points: " + std::to_string(ballTrajectory.size()), 
                            cv::Point(10, height - 40), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                cv::putText(outputFrame, "Detection: " + detectionMethod, 
                            cv::Point(10, height - 20), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                
                // Draw quadrant lines for debugging if goal is locked
                if (goalBoundaryLocked) {
                    cv::line(outputFrame, cv::Point(midX, goalBoundary.y), cv::Point(midX, goalBoundary.y + goalBoundary.height), cv::Scalar(255, 255, 255), 1);
                    cv::line(outputFrame, cv::Point(goalBoundary.x, midY), cv::Point(goalBoundary.x + goalBoundary.width, midY), cv::Scalar(255, 255, 255), 1);
                }
                
                prevGray = gray.clone();
                writer.write(outputFrame);
                
                // Log progress every 100 frames
                if (frameCount % 100 == 0) {
                    NSLog(@"[OpenCV] Processed %d frames", frameCount);
                }
            }
            
            cap.release();
            writer.release();
            NSLog(@"[OpenCV] Video processing completed. Total frames: %d", frameCount);
        }
    });
}

@end

// Helper function to detect all targets
static std::vector<Target> detectTargets(const cv::Mat& frame, std::vector<cv::Rect>& tapeRects) {
    std::vector<Target> targets;
    cv::Mat hsv;
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    
    // First detect Target 1 (yellow bullseye with rectangular frame)
    cv::Mat yellowMask;
    cv::inRange(hsv, cv::Scalar(20, 100, 100), cv::Scalar(35, 255, 255), yellowMask);
    
    std::vector<std::vector<cv::Point>> yellowContours;
    cv::findContours(yellowMask, yellowContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    // Find the largest yellow area
    double maxYellowArea = 0;
    cv::Rect bestYellowRect(-1, -1, -1, -1);
    
    for (const auto& contour : yellowContours) {
        double area = cv::contourArea(contour);
        if (area > 1000) {
            cv::Rect rect = cv::boundingRect(contour);
            double aspectRatio = static_cast<double>(rect.width) / rect.height;
            
            if (aspectRatio > 0.5 && aspectRatio < 2.0) {
                if (area > maxYellowArea) {
                    maxYellowArea = area;
                    bestYellowRect = rect;
                }
            }
        }
    }
    
    if (bestYellowRect.width > 0) {
        Target target1;
        target1.boundingBox = bestYellowRect;
        target1.isCircular = false;
        target1.targetNumber = 1;
        target1.center = cv::Point(bestYellowRect.x + bestYellowRect.width/2, 
                                 bestYellowRect.y + bestYellowRect.height/2);
        targets.push_back(target1);
    }
    
    // Then detect Target 2 (red bullseye circular target)
    Target circularTarget = detectCircularTarget(frame);
    if (circularTarget.boundingBox.width > 0) {
        // Check for overlap with Target 1
        bool hasOverlap = false;
        for (const auto& existingTarget : targets) {
            cv::Rect intersection = circularTarget.boundingBox & existingTarget.boundingBox;
            if (intersection.area() > 0) {
                hasOverlap = true;
                break;
            }
        }
        
        if (!hasOverlap) {
            circularTarget.targetNumber = 2;
            targets.push_back(circularTarget);
        }
    }
    
    // Detect fluorescent pink tape if not already found
    if (tapeRects.empty()) {
        cv::Mat pinkMask;
        cv::inRange(hsv, cv::Scalar(140, 100, 100), cv::Scalar(170, 255, 255), pinkMask);

        // Clean up mask to remove noise and connect tape segments
        cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(7, 7));
        cv::morphologyEx(pinkMask, pinkMask, cv::MORPH_CLOSE, kernel);
        cv::morphologyEx(pinkMask, pinkMask, cv::MORPH_OPEN, kernel);

        std::vector<std::vector<cv::Point>> pinkContours;
        cv::findContours(pinkMask, pinkContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        std::vector<cv::Point> allPinkPoints;
        for (const auto& contour : pinkContours) {
            double area = cv::contourArea(contour);
            if (area > 300) { // Filter out small noise
                allPinkPoints.insert(allPinkPoints.end(), contour.begin(), contour.end());
            }
        }
        
        if (allPinkPoints.size() > 1) {
            std::vector<cv::Point> hull;
            cv::convexHull(allPinkPoints, hull);
            double hullArea = cv::contourArea(hull);

            if (hullArea > 5000) { // Ensure the detected frame is large enough
                cv::Rect rect = cv::boundingRect(hull);
                tapeRects.push_back(rect);
            }
        }
    }

    return targets;
}

// Helper function to detect circular target
static Target detectCircularTarget(const cv::Mat& frame) {
    Target target;
    cv::Mat gray, hsv;
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    
    // Pre-process the image
    cv::GaussianBlur(gray, gray, cv::Size(9, 9), 2);
    
    // Detect circles using HoughCircles with more strict parameters
    std::vector<cv::Vec3f> circles;
    cv::HoughCircles(gray, circles, cv::HOUGH_GRADIENT, 1,
                     gray.rows/4,  // minimum distance between centers
                     150, 45,      // Canny edge detection parameters
                     40, 100       // min and max radius
    );
    
    if (!circles.empty()) {
        // Find circles with green outer ring and red center
        cv::Vec3f bestCircle;
        bool foundTarget = false;
        double maxResponse = 0;
        
        for (const auto& circle : circles) {
            cv::Point center(cvRound(circle[0]), cvRound(circle[1]));
            int radius = cvRound(circle[2]);
            
            // Check circle validity
            if (center.x >= 0 && center.x < frame.cols &&
                center.y >= 0 && center.y < frame.rows &&
                radius > 0) {
                
                // Check for red color in the center (bullseye)
                cv::Mat centerROI = hsv(cv::Rect(
                    std::max(0, center.x - radius/4),
                    std::max(0, center.y - radius/4),
                    std::min(radius/2, frame.cols - center.x),
                    std::min(radius/2, frame.rows - center.y)
                ));
                
                // Check for green color in the outer ring
                cv::Mat ringROI = hsv(cv::Rect(
                    std::max(0, center.x - radius),
                    std::max(0, center.y - radius),
                    std::min(radius*2, frame.cols - center.x),
                    std::min(radius*2, frame.rows - center.y)
                ));
                
                // Red color ranges in HSV
                cv::Mat redMask1, redMask2, redMask;
                cv::inRange(centerROI, cv::Scalar(0, 100, 100), cv::Scalar(10, 255, 255), redMask1);
                cv::inRange(centerROI, cv::Scalar(160, 100, 100), cv::Scalar(179, 255, 255), redMask2);
                cv::bitwise_or(redMask1, redMask2, redMask);
                
                // Green color range in HSV
                cv::Mat greenMask;
                cv::inRange(ringROI, cv::Scalar(35, 50, 50), cv::Scalar(85, 255, 255), greenMask);
                
                // Calculate percentage of red pixels in center area
                double redPercentage = (cv::countNonZero(redMask) * 100.0) / (centerROI.rows * centerROI.cols);
                
                // Calculate percentage of green pixels in outer ring area
                double greenPercentage = (cv::countNonZero(greenMask) * 100.0) / (ringROI.rows * ringROI.cols);
                
                // Check if both red center and green ring are present
                if (redPercentage > 20 && greenPercentage > 15) {  // Adjusted thresholds
                    // Calculate circle response (edge strength)
                    double response = 0;
                    int count = 0;
                    for (int angle = 0; angle < 360; angle += 10) {
                        int x = center.x + radius * cos(angle * CV_PI / 180);
                        int y = center.y + radius * sin(angle * CV_PI / 180);
                        if (x >= 0 && x < frame.cols && y >= 0 && y < frame.rows) {
                            response += gray.at<uchar>(y, x);
                            count++;
                        }
                    }
                    response /= count;
                    
                    // Weight the response by the color detection confidence
                    response *= (redPercentage + greenPercentage) / 200.0;
                    
                    if (response > maxResponse) {
                        maxResponse = response;
                        bestCircle = circle;
                        foundTarget = true;
                    }
                }
            }
        }
        
        if (foundTarget) {
            target.isCircular = true;
            target.center = cv::Point(cvRound(bestCircle[0]), cvRound(bestCircle[1]));
            target.radius = bestCircle[2];
            target.boundingBox = cv::Rect(target.center.x - target.radius,
                                         target.center.y - target.radius,
                                         2 * target.radius,
                                         2 * target.radius);
            target.circles.clear();
            target.circles.push_back(bestCircle);
        }
    }
    
    return target;
}

// Modified analyzeTrajectory function with enhanced, grid-based feedback
static std::string analyzeTrajectory(const std::vector<cv::Point>& trajectory,
                                    const Target& target, int frameWidth, int frameHeight) {
    if (trajectory.size() < 2) return "Not enough data.";

    // --- Trajectory Stats ---
    cv::Point end = trajectory.back();
    double totalDistance = 0;
    for (size_t i = 1; i < trajectory.size(); i++) {
        totalDistance += cv::norm(trajectory[i] - trajectory[i-1]);
    }
    double avgSpeed = trajectory.size() > 1 ? totalDistance / (trajectory.size() - 1) : 0;

    // --- 3x3 Grid Analysis ---
    cv::Rect targetBox = target.boundingBox;
    if (targetBox.width == 0 || targetBox.height == 0) return "Invalid target size.";

    float zoneWidth = targetBox.width / 3.0f;
    float zoneHeight = targetBox.height / 3.0f;

    // Determine ball's hit zone (0, 1, or 2 for row/col)
    int col = (end.x - targetBox.x) / zoneWidth;
    int row = (end.y - targetBox.y) / zoneHeight;
    col = std::max(0, std::min(2, col)); // Clamp to [0, 2]
    row = std::max(0, std::min(2, row)); // Clamp to [0, 2]

    // Target's center is always the middle zone (1, 1)
    const int targetRow = 1;
    const int targetCol = 1;

    // --- Semantic Feedback Generation ---
    const std::string rowLabels[] = {"Upper", "Center", "Lower"};
    const std::string colLabels[] = {"Left", "Center", "Right"};
    std::string zoneKey = rowLabels[row] + " " + colLabels[col];

    std::map<std::string, std::string> zoneMessages = {
        {"Upper Left",    "Great placement to top-left."},
        {"Upper Center",  "Top-center – predictable shot."},
        {"Upper Right",   "Sniper shot to top-right!"},
        {"Center Left",   "Keepers expect this – aim wider."},
        {"Center Center", "Middle shot – easy to stop."},
        {"Center Right",  "Good try – but aim more left."},
        {"Lower Left",    "Classic low-left corner shot."},
        {"Lower Center",  "Low center – try the corners."},
        {"Lower Right",   "Nice low-right target zone."}
    };
    
    // --- Positional Guidance ---
    std::string positionalFeedback;
    if (row == targetRow && col == targetCol) {
        positionalFeedback = "Perfect placement!";
    } else {
        // Vertical feedback (Y is inverted in image coordinates)
        if (row > targetRow) positionalFeedback += "Aim higher";
        else if (row < targetRow) positionalFeedback += "Aim lower";
        
        // Horizontal feedback
        if (col > targetCol) positionalFeedback += (positionalFeedback.empty() ? "" : " and ") + std::string("more to the left");
        else if (col < targetCol) positionalFeedback += (positionalFeedback.empty() ? "" : " and ") + std::string("more to the right");
    }

    // --- Power Feedback ---
    std::string powerFeedback;
    if (avgSpeed > 20)
        powerFeedback = " Good power!";
    else if (avgSpeed < 5)
        powerFeedback = " Add more power!";

    // --- Combine into Final Feedback ---
    std::string finalFeedback = positionalFeedback;
    if (row != targetRow || col != targetCol) {
        // Prepend the zone description if it's not a perfect shot
        finalFeedback = zoneMessages[zoneKey] + " " + positionalFeedback + ".";
    }
    finalFeedback += powerFeedback;

    return finalFeedback;
}

// Helper function to predict next ball position
static cv::Point predictNextPosition(const std::vector<cv::Point>& trajectory) {
    if (trajectory.size() < 3) return cv::Point(-1, -1);
    
    // Simple linear prediction using last 3 points
    cv::Point p1 = trajectory[trajectory.size() - 3];
    cv::Point p2 = trajectory[trajectory.size() - 2];
    cv::Point p3 = trajectory[trajectory.size() - 1];
    
    cv::Point velocity1 = p2 - p1;
    cv::Point velocity2 = p3 - p2;
    
    // Average velocity
    cv::Point avgVelocity((velocity1.x + velocity2.x) / 2, (velocity1.y + velocity2.y) / 2);
    
    // Predict next position
    cv::Point predicted = p3 + avgVelocity;
    
    return predicted;
}

// Helper function for ball detection using shape (HoughCircles)
static cv::Point detectBallByShape(const cv::Mat& frame) {
    cv::Mat gray;
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
    cv::GaussianBlur(gray, gray, cv::Size(7, 7), 2);

    std::vector<cv::Vec3f> circles;
    cv::HoughCircles(gray, circles, cv::HOUGH_GRADIENT, 1, gray.rows/8, 100, 30, 5, 50);

    if (!circles.empty()) {
        for (auto& circle : circles) {
            cv::Point center(cvRound(circle[0]), cvRound(circle[1]));
            int radius = cvRound(circle[2]);

            // Filter by expected radius range
            if (radius >= 5 && radius <= 50) {
                return center; // Return the first valid circle center
            }
        }
    }
    return cv::Point(-1, -1);
}

// Helper function to detect ball by color
static cv::Point detectBallByColor(const cv::Mat& frame) {
    cv::Mat hsv;
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    
    // Try multiple color ranges for different ball types
    std::vector<cv::Scalar> colorRanges = {
        // White ball
        cv::Scalar(0, 0, 200), cv::Scalar(180, 30, 255),
        // Yellow ball
        cv::Scalar(20, 100, 100), cv::Scalar(30, 255, 255),
        // Orange ball
        cv::Scalar(10, 100, 100), cv::Scalar(20, 255, 255),
        // Red ball (low range)
        cv::Scalar(0, 100, 100), cv::Scalar(10, 255, 255),
        // Red ball (high range)
        cv::Scalar(160, 100, 100), cv::Scalar(179, 255, 255)
    };
    
    cv::Point bestCenter(-1, -1);
    double maxArea = 0;
    
    for (size_t i = 0; i < colorRanges.size(); i += 2) {
        cv::Mat mask;
        cv::inRange(hsv, colorRanges[i], colorRanges[i + 1], mask);
        
        // Morphological operations
        cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
        cv::morphologyEx(mask, mask, cv::MORPH_OPEN, kernel);
        cv::morphologyEx(mask, mask, cv::MORPH_CLOSE, kernel);
        
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
        
        for (const auto& contour : contours) {
            double area = cv::contourArea(contour);
            if (area > 200 && area < 10000) { // Filter by size
                cv::Rect rect = cv::boundingRect(contour);
                cv::Point center(rect.x + rect.width / 2, rect.y + rect.height / 2);
                
                // Check if this is a reasonable ball position
                if (center.x > 0 && center.x < frame.cols && center.y > 0 && center.y < frame.rows) {
                    if (area > maxArea) {
                        maxArea = area;
                        bestCenter = center;
                    }
                }
            }
        }
    }
    
    return bestCenter;
}

// Helper function to detect ball by motion (now using Background Subtraction)
static cv::Point detectBallByMotion(const cv::Mat& gray, cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2) {
    cv::Mat fgMask;
    pMOG2->apply(gray, fgMask);

    // Morphological operations to reduce noise
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
    cv::morphologyEx(fgMask, fgMask, cv::MORPH_OPEN, kernel);
    cv::morphologyEx(fgMask, fgMask, cv::MORPH_CLOSE, kernel);
    
    // Find contours
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(fgMask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    // Find the largest motion contour (likely the ball)
    double maxArea = 0;
    cv::Point bestCenter(-1, -1);
    
    for (const auto& contour : contours) {
        double area = cv::contourArea(contour);
        if (area > 150 && area < 5000) { // Filter by size
            cv::Rect rect = cv::boundingRect(contour);
            cv::Point center(rect.x + rect.width / 2, rect.y + rect.height / 2);
            
            // Check if this is a reasonable ball position
            if (center.x > 0 && center.x < gray.cols && center.y > 0 && center.y < gray.rows) {
                if (area > maxArea) {
                    maxArea = area;
                    bestCenter = center;
                }
            }
        }
    }
    
    return bestCenter;
}

