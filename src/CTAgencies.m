#import "CTAgencies.h"
#import "CTData.h"
#import "ORJSON.h"
#import <zlib.h>

#define BART_KEY @"MW9S-E7SL-26DU-VV8V"
static NSArray *gBart = nil; static NSDictionary *gMuni = nil; static NSMutableDictionary *gSquares = nil;

static NSData *inflateIfGzip(NSData *d) {
    const unsigned char *b = [d bytes]; if ([d length] < 2 || b[0] != 0x1f || b[1] != 0x8b) return d;
    z_stream z; memset(&z, 0, sizeof(z)); z.next_in = (Bytef *)b; z.avail_in = (uInt)[d length];
    if (inflateInit2(&z, 16 + MAX_WBITS) != Z_OK) return d;
    NSMutableData *out = [NSMutableData dataWithLength:[d length] * 8 + 1024]; int r;
    do { if (z.total_out >= [out length]) [out increaseLengthBy:[out length]]; z.next_out = (Bytef *)[out mutableBytes] + z.total_out; z.avail_out = (uInt)([out length] - z.total_out); r = inflate(&z, Z_SYNC_FLUSH); } while (r == Z_OK);
    inflateEnd(&z); if (r != Z_STREAM_END) return d; [out setLength:z.total_out]; return out;
}
static id getJSON(NSString *url, NSString **err) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    NSHTTPURLResponse *resp = nil; NSError *e = nil;
    NSData *d = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&e];
    if (!d) { if (err) *err = [e localizedDescription]; return nil; }
    if ([resp statusCode] == 401) { if (err) *err = @"511 rejected the token."; return nil; }
    if ([resp statusCode] == 429) { if (err) *err = @"511 rate limit hit (60 per hour). Try again in a bit."; return nil; }
    if ([resp statusCode] != 200) { if (err) *err = [NSString stringWithFormat:@"HTTP %ld", (long)[resp statusCode]]; return nil; }
    NSString *s = [[[NSString alloc] initWithData:inflateIfGzip(d) encoding:NSUTF8StringEncoding] autorelease];
    if ([s length] && [s characterAtIndex:0] == 0xFEFF) s = [s substringFromIndex:1];
    id obj = [ORJSON parse:s];
    if (!obj && err) *err = @"Could not read the reply.";
    return obj;
}
static NSString *cdata(id v) { if ([v isKindOfClass:[NSDictionary class]]) v = [v objectForKey:@"#cdata-section"]; return [v isKindOfClass:[NSString class]] ? [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @""; }
static NSArray *asArray(id v) { return [v isKindOfClass:[NSArray class]] ? v : v ? [NSArray arrayWithObject:v] : [NSArray array]; }

@implementation CTBart
+ (NSArray *)stations { if (!gBart) { NSString *p = [[NSBundle mainBundle] pathForResource:@"bart" ofType:@"json"]; gBart = [([ORJSON parse:[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]] ?: [NSArray array]) retain]; } return gBart; }
+ (NSInteger)stationIndexForAbbr:(NSString *)abbr { NSArray *s = [self stations]; for (NSUInteger i = 0; i < [s count]; i++) if ([[[s objectAtIndex:i] objectForKey:@"abbr"] isEqualToString:abbr]) return i; return 0; }
+ (NSString *)homeStation { return [[NSUserDefaults standardUserDefaults] stringForKey:@"ct_bart_home"] ?: @"POWL"; }
+ (void)setHomeStation:(NSString *)a { [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"ct_bart_home"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
+ (NSArray *)departuresAt:(NSString *)abbr error:(NSString **)err {
    id obj = getJSON([NSString stringWithFormat:@"https://api.bart.gov/api/etd.aspx?cmd=etd&orig=%@&key=%@&json=y", abbr, BART_KEY], err);
    if (!obj) return nil;
    NSArray *st = asArray([[obj objectForKey:@"root"] objectForKey:@"station"]); if (![st count]) { if (err) *err = @"BART sent no estimates."; return nil; }
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *e in asArray([[st objectAtIndex:0] objectForKey:@"etd"])) for (NSDictionary *x in asArray([e objectForKey:@"estimate"])) {
        NSString *m = [[x objectForKey:@"minutes"] description]; NSInteger mins = [m isEqualToString:@"Leaving"] ? 0 : [m integerValue];
        [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:[e objectForKey:@"destination"] ?: @"", @"dest", [e objectForKey:@"abbreviation"] ?: @"", @"abbr", [NSNumber numberWithInteger:mins], @"minutes",
            [x objectForKey:@"platform"] ?: @"", @"platform", [x objectForKey:@"direction"] ?: @"", @"direction", [x objectForKey:@"length"] ?: @"", @"length", [x objectForKey:@"hexcolor"] ?: @"#999999", @"hex", [NSNumber numberWithInteger:[[x objectForKey:@"delay"] integerValue]], @"delay", nil]];
    }
    [out sortUsingComparator:^NSComparisonResult(id p, id q) { NSInteger a = [[p objectForKey:@"minutes"] integerValue], b = [[q objectForKey:@"minutes"] integerValue]; return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame; }];
    return out;
}
+ (NSString *)advisoriesWithError:(NSString **)err {
    id obj = getJSON([NSString stringWithFormat:@"https://api.bart.gov/api/bsa.aspx?cmd=bsa&key=%@&json=y", BART_KEY], err);
    if (!obj) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *b in asArray([[obj objectForKey:@"root"] objectForKey:@"bsa"])) { NSString *t = cdata([b objectForKey:@"description"]); if ([t length] && [t rangeOfString:@"No delays reported"].location == NSNotFound) [lines addObject:t]; }
    return [lines componentsJoinedByString:@"\n\n"];
}
+ (NSArray *)tripsFrom:(NSString *)a to:(NSString *)b time:(NSString *)t error:(NSString **)err {
    NSString *tm = t ? [NSString stringWithFormat:@"&time=%@", [t stringByReplacingOccurrencesOfString:@" " withString:@""]] : @"";
    id obj = getJSON([NSString stringWithFormat:@"https://api.bart.gov/api/sched.aspx?cmd=depart&orig=%@&dest=%@%@&b=0&a=4&key=%@&json=y", a, b, tm, BART_KEY], err);
    if (!obj) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *tr in asArray([[[[obj objectForKey:@"root"] objectForKey:@"schedule"] objectForKey:@"request"] objectForKey:@"trip"])) {
        NSMutableArray *legs = [NSMutableArray array];
        for (NSDictionary *l in asArray([tr objectForKey:@"leg"])) [legs addObject:[NSDictionary dictionaryWithObjectsAndKeys:[l objectForKey:@"@line"] ?: @"", @"line", [l objectForKey:@"@trainHeadStation"] ?: @"", @"head", [l objectForKey:@"@origin"] ?: @"", @"from", [l objectForKey:@"@destination"] ?: @"", @"to", [l objectForKey:@"@origTimeMin"] ?: @"", @"dep", [l objectForKey:@"@destTimeMin"] ?: @"", @"arr", nil]];
        [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:[tr objectForKey:@"@origTimeMin"] ?: @"", @"dep", [tr objectForKey:@"@destTimeMin"] ?: @"", @"arr", [NSNumber numberWithInteger:[[tr objectForKey:@"@tripTime"] integerValue]], @"mins", [tr objectForKey:@"@fare"] ?: @"", @"fare", legs, @"legs", nil]];
    }
    if (![out count] && err) *err = @"BART returned no trips.";
    return out;
}
+ (UIImage *)squareForHex:(NSString *)hex {
    if (!gSquares) gSquares = [[NSMutableDictionary alloc] init];
    if ([gSquares objectForKey:hex]) return [gSquares objectForKey:hex];
    unsigned v = 0; NSScanner *sc = [NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]]; [sc scanHexInt:&v];
    UIColor *c = [UIColor colorWithRed:((v >> 16) & 0xff) / 255.0 green:((v >> 8) & 0xff) / 255.0 blue:(v & 0xff) / 255.0 alpha:1];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(44, 26), NO, 0);
    CGContextRef g = UIGraphicsGetCurrentContext(); [c set];
    CGRect r = CGRectMake(6, 2, 22, 22); CGContextAddEllipseInRect(g, r); CGContextFillPath(g);
    if (v == 0xffffff) { [[UIColor colorWithWhite:0.6 alpha:1] set]; CGContextSetLineWidth(g, 1.5); CGContextStrokeEllipseInRect(g, r); }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [gSquares setObject:img forKey:hex]; return img;
}
@end

