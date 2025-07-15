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
+ (BOOL)detectImpactWithBall:(NSDictionary *)ball targets:(NSArray<NSDictionary *> *)targets goalRegion:(CGRect)goalRegion;
+ (void)resetTracking;

// Enhanced backend processing methods
+ (NSDictionary *)analyzeFramePerformance:(UIImage *)frame;
+ (NSArray<NSDictionary *> *)detectMotionInFrame:(UIImage *)frame;
+ (NSDictionary *)getTrackingStatistics;
+ (void)setProcessingMode:(NSString *)mode; // "fast", "accurate", "balanced"
+ (void)calibrateForLighting:(UIImage *)frame;

@end

NS_ASSUME_NONNULL_END

