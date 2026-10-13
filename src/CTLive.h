#import <Foundation/Foundation.h>
// Real-time via 511.org StopMonitoring (needs a free token; 60 requests per hour). Synchronous; call off the main thread.
// Returns {trainNumber: {expected (minutes since midnight), aimed}} or nil with error.
@interface CTLive : NSObject
+ (NSDictionary *)predictionsForStopCode:(NSString *)code error:(NSString **)err;
+ (NSString *)alertsWithError:(NSString **)err;   // joined alert headlines for Caltrain, or nil
+ (NSString *)cachedAlerts; + (NSTimeInterval)alertsAge;   // last fetched text and how old it is
@end
@interface CTAI : NSObject
// "sf to palo alto after 6" -> {from (NSNumber station idx), to, when (minutes or -1), arriveBy (bool)}
+ (NSDictionary *)parseAsk:(NSString *)text error:(NSString **)err;
// Laya: should you run for a train leaving in `mins` when the platform is `walk` minutes away? {p (0..1), confidence}
+ (NSDictionary *)runForTrainIn:(NSInteger)mins walk:(NSInteger)walk next:(NSInteger)next error:(NSString **)err;
@end
