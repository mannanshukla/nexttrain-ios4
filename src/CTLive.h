#import <Foundation/Foundation.h>
// Real-time via 511.org StopMonitoring (needs a free token; 60 requests per hour). Synchronous; call off the main thread.
// Returns {trainNumber: {expected (minutes since midnight), aimed}} or nil with error.
@interface CTLive : NSObject
+ (NSDictionary *)predictionsForStopCode:(NSString *)code error:(NSString **)err;
+ (NSString *)alertsWithError:(NSString **)err;   // joined alert headlines for Caltrain, or nil
+ (NSString *)cachedAlerts; + (NSTimeInterval)alertsAge;   // last fetched text and how old it is
@end
