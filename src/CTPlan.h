#import <Foundation/Foundation.h>
// Trip planning across Caltrain and BART. The model only chooses the route (which stations, which systems, when);
// every time comes from the bundled Caltrain timetable or api.bart.gov, never from the model.
//
// A segment is one ride: {mode ("caltrain" | "bart"), from, to (display names), depAt, arrAt (NSNumber, seconds since 1970), label ("Express 412", "BART to Richmond"),
//   caltrain only: trip, fromIdx, toIdx, train, fromCode, toCode (511 stop codes) · bart only: fromAbbr, toAbbr, head}
// An itinerary is {depAt, arrAt, segs:[segment]}.
@interface CTAI : NSObject
// "stanford to the mission tomorrow by 9" -> {legs:[{mode, from, to (NSNumber station index in that system), fromName, toName, gap (NSNumber minutes, optional)}],
//   day (NSNumber, days from today), when (minutes since midnight or -1), arriveBy, express (NSNumber bool), note}
+ (NSDictionary *)planTrip:(NSString *)text error:(NSString **)err;
+ (NSDictionary *)planFromReply:(NSString *)reply error:(NSString **)err;   // the parsing half of planTrip, for testing without the network
@end
@interface CTRoute : NSObject
+ (NSArray *)itinerariesFor:(NSDictionary *)plan error:(NSString **)err;   // up to 4; synchronous, may hit the network, call off the main thread
+ (NSDictionary *)caltrainTrip:(NSDictionary *)trip from:(NSInteger)fi to:(NSInteger)ti base:(NSTimeInterval)midnight;   // one segment from a timetable trip
+ (NSDictionary *)bartLeg:(NSDictionary *)leg;                                           // one segment from a CTBart trip leg
+ (NSArray *)ringsFor:(NSArray *)segs leave:(BOOL)leave;   // timer rings: one before the end of every segment, plus one to leave for the first if asked
+ (NSDictionary *)leaveRingFor:(NSDictionary *)seg;        // nil when it is already time to go
+ (NSString *)summary:(NSDictionary *)itinerary;           // "Express 412 to Millbrae, then BART to Richmond"
@end
