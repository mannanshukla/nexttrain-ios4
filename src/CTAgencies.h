#import <UIKit/UIKit.h>
// BART (keyless legacy API over https) and Muni (511 StopMonitoring). Synchronous fetchers; call off the main thread.
@interface CTBart : NSObject
+ (NSArray *)stations;                                   // bundled: {abbr, name, city}
+ (NSInteger)stationIndexForAbbr:(NSString *)abbr;
+ (NSArray *)departuresAt:(NSString *)abbr error:(NSString **)err;   // [{dest, abbr, minutes (NSNumber, 0 = leaving), platform, direction, length, hex, delay}] sorted by minutes
+ (NSString *)advisoriesWithError:(NSString **)err;      // joined text or "" when none
+ (NSArray *)tripsFrom:(NSString *)a to:(NSString *)b time:(NSString *)t error:(NSString **)err;   // [{dep, arr, mins, fare, depAt, arrAt, legs:[{line, head, from, to, dep, arr, depAt, arrAt}]}]; depAt/arrAt are seconds since 1970
// Same, for a given moment: departing at or after t, or (arriveBy) arriving by t. Sorted by departure.
+ (NSArray *)tripsFrom:(NSString *)a to:(NSString *)b at:(NSTimeInterval)t arriveBy:(BOOL)by error:(NSString **)err;
+ (NSInteger)stationNamed:(NSString *)q;                 // fuzzy over names and abbreviations, -1 if none
+ (NSString *)nameForAbbr:(NSString *)abbr;
+ (UIImage *)squareForHex:(NSString *)hex;
+ (NSString *)homeStation; + (void)setHomeStation:(NSString *)a;
@end
@interface CTMuni : NSObject
+ (NSString *)nameForStop:(NSString *)code;              // bundled list, nil if unknown
+ (NSArray *)savedStops; + (void)setSavedStops:(NSArray *)codes;
+ (NSArray *)predictionsForStop:(NSString *)code error:(NSString **)err;   // [{route, dest, minutes (NSNumber)}] sorted by minutes
@end