@implementation CTMuni
+ (NSString *)nameForStop:(NSString *)code { if (!gMuni) { NSString *p = [[NSBundle mainBundle] pathForResource:@"muni_stops" ofType:@"json"]; gMuni = [([ORJSON parse:[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]] ?: [NSDictionary dictionary]) retain]; } return [gMuni objectForKey:code]; }
+ (NSArray *)savedStops { return [[NSUserDefaults standardUserDefaults] arrayForKey:@"ct_muni_stops"] ?: [NSArray array]; }
+ (void)setSavedStops:(NSArray *)codes { [[NSUserDefaults standardUserDefaults] setObject:codes forKey:@"ct_muni_stops"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
+ (NSArray *)predictionsForStop:(NSString *)code error:(NSString **)err {
    if (![[CTData token] length]) { if (err) *err = @"Add a 511 token in Settings."; return nil; }
    id obj = getJSON([NSString stringWithFormat:@"http://api.511.org/transit/StopMonitoring?api_key=%@&agency=SF&stopCode=%@&format=json", [CTData token], code], err);
    if (!obj) return nil;
    NSArray *visits = asArray([[[obj objectForKey:@"ServiceDelivery"] objectForKey:@"StopMonitoringDelivery"] objectForKey:@"MonitoredStopVisit"]);
    NSMutableArray *out = [NSMutableArray array]; NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    static NSDateFormatter *f = nil; if (!f) { f = [[NSDateFormatter alloc] init]; [f setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"]; [f setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]]; }
    for (NSDictionary *v in visits) {
        NSDictionary *j = [v objectForKey:@"MonitoredVehicleJourney"]; NSDictionary *call = [j objectForKey:@"MonitoredCall"];
        NSString *iso = [call objectForKey:@"ExpectedArrivalTime"] ?: [call objectForKey:@"ExpectedDepartureTime"]; if (![iso isKindOfClass:[NSString class]] || [iso length] < 19) continue;
        NSDate *d = [f dateFromString:[iso substringToIndex:19]]; if (!d) continue;
        NSInteger mins = (NSInteger)(([d timeIntervalSince1970] - now) / 60); if (mins < 0) mins = 0;
        [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:[j objectForKey:@"LineRef"] ?: @"", @"route", [j objectForKey:@"DestinationName"] ?: @"", @"dest", [NSNumber numberWithInteger:mins], @"minutes", nil]];
    }
    [out sortUsingComparator:^NSComparisonResult(id p, id q) { NSInteger a = [[p objectForKey:@"minutes"] integerValue], b = [[q objectForKey:@"minutes"] integerValue]; return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame; }];
    return out;
}
@end
