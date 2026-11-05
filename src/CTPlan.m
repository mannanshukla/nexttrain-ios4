#import "CTPlan.h"
#import "CTData.h"
#import "CTAgencies.h"
#import "ORJSON.h"

static NSNumber *num(double v) { return [NSNumber numberWithDouble:v]; }
static double at(NSDictionary *d, NSString *k) { return [[d objectForKey:k] doubleValue]; }
static NSString *caltrainName(NSInteger i) { NSArray *s = [CTData stations]; return i >= 0 && i < (NSInteger)[s count] ? [[s objectAtIndex:i] objectForKey:@"name"] : @"?"; }
static NSString *bartName(NSInteger i) { NSArray *s = [CTBart stations]; return i >= 0 && i < (NSInteger)[s count] ? [[s objectAtIndex:i] objectForKey:@"name"] : @"?"; }
static NSString *bartAbbr(NSInteger i) { NSArray *s = [CTBart stations]; return i >= 0 && i < (NSInteger)[s count] ? [[s objectAtIndex:i] objectForKey:@"abbr"] : @""; }

@implementation CTAI
+ (NSString *)ask:(NSString *)system user:(NSString *)q error:(NSString **)err {
    NSArray *msgs = [NSArray arrayWithObjects:[NSDictionary dictionaryWithObjectsAndKeys:@"system", @"role", system, @"content", nil], [NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", q, @"content", nil], nil];
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:@"openrelay/gpt-oss-120b", @"model", msgs, @"messages", [NSNumber numberWithBool:NO], @"stream", [NSNumber numberWithDouble:0.1], @"temperature", nil];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://inference.openrelay.inc/v1/chat/completions"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [req setHTTPMethod:@"POST"]; [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [req setValue:[NSString stringWithFormat:@"Bearer %@", [CTData apiKey]] forHTTPHeaderField:@"Authorization"]; [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    [req setHTTPBody:[[ORJSON stringify:body] dataUsingEncoding:NSUTF8StringEncoding]];
    NSHTTPURLResponse *resp = nil; NSError *e = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&e];
    if (!data) { if (err) *err = [e localizedDescription]; return nil; }
    id obj = [ORJSON parse:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
    if ([resp statusCode] == 401) { if (err) *err = @"OpenRelay rejected the API key."; return nil; }
    if ([resp statusCode] != 200 || ![obj isKindOfClass:[NSDictionary class]]) { if (err) *err = [NSString stringWithFormat:@"OpenRelay returned HTTP %d", (int)[resp statusCode]]; return nil; }
    NSArray *choices = [obj objectForKey:@"choices"]; id content = [choices isKindOfClass:[NSArray class]] && [choices count] ? [[[choices objectAtIndex:0] objectForKey:@"message"] objectForKey:@"content"] : nil;
    if (![content isKindOfClass:[NSString class]]) { if (err) *err = @"Empty reply."; return nil; }
    return content;
}
+ (NSDictionary *)json:(NSString *)content {
    NSRange a = [content rangeOfString:@"{"], b = [content rangeOfString:@"}" options:NSBackwardsSearch];
    if (a.location == NSNotFound || b.location == NSNotFound || b.location < a.location) return nil;
    id j = [ORJSON parse:[content substringWithRange:NSMakeRange(a.location, b.location - a.location + 1)]];
    return [j isKindOfClass:[NSDictionary class]] && [[j objectForKey:@"legs"] isKindOfClass:[NSArray class]] && [[j objectForKey:@"legs"] count] ? j : nil;
}
+ (NSDictionary *)planTrip:(NSString *)q error:(NSString **)err {
    if (![[CTData apiKey] length]) { if (err) *err = @"Add your OpenRelay API key in Settings first."; return nil; }
    NSMutableArray *ct = [NSMutableArray array], *bt = [NSMutableArray array];
    for (NSDictionary *s in [CTData stations]) [ct addObject:[s objectForKey:@"name"]];
    for (NSDictionary *s in [CTBart stations]) [bt addObject:[s objectForKey:@"name"]];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]]; [f setDateFormat:@"EEEE yyyy-MM-dd HH:mm"];
    NSString *system = [NSString stringWithFormat:
        @"You plan Bay Area train trips on Caltrain and BART. Read the rider's request and reply with one JSON object only: no prose, no code fences.\n"
        @"Schema: {\"legs\":[{\"mode\":\"caltrain\"|\"bart\",\"from\":station,\"to\":station}],\"day\":\"today\"|\"tomorrow\"|\"YYYY-MM-DD\",\"time\":\"HH:MM\" 24-hour or \"now\",\"arriveBy\":bool,\"express\":bool,\"note\":string}\n"
        @"It is now %@.\n"
        @"Caltrain stations (exact names for caltrain legs): %@.\n"
        @"BART stations (exact names for bart legs): %@.\n"
        @"Routing:\n"
        @"- Use as few legs as possible. Caltrain covers the Peninsula and South Bay (San Francisco 4th and King to San Jose and Gilroy). BART covers San Francisco's Market and Mission streets, Daly City, SFO, the East Bay, Oakland airport and Berryessa.\n"
        @"- Caltrain and BART meet only at Millbrae; use Millbrae for any trip that needs both. Two legs in a row must share that station.\n"
        @"- A place that is not a station means the station nearest to it. Stanford University: Palo Alto (the Stanford station only opens for football games). SFO or the airport: San Francisco International Airport (SFO) on BART. Oakland airport: Oakland International Airport (OAK). Oracle Park, the Giants, Mission Bay, SoMa, 4th and King: San Francisco on Caltrain. Union Square, downtown SF: Powell St. The Mission: 16th St./Mission or 24th St./Mission. Berkeley or Cal: Downtown Berkeley. SAP Center: San Jose Diridon. Google: Mountain View. Downtown Palo Alto: Palo Alto.\n"
        @"- No starting point given: start at the rider's home station, %@ on Caltrain.\n"
        @"Time:\n"
        @"- arriveBy is true when they need to be there by a time (by, before, arrive, get there, land, make a meeting at). Otherwise the time is when they leave.\n"
        @"- morning 08:00, lunch 12:00, afternoon 14:00, after work 17:30, evening 19:00, tonight 21:00. No time means now.\n"
        @"- A bare hour with no AM or PM means its next occurrence from now.\n"
        @"- A weekday name means the next such day; give day as YYYY-MM-DD.\n"
        @"- express is true only when they ask for an express, a bullet or the fastest train.\n"
        @"note: one sentence under 90 characters saying how you read places you mapped to stations, or \"\" when nothing needs saying.\n"
        @"Example: \"stanford to sfo friday by 10am\" -> {\"legs\":[{\"mode\":\"caltrain\",\"from\":\"Palo Alto\",\"to\":\"Millbrae\"},{\"mode\":\"bart\",\"from\":\"Millbrae\",\"to\":\"San Francisco International Airport (SFO)\"}],\"day\":\"YYYY-MM-DD of that Friday\",\"time\":\"10:00\",\"arriveBy\":true,\"express\":false,\"note\":\"Stanford is Palo Alto station; change to BART at Millbrae.\"}",
        [f stringFromDate:[NSDate date]], [ct componentsJoinedByString:@", "], [bt componentsJoinedByString:@", "], caltrainName([CTData homeStation])];
    NSDictionary *j = nil;
    for (int attempt = 0; attempt < 2 && !j; attempt++) {   // one retry: the model occasionally wraps the JSON in prose that will not parse
        NSString *content = [self ask:system user:q error:err]; if (!content) return nil;
        j = [self json:content];
    }
    if (!j) { if (err) *err = @"Didn't get a route back. Try naming the stations."; return nil; }
    return [self planFromJSON:j error:err];
}
+ (NSDictionary *)planFromReply:(NSString *)reply error:(NSString **)err {
    NSDictionary *j = [self json:reply];
    if (!j) { if (err) *err = @"Didn't get a route back. Try naming the stations."; return nil; }
    return [self planFromJSON:j error:err];
}
+ (NSDictionary *)planFromJSON:(NSDictionary *)j error:(NSString **)err {
    NSMutableArray *legs = [NSMutableArray array];
    for (NSDictionary *l in [j objectForKey:@"legs"]) {
        if (![l isKindOfClass:[NSDictionary class]]) continue;
        BOOL bart = [[[l objectForKey:@"mode"] description] rangeOfString:@"bart" options:NSCaseInsensitiveSearch].location != NSNotFound;
        NSString *fs = [[l objectForKey:@"from"] description] ?: @"", *ts = [[l objectForKey:@"to"] description] ?: @"";
        NSInteger fi = bart ? [CTBart stationNamed:fs] : [CTData stationNamed:fs], ti = bart ? [CTBart stationNamed:ts] : [CTData stationNamed:ts];
        if (fi < 0 && ![legs count] && !bart) fi = [CTData homeStation];
        if (fi < 0 || ti < 0) { if (err) *err = [NSString stringWithFormat:@"Couldn't match %@ station \"%@\".", bart ? @"a BART" : @"a Caltrain", fi < 0 ? fs : ts]; return nil; }
        if (fi == ti) continue;
        NSMutableDictionary *leg = [NSMutableDictionary dictionaryWithObjectsAndKeys:bart ? @"bart" : @"caltrain", @"mode", [NSNumber numberWithInteger:fi], @"from", [NSNumber numberWithInteger:ti], @"to",
            bart ? bartName(fi) : caltrainName(fi), @"fromName", bart ? bartName(ti) : caltrainName(ti), @"toName", nil];
        if ([[l objectForKey:@"gap"] respondsToSelector:@selector(integerValue)] && [[l objectForKey:@"gap"] integerValue] > 0) [leg setObject:[NSNumber numberWithInteger:[[l objectForKey:@"gap"] integerValue]] forKey:@"gap"];
        [legs addObject:leg];
    }
    if (![legs count]) { if (err) *err = @"That trip starts and ends at the same station."; return nil; }

    NSInteger day = 0; NSString *ds = [[j objectForKey:@"day"] description];
    if ([ds isEqualToString:@"tomorrow"]) day = 1;
    else if ([ds length] == 10) {
        NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease]; [df setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]]; [df setDateFormat:@"yyyy-MM-dd"];
        NSDate *d = [df dateFromString:ds];
        if (d) day = (NSInteger)floor(([CTData midnightOf:[d timeIntervalSince1970] + 43200] - [CTData midnightPlus:0]) / 86400 + 0.5);
        if (day < 0 || day > 13) day = 0;
    }
    NSInteger when = -1; NSArray *hm = [[[j objectForKey:@"time"] description] componentsSeparatedByString:@":"];
    if ([hm count] == 2) when = [[hm objectAtIndex:0] integerValue] * 60 + [[hm objectAtIndex:1] integerValue];
    if (when >= 0 && day == 0 && when < 12 * 60 && when + 60 < [CTData minutesNow]) when += 12 * 60;   // "by 6" asked at 8 AM means 6 PM
    NSString *note = [[j objectForKey:@"note"] isKindOfClass:[NSString class]] ? [j objectForKey:@"note"] : @"";
    return [NSDictionary dictionaryWithObjectsAndKeys:legs, @"legs", [NSNumber numberWithInteger:day], @"day", [NSNumber numberWithInteger:when], @"when",
        [NSNumber numberWithBool:[[j objectForKey:@"arriveBy"] boolValue] && when >= 0], @"arriveBy", [NSNumber numberWithBool:[[j objectForKey:@"express"] boolValue]], @"express", note, @"note", nil];
}
@end

