#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;

// Existing video analysis method
+ (void)analyzeVideo:(NSString *)inputPath outputPath:(NSString *)outputPath;

// Real-time processing methods
+ (NSDictionary *)detectTargetsInFrame:(UIImage *)frame goalRegion:(CGRect)goalRegion;
+ (NSDictionary * _Nullable)detectBallInFrame:(UIImage *)frame;
+ (NSDictionary * _Nullable)detectSoccerBall:(UIImage *)frame; // Simple soccer ball detection
+ (BOOL)detectImpactWithBall:(NSDictionary *)ball targets:(NSArray<NSDictionary *> *)targets goalRegion:(CGRect)goalRegion;
+ (void)resetTracking;

// Enhanced backend processing methods
+ (NSDictionary *)analyzeFramePerformance:(UIImage *)frame;
+ (NSArray<NSDictionary *> *)detectMotionInFrame:(UIImage *)frame;
+ (NSDictionary *)getTrackingStatistics;
+ (void)setProcessingMode:(NSString *)mode; // "fast", "accurate", "balanced"
+ (void)calibrateForLighting:(UIImage *)frame;
+ (NSDictionary * _Nullable)detectBallByFFT:(UIImage *)frame;

@end

NS_ASSUME_NONNULL_END

