#import <UIKit/UIKit.h>
// Bundled Caltrain timetable (res/caltrain.json, compacted GTFS) plus prefs.
@interface CTData : NSObject
+ (NSDictionary *)feed;
+ (NSArray *)stations;                 // north to south: {id, name, lat, lon, codes:{N,S}, zone}
+ (NSInteger)stationNamed:(NSString *)query;   // fuzzy, -1 if none
+ (NSString *)feedVersion; + (NSString *)feedEnd;
+ (NSString *)dateKey:(NSDate *)d;     // yyyyMMdd
+ (NSInteger)minutesNow;               // minutes since local midnight
+ (NSString *)fmtMin:(NSInteger)m;     // "5:32 PM", wraps past midnight
+ (NSSet *)activeServicesOn:(NSDate *)date;
// Departures from station s heading dir (0 north, 1 south) on date at/after minute m. Items: {trip, dep (NSNumber), idx (NSNumber)}
+ (NSArray *)departuresFrom:(NSInteger)s dir:(NSInteger)dir date:(NSDate *)date after:(NSInteger)m;
// Trips serving a then b on date. leaveAfter >= 0 filters by departure, arriveBy >= 0 by arrival (latest first). Items: {trip, dep, arr, fromIdx, toIdx}
+ (NSArray *)tripsFrom:(NSInteger)a to:(NSInteger)b date:(NSDate *)date leaveAfter:(NSInteger)leave arriveBy:(NSInteger)by;
+ (double)fareFrom:(NSInteger)a to:(NSInteger)b;   // 0 if unknown
+ (UIColor *)colorForType:(NSString *)type;
+ (UIImage *)badgeForType:(NSString *)type;
+ (UIImage *)badgeText:(NSString *)txt color:(UIColor *)color;
+ (NSString *)apiKey; + (void)setApiKey:(NSString *)k;         // OpenRelay
+ (NSString *)token; + (void)setToken:(NSString *)t;           // 511.org
+ (NSInteger)homeStation; + (void)setHomeStation:(NSInteger)s;
+ (NSInteger)homeDir; + (void)setHomeDir:(NSInteger)d;
+ (NSInteger)walkMinutes; + (void)setWalkMinutes:(NSInteger)m;   // how far you usually are from the platform
@end