static NSString *bartShort(NSString *abbr) {   // "SFO is next" fits the timer; the full airport names do not
    if ([abbr isEqualToString:@"SFIA"]) return @"SFO"; if ([abbr isEqualToString:@"OAKL"]) return @"Oakland Airport";
    return [CTBart nameForAbbr:abbr];
}

@implementation CTRoute
+ (NSDictionary *)caltrainTrip:(NSDictionary *)trip from:(NSInteger)fi to:(NSInteger)ti base:(NSTimeInterval)midnight {
    NSArray *stops = [trip objectForKey:@"stops"]; NSArray *a = [stops objectAtIndex:fi], *b = [stops objectAtIndex:ti];
    NSInteger sa = [[a objectAtIndex:0] integerValue], sb = [[b objectAtIndex:0] integerValue]; NSString *dk = [[trip objectForKey:@"dir"] integerValue] == 0 ? @"N" : @"S";
    NSArray *st = [CTData stations];
    return [NSDictionary dictionaryWithObjectsAndKeys:@"caltrain", @"mode", caltrainName(sa), @"from", caltrainName(sb), @"to",
        num(midnight + [[a objectAtIndex:1] integerValue] * 60), @"depAt", num(midnight + [[b objectAtIndex:2] integerValue] * 60), @"arrAt",
        [NSString stringWithFormat:@"%@ %@", [trip objectForKey:@"type"], [trip objectForKey:@"n"]], @"label", trip, @"trip", [NSNumber numberWithInteger:fi], @"fromIdx", [NSNumber numberWithInteger:ti], @"toIdx",
        [[trip objectForKey:@"n"] description], @"train", [[[st objectAtIndex:sa] objectForKey:@"codes"] objectForKey:dk] ?: @"", @"fromCode", [[[st objectAtIndex:sb] objectForKey:@"codes"] objectForKey:dk] ?: @"", @"toCode", nil];
}
+ (NSDictionary *)bartLeg:(NSDictionary *)l {
    NSString *head = [[[[l objectForKey:@"head"] componentsSeparatedByString:@" / "] lastObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];   // "SFO / SF / Richmond"; station names keep their own slashes
    return [NSDictionary dictionaryWithObjectsAndKeys:@"bart", @"mode", bartShort([l objectForKey:@"from"]), @"from", bartShort([l objectForKey:@"to"]), @"to", [l objectForKey:@"from"], @"fromAbbr", [l objectForKey:@"to"], @"toAbbr",
        [l objectForKey:@"depAt"], @"depAt", [l objectForKey:@"arrAt"], @"arrAt", [l objectForKey:@"head"] ?: @"", @"head", [head length] ? [NSString stringWithFormat:@"BART to %@", head] : @"BART", @"label", nil];
}
// Ways to ride one planned leg near time t. Each option is an array of segments (a BART trip can carry its own transfers).
// Departing at or after t, earliest first; or with arriveBy, arriving by t, latest first.
+ (NSArray *)options:(NSDictionary *)leg at:(NSTimeInterval)t arriveBy:(BOOL)by express:(BOOL)express error:(NSString **)err {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger a = [[leg objectForKey:@"from"] integerValue], b = [[leg objectForKey:@"to"] integerValue];
    if ([[leg objectForKey:@"mode"] isEqualToString:@"bart"]) {
        NSArray *trips = [CTBart tripsFrom:bartAbbr(a) to:bartAbbr(b) at:t arriveBy:by error:err];
        for (NSDictionary *x in (by ? [trips reverseObjectEnumerator] : [trips objectEnumerator])) {
            NSMutableArray *segs = [NSMutableArray array]; for (NSDictionary *l in [x objectForKey:@"legs"]) [segs addObject:[self bartLeg:l]];
            if ([segs count]) [out addObject:segs];
        }
        return out;
    }
    NSTimeInterval mid = [CTData midnightOf:t]; NSInteger m = (NSInteger)floor((t - mid) / 60); NSArray *trips = nil;
    if (!by && m < 4 * 60) {   // 1 AM is still last night's service day; fall back to this morning's first trains
        trips = [CTData tripsFrom:a to:b date:[NSDate dateWithTimeIntervalSince1970:mid - 86400 + 43200] leaveAfter:m + 1440 arriveBy:-1];
        if ([trips count]) mid -= 86400;
    }
    if (![trips count]) trips = [CTData tripsFrom:a to:b date:[NSDate dateWithTimeIntervalSince1970:mid + 43200] leaveAfter:by ? -1 : m arriveBy:by ? m : -1];
    NSMutableArray *fast = [NSMutableArray array];
    if (express) for (NSDictionary *d in trips) { NSString *ty = [[d objectForKey:@"trip"] objectForKey:@"type"]; if ([ty isEqualToString:@"Express"] || [ty isEqualToString:@"Limited"]) [fast addObject:d]; }
    for (NSDictionary *d in ([fast count] ? fast : trips)) {
        [out addObject:[NSArray arrayWithObject:[self caltrainTrip:[d objectForKey:@"trip"] from:[[d objectForKey:@"fromIdx"] integerValue] to:[[d objectForKey:@"toIdx"] integerValue] base:mid]]];
        if ([out count] >= 6) break;
    }
    if (![out count] && err) *err = [NSString stringWithFormat:@"No Caltrain from %@ to %@ %@.", caltrainName(a), caltrainName(b), by ? @"arrives by then" : @"after that"];
    return out;
}
+ (NSTimeInterval)gapFrom:(NSDictionary *)prev to:(NSDictionary *)next {
    if ([[next objectForKey:@"gap"] integerValue] > 0) return [[next objectForKey:@"gap"] integerValue] * 60;
    if ([[prev objectForKey:@"mode"] isEqualToString:[next objectForKey:@"mode"]]) return 3 * 60;
    if ([[prev objectForKey:@"toName"] hasPrefix:@"Millbrae"] && [[next objectForKey:@"fromName"] hasPrefix:@"Millbrae"]) return 5 * 60;   // same building
    return 15 * 60;   // different stations: a walk or a Muni ride between them
}
// Cached answers per leg: a later lookup can reuse an earlier one when it already covers the new time.
+ (NSArray *)option:(NSDictionary *)leg at:(NSTimeInterval)t arriveBy:(BOOL)by express:(BOOL)express cache:(NSMutableDictionary *)cache key:(NSString *)key error:(NSString **)err {
    NSDictionary *c = [cache objectForKey:key];
    if (c && (by ? at(c, @"t") >= t : at(c, @"t") <= t)) {
        for (NSArray *o in [c objectForKey:@"opts"]) {
            NSTimeInterval d = at([o objectAtIndex:0], @"depAt"), r = at([o lastObject], @"arrAt");
            if (by ? r <= t : d >= t) return o;
        }
    }
    NSArray *opts = [self options:leg at:t arriveBy:by express:express error:err];
    [cache setObject:[NSDictionary dictionaryWithObjectsAndKeys:num(t), @"t", opts ?: [NSArray array], @"opts", nil] forKey:key];
    return [opts count] ? [opts objectAtIndex:0] : nil;
}
+ (NSArray *)itinerariesFor:(NSDictionary *)plan error:(NSString **)err {
    NSArray *legs = [plan objectForKey:@"legs"]; NSInteger n = [legs count]; if (!n) { if (err) *err = @"No route."; return nil; }
    NSInteger day = [[plan objectForKey:@"day"] integerValue], when = [[plan objectForKey:@"when"] integerValue];
    BOOL by = [[plan objectForKey:@"arriveBy"] boolValue] && when >= 0, express = [[plan objectForKey:@"express"] boolValue];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970], base = [CTData midnightPlus:day];
    NSTimeInterval t = when >= 0 ? base + when * 60 : (day == 0 ? now : base + 4 * 3600);
    if (!by && t < now - 60) t = now;
    NSMutableArray *its = [NSMutableArray array]; NSMutableDictionary *cache = [NSMutableDictionary dictionary]; NSString *e = nil;
    NSArray *ends = [self options:[legs objectAtIndex:by ? n - 1 : 0] at:t arriveBy:by express:express error:&e];
    for (NSArray *end in ends) {
        if ([its count] >= 4) break;
        NSMutableArray *segs = [NSMutableArray arrayWithArray:end]; BOOL ok = YES;
        if (!by) for (NSInteger i = 1; i < n && ok; i++) {
            NSDictionary *leg = [legs objectAtIndex:i];
            NSArray *o = [self option:leg at:at([segs lastObject], @"arrAt") + [self gapFrom:[legs objectAtIndex:i - 1] to:leg] arriveBy:NO express:express cache:cache key:[NSString stringWithFormat:@"%ld", (long)i] error:&e];
            if (o) [segs addObjectsFromArray:o]; else ok = NO;
        }
        else for (NSInteger i = n - 2; i >= 0 && ok; i--) {
            NSDictionary *leg = [legs objectAtIndex:i];
            NSArray *o = [self option:leg at:at([segs objectAtIndex:0], @"depAt") - [self gapFrom:leg to:[legs objectAtIndex:i + 1]] arriveBy:YES express:express cache:cache key:[NSString stringWithFormat:@"%ld", (long)i] error:&e];
            if (o) [segs replaceObjectsInRange:NSMakeRange(0, 0) withObjectsFromArray:o]; else ok = NO;
        }
        if (!ok) continue;
        NSDictionary *it = [NSDictionary dictionaryWithObjectsAndKeys:[[segs objectAtIndex:0] objectForKey:@"depAt"], @"depAt", [[segs lastObject] objectForKey:@"arrAt"], @"arrAt", segs, @"segs", nil];
        BOOL dup = NO;   // two first trains that make the same connection: keep the one that lets you leave later
        for (NSUInteger k = 0; k < [its count]; k++) {
            NSDictionary *o = [its objectAtIndex:k];
            if (at(o, @"arrAt") == at(it, @"arrAt")) { dup = YES; if (at(it, @"depAt") > at(o, @"depAt")) [its replaceObjectAtIndex:k withObject:it]; break; }
            if (by && at(o, @"depAt") == at(it, @"depAt")) { dup = YES; if (at(it, @"arrAt") < at(o, @"arrAt")) [its replaceObjectAtIndex:k withObject:it]; break; }
        }
        if (!dup) [its addObject:it];
    }
    [its sortUsingComparator:^NSComparisonResult(id x, id y) { double p = at(x, @"depAt"), q = at(y, @"depAt"); return p < q ? NSOrderedAscending : p > q ? NSOrderedDescending : NSOrderedSame; }];
    if (![its count] && err) *err = e ?: @"No connection works at that time.";
    return its;
}
+ (NSDictionary *)ring:(NSTimeInterval)t say:(NSString *)say sub:(NSString *)sub kind:(NSString *)kind seg:(NSDictionary *)seg code:(NSString *)codeKey base:(NSTimeInterval)base lead:(NSTimeInterval)lead {
    NSMutableDictionary *r = [NSMutableDictionary dictionaryWithObjectsAndKeys:num(t), @"at", say, @"say", sub ?: @"", @"sub", kind, @"kind", nil];
    if ([[seg objectForKey:@"mode"] isEqualToString:@"caltrain"] && [[seg objectForKey:codeKey] length]) {   // lets the timer follow the train with 511
        [r setObject:[seg objectForKey:codeKey] forKey:@"code"]; [r setObject:[seg objectForKey:@"train"] forKey:@"train"]; [r setObject:num(base) forKey:@"base"]; [r setObject:num(lead) forKey:@"lead"];
    }
    return r;
}
+ (NSDictionary *)leaveRingFor:(NSDictionary *)seg {
    NSTimeInterval walk = [CTData walkMinutes] * 60, dep = at(seg, @"depAt"), t = dep - walk;
    if (t < [[NSDate date] timeIntervalSince1970] + 30) return nil;
    return [self ring:t say:@"Time to leave" sub:[NSString stringWithFormat:@"%@ leaves %@ at %@. %ld min walk.", [seg objectForKey:@"label"], [seg objectForKey:@"from"], [CTData fmtTime:dep], (long)[CTData walkMinutes]] kind:@"leave" seg:seg code:@"fromCode" base:dep lead:walk];
}
+ (NSArray *)ringsFor:(NSArray *)segs leave:(BOOL)leave {
    NSMutableArray *out = [NSMutableArray array]; NSTimeInterval now = [[NSDate date] timeIntervalSince1970], lead = [CTData leadMinutes] * 60;
    if (leave && [segs count]) { NSDictionary *r = [self leaveRingFor:[segs objectAtIndex:0]]; if (r) [out addObject:r]; }
    for (NSUInteger i = 0; i < [segs count]; i++) {
        NSDictionary *s = [segs objectAtIndex:i], *next = i + 1 < [segs count] ? [segs objectAtIndex:i + 1] : nil;
        NSTimeInterval arr = at(s, @"arrAt"), t = MAX(arr - lead, MIN(at(s, @"depAt") + 60, arr - 30));   // a one-stop hop still rings after you board
        if (t <= now) continue;
        NSString *sub = !next ? @"Get your stuff." : [[next objectForKey:@"from"] isEqualToString:[s objectForKey:@"to"]]
            ? [NSString stringWithFormat:@"Change to %@, %@.", [next objectForKey:@"label"], [CTData fmtTime:at(next, @"depAt")]]
            : [NSString stringWithFormat:@"Then %@ from %@ at %@.", [next objectForKey:@"label"], [next objectForKey:@"from"], [CTData fmtTime:at(next, @"depAt")]];
        [out addObject:[self ring:t say:[NSString stringWithFormat:@"%@ is next", [s objectForKey:@"to"]] sub:sub kind:@"stop" seg:s code:@"toCode" base:arr lead:arr - t]];
    }
    return out;
}
+ (NSString *)summary:(NSDictionary *)it {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSDictionary *s in [it objectForKey:@"segs"])
        [parts addObject:[[s objectForKey:@"mode"] isEqualToString:@"caltrain"] ? [NSString stringWithFormat:@"%@ to %@", [s objectForKey:@"label"], [s objectForKey:@"to"]] : [NSString stringWithFormat:@"BART to %@", [s objectForKey:@"to"]]];
    return [parts componentsJoinedByString:@", then "];
}
@end
