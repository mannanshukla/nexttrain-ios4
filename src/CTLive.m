#import "CTLive.h"
#import "CTData.h"
#import "ORJSON.h"
#import <zlib.h>

static NSData *gunzip(NSData *d) {   // 511 sends gzip; the URL loader usually inflates it, this covers the case where it does not
    const unsigned char *b = [d bytes]; if ([d length] < 2 || b[0] != 0x1f || b[1] != 0x8b) return d;
    z_stream z; memset(&z, 0, sizeof(z)); z.next_in = (Bytef *)b; z.avail_in = (uInt)[d length];
    if (inflateInit2(&z, 16 + MAX_WBITS) != Z_OK) return d;
    NSMutableData *out = [NSMutableData dataWithLength:[d length] * 8 + 1024]; int r;
    do { if (z.total_out >= [out length]) [out increaseLengthBy:[out length]]; z.next_out = (Bytef *)[out mutableBytes] + z.total_out; z.avail_out = (uInt)([out length] - z.total_out); r = inflate(&z, Z_SYNC_FLUSH); } while (r == Z_OK);
    inflateEnd(&z); if (r != Z_STREAM_END) return d; [out setLength:z.total_out]; return out;
}

static NSData *fetch(NSString *url, NSString **err, NSInteger *status) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    NSHTTPURLResponse *resp = nil; NSError *e = nil;
    NSData *d = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&e];
    if (status) *status = [resp statusCode];
    if (!d && err) *err = [e localizedDescription];
    return d;
}
static NSString *text(NSData *d) {   // 511 responses may be gzipped and may start with a BOM
    NSString *s = [[[NSString alloc] initWithData:gunzip(d) encoding:NSUTF8StringEncoding] autorelease];
    if ([s length] && [s characterAtIndex:0] == 0xFEFF) s = [s substringFromIndex:1];
    return s;
}
static NSInteger isoToLocalMinutes(NSString *iso) {
    if (![iso isKindOfClass:[NSString class]] || [iso length] < 19) return -1;
    static NSDateFormatter *f = nil;
    if (!f) { f = [[NSDateFormatter alloc] init]; [f setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"]; [f setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]]; }
    NSDate *d = [f dateFromString:[iso substringToIndex:19]]; if (!d) return -1;
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit | NSDayCalendarUnit fromDate:d];
    NSInteger today = [[[NSCalendar currentCalendar] components:NSDayCalendarUnit fromDate:[NSDate date]] day];
    NSInteger m = [c hour] * 60 + [c minute]; if ([c day] != today) m += 1440;   // after midnight
    return m;
}

static NSString *gAlerts = nil; static NSTimeInterval gAlertsAt = 0;

@implementation CTLive
+ (NSString *)cachedAlerts { return gAlerts; }
+ (NSTimeInterval)alertsAge { return gAlertsAt ? [[NSDate date] timeIntervalSince1970] - gAlertsAt : 1e9; }
+ (NSDictionary *)predictionsForStopCode:(NSString *)code error:(NSString **)err {
    if (![[CTData token] length]) { if (err) *err = @"No 511 token."; return nil; }
    NSInteger status = 0;
    NSData *d = fetch([NSString stringWithFormat:@"http://api.511.org/transit/StopMonitoring?api_key=%@&agency=CT&stopCode=%@&format=json", [CTData token], code], err, &status);
    if (!d) return nil;
    if (status == 401) { if (err) *err = @"511 rejected the token."; return nil; }
    if (status == 429) { if (err) *err = @"511 rate limit hit (60 per hour). Try again in a bit."; return nil; }
    if (status != 200) { if (err) *err = [NSString stringWithFormat:@"511 returned HTTP %ld", (long)status]; return nil; }
    id obj = [ORJSON parse:text(d)];
    id visits = [[[[obj objectForKey:@"ServiceDelivery"] objectForKey:@"StopMonitoringDelivery"] objectForKey:@"MonitoredStopVisit"] isKindOfClass:[NSArray class]] ? [[[obj objectForKey:@"ServiceDelivery"] objectForKey:@"StopMonitoringDelivery"] objectForKey:@"MonitoredStopVisit"] : nil;
    if (!visits) { if (err) *err = @"Could not read the 511 reply."; return nil; }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSDictionary *v in visits) {
        NSDictionary *j = [v objectForKey:@"MonitoredVehicleJourney"]; NSDictionary *call = [j objectForKey:@"MonitoredCall"];
        NSString *train = [[j objectForKey:@"VehicleRef"] description]; if (![train length]) continue;
        NSInteger exp = isoToLocalMinutes([call objectForKey:@"ExpectedDepartureTime"] ?: [call objectForKey:@"ExpectedArrivalTime"]);
        NSInteger aim = isoToLocalMinutes([call objectForKey:@"AimedDepartureTime"] ?: [call objectForKey:@"AimedArrivalTime"]);
        if (exp < 0) continue;
        [out setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:exp], @"expected", [NSNumber numberWithInteger:aim], @"aimed", nil] forKey:train];
    }
    return out;
}
+ (NSString *)alertsWithError:(NSString **)err {
    if (![[CTData token] length]) { if (err) *err = @"No 511 token."; return nil; }
    NSInteger status = 0;
    NSData *d = fetch([NSString stringWithFormat:@"http://api.511.org/transit/servicealerts?api_key=%@&agency=CT&format=json", [CTData token]], err, &status);
    if (!d || status != 200) { if (err && status) *err = [NSString stringWithFormat:@"511 returned HTTP %ld", (long)status]; return nil; }
    NSString *txt = text(d); id obj = [ORJSON parse:txt];
    NSArray *ents = [[obj objectForKey:@"Entities"] isKindOfClass:[NSArray class]] ? [obj objectForKey:@"Entities"] : nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *e in ents) {
        NSDictionary *a = [e objectForKey:@"Alert"]; NSArray *tr = [[[a objectForKey:@"HeaderText"] objectForKey:@"Translations"] isKindOfClass:[NSArray class]] ? [[a objectForKey:@"HeaderText"] objectForKey:@"Translations"] : nil;
        for (NSDictionary *t in tr) if ([[t objectForKey:@"Language"] isEqualToString:@"en"] && [[t objectForKey:@"Text"] length]) { [lines addObject:[t objectForKey:@"Text"]]; break; }
    }
    NSString *out = [lines count] ? [lines componentsJoinedByString:@"\n"] : @"";
    [gAlerts release]; gAlerts = [out copy]; gAlertsAt = [[NSDate date] timeIntervalSince1970];
    return out;
}
@end
