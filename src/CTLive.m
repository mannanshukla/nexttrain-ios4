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

@implementation CTAI
+ (NSDictionary *)runForTrainIn:(NSInteger)mins walk:(NSInteger)walk next:(NSInteger)next error:(NSString **)err {
    if (![[CTData apiKey] length]) { if (err) *err = @"Add your OpenRelay API key in Settings first."; return nil; }
    NSString *state = [NSString stringWithFormat:@"A Caltrain rider is deciding whether to run for a train. The train leaves in %ld minutes. Walking normally, the platform is about %ld minutes away; running cuts that roughly in half. The next train after this one is in %@. Trains sometimes leave up to a minute early from the rider's point of view.", (long)mins, (long)walk, next > 0 ? [NSString stringWithFormat:@"%ld minutes", (long)next] : @"a long time, or there is none"];
    NSDictionary *q = [NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"noul", @"type", @"Should the rider run for this train?", @"instructions",
        [NSDictionary dictionaryWithObjectsAndKeys:@"running is worth it and will probably make the train", @"true", @"do not bother, it is too tight or the next train is soon enough", @"false", nil], @"criteria", nil] forKey:@"run"];
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:@"openrelay/laya", @"model", state, @"state", q, @"questions", nil];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://inference.openrelay.inc/v1/decisions"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [req setHTTPMethod:@"POST"]; [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [req setValue:[NSString stringWithFormat:@"Bearer %@", [CTData apiKey]] forHTTPHeaderField:@"Authorization"]; [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    [req setHTTPBody:[[ORJSON stringify:body] dataUsingEncoding:NSUTF8StringEncoding]];
    NSHTTPURLResponse *resp = nil; NSError *e = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&e];
    if (!data) { if (err) *err = [e localizedDescription]; return nil; }
    id obj = [ORJSON parse:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
    if ([resp statusCode] != 200 || ![obj isKindOfClass:[NSDictionary class]]) { if (err) *err = [NSString stringWithFormat:@"HTTP %d", (int)[resp statusCode]]; return nil; }
    NSDictionary *a = [[obj objectForKey:@"answers"] objectForKey:@"run"];
    if (![a isKindOfClass:[NSDictionary class]]) { if (err) *err = @"Laya gave no answer."; return nil; }
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:[[a objectForKey:@"noul"] doubleValue]], @"p", [NSNumber numberWithDouble:[[a objectForKey:@"confidence"] doubleValue]], @"confidence", nil];
}
+ (NSDictionary *)parseAsk:(NSString *)q error:(NSString **)err {
    if (![[CTData apiKey] length]) { if (err) *err = @"Add your OpenRelay API key in Settings first."; return nil; }
    NSMutableArray *names = [NSMutableArray array]; for (NSDictionary *s in [CTData stations]) [names addObject:[s objectForKey:@"name"]];
    NSString *system = [NSString stringWithFormat:@"You turn a casual Caltrain request into JSON. Reply with JSON only, no prose. Schema: {\"from\":string,\"to\":string,\"when\":\"HH:MM\" 24-hour or \"now\",\"arriveBy\":bool}. "
        @"from and to must be exactly one of these station names: %@. Map nicknames: SF, the city and 4th and King mean San Francisco; San Jose, SJ and Diridon mean San Jose Diridon; MV means Mountain View; the airport means Millbrae. "
        @"arriveBy is true when the person wants to be there by a time (by, before, land by, arrive). Vague times: morning 08:00, after work 17:30, evening 19:00, tonight 21:00, now when unspecified. A bare hour with no AM or PM means the next occurrence of that hour; if it has already passed this morning, use PM. If a station is missing or unclear use the home station %@ as from.",
        [names componentsJoinedByString:@", "], [[[CTData stations] objectAtIndex:[CTData homeStation]] objectForKey:@"name"]];
    NSArray *msgs = [NSArray arrayWithObjects:[NSDictionary dictionaryWithObjectsAndKeys:@"system", @"role", system, @"content", nil], [NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", q, @"content", nil], nil];
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:@"openrelay/gpt-oss-120b", @"model", msgs, @"messages", [NSNumber numberWithBool:NO], @"stream", [NSNumber numberWithDouble:0.1], @"temperature", nil];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://inference.openrelay.inc/v1/chat/completions"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [req setHTTPMethod:@"POST"]; [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [req setValue:[NSString stringWithFormat:@"Bearer %@", [CTData apiKey]] forHTTPHeaderField:@"Authorization"]; [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    [req setHTTPBody:[[ORJSON stringify:body] dataUsingEncoding:NSUTF8StringEncoding]];
    NSHTTPURLResponse *resp = nil; NSError *e = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&e];
    if (!data) { if (err) *err = [e localizedDescription]; return nil; }
    id obj = [ORJSON parse:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
    if ([resp statusCode] != 200 || ![obj isKindOfClass:[NSDictionary class]]) { if (err) *err = [NSString stringWithFormat:@"HTTP %d", (int)[resp statusCode]]; return nil; }
    NSArray *choices = [obj objectForKey:@"choices"]; id content = [choices count] ? [[[choices objectAtIndex:0] objectForKey:@"message"] objectForKey:@"content"] : nil;
    if (![content isKindOfClass:[NSString class]]) { if (err) *err = @"Empty reply."; return nil; }
    NSRange a = [content rangeOfString:@"{"], b = [content rangeOfString:@"}" options:NSBackwardsSearch];
    if (a.location == NSNotFound || b.location == NSNotFound) { if (err) *err = @"Didn't get JSON back."; return nil; }
    NSDictionary *j = [ORJSON parse:[content substringWithRange:NSMakeRange(a.location, b.location - a.location + 1)]];
    if (![j isKindOfClass:[NSDictionary class]]) { if (err) *err = @"Didn't get JSON back."; return nil; }
    NSInteger from = [CTData stationNamed:[[j objectForKey:@"from"] description]], to = [CTData stationNamed:[[j objectForKey:@"to"] description]];
    if (from < 0) from = [CTData homeStation];
    if (to < 0) { if (err) *err = [NSString stringWithFormat:@"Couldn't match a station in \"%@\".", [j objectForKey:@"to"] ?: @""]; return nil; }
    NSInteger when = -1; NSString *w = [[j objectForKey:@"when"] description]; NSArray *hm = [w componentsSeparatedByString:@":"];
    if ([hm count] == 2) when = [[hm objectAtIndex:0] integerValue] * 60 + [[hm objectAtIndex:1] integerValue];
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:from], @"from", [NSNumber numberWithInteger:to], @"to", [NSNumber numberWithInteger:when], @"when", [NSNumber numberWithBool:[[j objectForKey:@"arriveBy"] boolValue]], @"arriveBy", nil];
}
@end
