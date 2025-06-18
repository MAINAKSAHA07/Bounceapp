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
            
            // Try 'MJPG' codec for .avi compatibility
            cv::VideoWriter writer(output, cv::VideoWriter::fourcc('M','J','P','G'), fps, cv::Size(width, height));
            if (!writer.isOpened()) {
                NSLog(@"Error: Could not create output video writer. Path: %s, Size: %dx%d, FPS: %f", output.c_str(), width, height, fps);
                return;
            }
            NSLog(@"[OpenCV] Output writer created. Path: %s, Size: %dx%d, FPS: %f", output.c_str(), width, height, fps);
            
            cv::Mat frame, hsv, mask, outputFrame;
            cv::Scalar lower_pink(140, 100, 100); // HSV: H=150±10, S=100-255, V=100-255
            cv::Scalar upper_pink(160, 255, 255);
            
            cv::Mat prevGray;
            std::string persistentZoneLabel = "";
            std::string persistentFeedback = "";

            NSLog(@"[OpenCV] Input path: %s", input.c_str());
            
            while (cap.read(frame)) {
                outputFrame = frame.clone();
                cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
                cv::inRange(hsv, lower_pink, upper_pink, mask);
                
                std::vector<std::vector<cv::Point>> contours;
                cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
                
                std::vector<cv::Point> allPoints;
                int frameWidth = frame.cols;
                for (const auto& contour : contours) {
                    double area = cv::contourArea(contour);
                    if (area < 200) continue;
                    cv::Rect rect = cv::boundingRect(contour);
                    // Only consider if contour touches both left and right edges first
                    if (rect.x <= 2 && rect.x + rect.width >= frameWidth - 3) {
                        allPoints.insert(allPoints.end(), contour.begin(), contour.end());
                    }
                }
                
                // Draw rectangle only if a valid pink contour spans the frame
                if (!allPoints.empty()) {
                    cv::Rect fullTarget = cv::boundingRect(allPoints);
                    cv::rectangle(outputFrame, fullTarget, cv::Scalar(0, 255, 0), 2);
                }
                
                cv::Mat gray, diff;
                cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
                
                if (!prevGray.empty()) {
                    cv::absdiff(gray, prevGray, diff);
                    cv::threshold(diff, diff, 25, 255, cv::THRESH_BINARY);
                    std::vector<std::vector<cv::Point>> motionContours;
                    cv::findContours(diff, motionContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
                    
                    // ------------------- RED BULLSEYE CIRCLE DETECTION --------------------
                    cv::Mat redMask1, redMask2, redMask;
                    cv::inRange(hsv, cv::Scalar(0, 100, 100), cv::Scalar(10, 255, 255), redMask1);     // low red
                    cv::inRange(hsv, cv::Scalar(160, 100, 100), cv::Scalar(179, 255, 255), redMask2);   // high red
                    cv::bitwise_or(redMask1, redMask2, redMask);
                    
                    // Use redMask to focus HoughCircles detection
                    cv::Mat redMaskGray;
                    cv::GaussianBlur(redMask, redMaskGray, cv::Size(9, 9), 2, 2); // blur improves detection
                    
                    std::vector<cv::Vec3f> circles;
                    cv::HoughCircles(redMaskGray, circles, cv::HOUGH_GRADIENT, 1,
                                     redMask.rows / 8,   // min dist between circles
                                     100, 20,            // param1 (edge), param2 (center strength)
                                     10, 60);            // min and max radius of circle (tweak if needed)
                    
                    cv::Point targetCenter(-1, -1);
                    
                    if (!circles.empty()) {
                        cv::Vec3f best = circles[0]; // pick first/best detected circle
                        targetCenter = cv::Point(cvRound(best[0]), cvRound(best[1]));
                        int radius = cvRound(best[2]);
                        
                        // Draw detected bullseye circle outline
                        cv::circle(outputFrame, targetCenter, radius, cv::Scalar(0, 255, 255), 2);
                        
                        // Draw "X" and label
                        cv::drawMarker(outputFrame, targetCenter, cv::Scalar(0, 255, 255),
                                       cv::MARKER_TILTED_CROSS, 20, 2);
                        cv::putText(outputFrame, "TARGET", targetCenter + cv::Point(10, -10),
                                    cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 255), 2);
                    }
                    
                    for (const auto& mc : motionContours) {
                        if (cv::contourArea(mc) < 500) continue;
                        cv::Rect motionRect = cv::boundingRect(mc);
                        cv::Point center(motionRect.x + motionRect.width / 2, motionRect.y + motionRect.height / 2);
                        // Draw line and compute distance to target
                        if (targetCenter.x > 0 && targetCenter.y > 0) {
                            // 1. Draw line
                            cv::line(outputFrame, targetCenter, center, cv::Scalar(255, 255, 0), 2);
                            
                            // 2. Compute distance
                            double distance = cv::norm(targetCenter - center);
                            
                            // 3. Show distance on screen
                            cv::putText(outputFrame, "Distance: " + std::to_string((int)distance) + " px",
                                        targetCenter + cv::Point(20, 40),
                                        cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(255, 255, 0), 2);
                        }
                        
                        cv::circle(outputFrame, center, 6, cv::Scalar(0, 0, 255), -1);
                        cv::putText(outputFrame, "Impact Detected", cv::Point(30, 30), cv::FONT_HERSHEY_SIMPLEX, 0.8, cv::Scalar(255, 255, 255), 2);
                        
                        if (!allPoints.empty()) {
                            cv::Rect fullTarget = cv::boundingRect(allPoints);
                            
                            if (fullTarget.contains(center)) {
                                int colWidth = fullTarget.width / 3;
                                int rowHeight = fullTarget.height / 3;
                                
                                int col = std::clamp((center.x - fullTarget.x) / colWidth, 0, 2);
                                int row = std::clamp((center.y - fullTarget.y) / rowHeight, 0, 2);
                                
                                const char* zoneNames[3][3] = {
                                    {"Upper Left",    "Upper Center",    "Upper Right"},
                                    {"Center Left",   "Center",          "Center Right"},
                                    {"Lower Left",    "Lower Center",    "Lower Right"}
                                };
                                
                                std::string zoneLabel = zoneNames[row][col];
                                
                                cv::putText(outputFrame, "Zone: " + zoneLabel,
                                            cv::Point(center.x + 10, center.y - 10),
                                            cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 255), 2);
                                
                                // Classify target zone using same logic
                                int targetCol = std::clamp((targetCenter.x - fullTarget.x) / colWidth, 0, 2);
                                int targetRow = std::clamp((targetCenter.y - fullTarget.y) / rowHeight, 0, 2);

                                std::string feedback;
                                
                                persistentZoneLabel = "Zone: " + zoneLabel;

                                // Compare rows for vertical suggestion
                                if (row > targetRow) feedback += "Try to kick higher";
                                else if (row < targetRow) feedback += "Try to kick lower";

                                // Compare cols for horizontal suggestion
                                if (col > targetCol) feedback += (feedback.empty() ? "" : " and ") + std::string("left");
                                else if (col < targetCol) feedback += (feedback.empty() ? "" : " and ") + std::string("right");

                                if (row == targetRow && col == targetCol)
                                    feedback = "Nice shot! Right on target!";
                                
                                persistentFeedback = feedback;
                            }
                        }
                    }
                }
                
                prevGray = gray;
                if (!persistentZoneLabel.empty()) {
                    cv::putText(outputFrame, persistentZoneLabel,
                                cv::Point(30, 90),
                                cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 255), 2);
                }

                if (!persistentFeedback.empty()) {
                    cv::putText(outputFrame, "Feedback: " + persistentFeedback,
                                cv::Point(30, 60),
                                cv::FONT_HERSHEY_SIMPLEX, 0.7, cv::Scalar(255, 255, 255), 2);
                }
                writer.write(outputFrame);
            }
        }
    });
}

@end

