#import "CTData.h"
#import "ORJSON.h"

static NSDictionary *gFeed = nil; static NSMutableDictionary *gBadges = nil;

@implementation CTData
+ (NSDictionary *)feed {
    if (!gFeed) { NSString *p = [[NSBundle mainBundle] pathForResource:@"caltrain" ofType:@"json"]; gFeed = [[ORJSON parse:[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]] retain]; }
    return gFeed;
}
+ (NSArray *)stations { return [[self feed] objectForKey:@"stations"]; }
+ (NSString *)feedVersion { return [[self feed] objectForKey:@"version"]; }
+ (NSString *)feedEnd { return [[self feed] objectForKey:@"end"]; }
+ (NSInteger)stationNamed:(NSString *)q {
    NSString *s = [[q lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (![s length]) return -1;
    NSDictionary *alias = [NSDictionary dictionaryWithObjectsAndKeys:@"san francisco", @"sf", @"san francisco", @"the city", @"san francisco", @"4th and king", @"san jose diridon", @"san jose", @"san jose diridon", @"diridon", @"san jose diridon", @"sj", @"mountain view", @"mv", @"palo alto", @"pa", @"redwood city", @"rwc", @"south san francisco", @"south sf", @"south san francisco", @"ssf", @"millbrae", @"airport", @"san mateo", @"sm", nil];
    if ([alias objectForKey:s]) s = [alias objectForKey:s];
    NSArray *st = [self stations];
    for (NSUInteger i = 0; i < [st count]; i++) if ([[[[st objectAtIndex:i] objectForKey:@"name"] lowercaseString] isEqualToString:s]) return i;
    for (NSUInteger i = 0; i < [st count]; i++) if ([[[[st objectAtIndex:i] objectForKey:@"name"] lowercaseString] hasPrefix:s]) return i;
    for (NSUInteger i = 0; i < [st count]; i++) if ([[[[st objectAtIndex:i] objectForKey:@"name"] lowercaseString] rangeOfString:s].location != NSNotFound) return i;
    return -1;
}
+ (NSString *)dateKey:(NSDate *)d { static NSDateFormatter *f = nil; if (!f) { f = [[NSDateFormatter alloc] init]; [f setDateFormat:@"yyyyMMdd"]; } return [f stringFromDate:d]; }
+ (NSInteger)minutesNow { NSDateComponents *c = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:[NSDate date]]; return [c hour] * 60 + [c minute]; }
+ (NSString *)fmtMin:(NSInteger)m { m = ((m % 1440) + 1440) % 1440; NSInteger h = m / 60; return [NSString stringWithFormat:@"%ld:%02ld %@", (long)(h % 12 == 0 ? 12 : h % 12), (long)(m % 60), h < 12 ? @"AM" : @"PM"]; }
+ (NSSet *)activeServicesOn:(NSDate *)date {
    NSString *key = [self dateKey:date];
    NSInteger wd = ([[[NSCalendar currentCalendar] components:NSWeekdayCalendarUnit fromDate:date] weekday] + 5) % 7;   // Mon = 0
    NSMutableSet *on = [NSMutableSet set];
    NSDictionary *svcs = [[self feed] objectForKey:@"services"];
    for (NSString *sid in svcs) {
        NSDictionary *s = [svcs objectForKey:sid];
        if ([key compare:[s objectForKey:@"start"]] == NSOrderedAscending || [key compare:[s objectForKey:@"end"]] == NSOrderedDescending) continue;
        if ([[[s objectForKey:@"days"] objectAtIndex:wd] boolValue]) [on addObject:sid];
    }
    for (NSDictionary *e in [[self feed] objectForKey:@"exceptions"]) {
        if (![[e objectForKey:@"date"] isEqualToString:key]) continue;
        if ([[e objectForKey:@"type"] intValue] == 1) [on addObject:[e objectForKey:@"svc"]]; else [on removeObject:[e objectForKey:@"svc"]];
    }
    return on;
}
+ (NSDate *)dayBefore:(NSDate *)d { NSDateComponents *c = [[[NSDateComponents alloc] init] autorelease]; [c setDay:-1]; return [[NSCalendar currentCalendar] dateByAddingComponents:c toDate:d options:0]; }
+ (NSArray *)departuresFrom:(NSInteger)s dir:(NSInteger)dir date:(NSDate *)date after:(NSInteger)m {
    NSMutableArray *out = [NSMutableArray array];
    NSSet *today = [self activeServicesOn:date], *yesterday = [self activeServicesOn:[self dayBefore:date]];
    for (NSDictionary *t in [[self feed] objectForKey:@"trips"]) {
        if ([[t objectForKey:@"dir"] integerValue] != dir) continue;
        NSString *svc = [t objectForKey:@"svc"]; NSArray *stops = [t objectForKey:@"stops"];
        for (NSUInteger i = 0; i + 1 < [stops count]; i++) {
            NSArray *st = [stops objectAtIndex:i]; if ([[st objectAtIndex:0] integerValue] != s) continue;
            NSInteger dep = [[st objectAtIndex:1] integerValue];
            if ([today containsObject:svc] && dep >= m) [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:t, @"trip", [NSNumber numberWithInteger:dep], @"dep", [NSNumber numberWithInteger:i], @"idx", nil]];
            if ([yesterday containsObject:svc] && dep >= 1440 && dep - 1440 >= m) [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:t, @"trip", [NSNumber numberWithInteger:dep - 1440], @"dep", [NSNumber numberWithInteger:i], @"idx", nil]];
            break;
        }
    }
    [out sortUsingComparator:^NSComparisonResult(id x, id y) { NSInteger p = [[x objectForKey:@"dep"] integerValue], q = [[y objectForKey:@"dep"] integerValue]; return p < q ? NSOrderedAscending : p > q ? NSOrderedDescending : NSOrderedSame; }];
    return out;
}
+ (NSArray *)tripsFrom:(NSInteger)a to:(NSInteger)b date:(NSDate *)date leaveAfter:(NSInteger)leave arriveBy:(NSInteger)by {
    NSMutableArray *out = [NSMutableArray array];
    NSSet *today = [self activeServicesOn:date];
    for (NSDictionary *t in [[self feed] objectForKey:@"trips"]) {
        if (![today containsObject:[t objectForKey:@"svc"]]) continue;
        NSArray *stops = [t objectForKey:@"stops"]; NSInteger ia = -1, ib = -1;
        for (NSUInteger i = 0; i < [stops count]; i++) { NSInteger sid = [[[stops objectAtIndex:i] objectAtIndex:0] integerValue]; if (sid == a && ia < 0) ia = i; else if (sid == b && ia >= 0) { ib = i; break; } }
        if (ia < 0 || ib < 0) continue;
        NSInteger dep = [[[stops objectAtIndex:ia] objectAtIndex:1] integerValue], arr = [[[stops objectAtIndex:ib] objectAtIndex:2] integerValue];
        if (leave >= 0 && dep < leave) continue;
        if (by >= 0 && arr > by) continue;
        [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:t, @"trip", [NSNumber numberWithInteger:dep], @"dep", [NSNumber numberWithInteger:arr], @"arr", [NSNumber numberWithInteger:ia], @"fromIdx", [NSNumber numberWithInteger:ib], @"toIdx", nil]];
    }
    [out sortUsingComparator:^NSComparisonResult(id x, id y) { NSInteger p = [[x objectForKey:@"dep"] integerValue], q = [[y objectForKey:@"dep"] integerValue]; return p < q ? NSOrderedAscending : p > q ? NSOrderedDescending : NSOrderedSame; }];
    if (by >= 0) { NSMutableArray *r = [NSMutableArray array]; for (id x in [out reverseObjectEnumerator]) [r addObject:x]; return r; }
    return out;
}
+ (double)fareFrom:(NSInteger)a to:(NSInteger)b {
    NSArray *st = [self stations]; if (a < 0 || b < 0 || a >= (NSInteger)[st count] || b >= (NSInteger)[st count]) return 0;
    NSString *k = [NSString stringWithFormat:@"%@-%@", [[st objectAtIndex:a] objectForKey:@"zone"], [[st objectAtIndex:b] objectForKey:@"zone"]];
    return [[[[self feed] objectForKey:@"fares"] objectForKey:k] doubleValue];
}
+ (UIColor *)colorForType:(NSString *)type {
    if ([type isEqualToString:@"Express"]) return [UIColor colorWithRed:0.89 green:0.09 blue:0.22 alpha:1];
    if ([type isEqualToString:@"Limited"]) return [UIColor colorWithRed:0.18 green:0.43 blue:0.71 alpha:1];
    if ([type isEqualToString:@"South County"]) return [UIColor colorWithRed:0.35 green:0.56 blue:0.16 alpha:1];
    return [UIColor colorWithWhite:0.45 alpha:1];
}
+ (UIImage *)badgeForType:(NSString *)type {
    NSString *txt = [type isEqualToString:@"Express"] ? @"EXP" : [type isEqualToString:@"Limited"] ? @"LTD" : [type isEqualToString:@"South County"] ? @"SC" : @"LCL";
    return [self badgeText:txt color:[self colorForType:type]];
}
+ (UIImage *)badgeText:(NSString *)txt color:(UIColor *)color {
    if (!gBadges) gBadges = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithFormat:@"%@|%@", txt, color];
    if ([gBadges objectForKey:key]) return [gBadges objectForKey:key];
    CGSize sz = CGSizeMake(44, 26);
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    [color set];
    CGFloat r = 5;
    CGContextMoveToPoint(c, r, 0); CGContextAddArcToPoint(c, sz.width, 0, sz.width, sz.height, r); CGContextAddArcToPoint(c, sz.width, sz.height, 0, sz.height, r); CGContextAddArcToPoint(c, 0, sz.height, 0, 0, r); CGContextAddArcToPoint(c, 0, 0, sz.width, 0, r); CGContextFillPath(c);
    [[UIColor whiteColor] set];
    [txt drawInRect:CGRectMake(0, 5, sz.width, 16) withFont:[UIFont boldSystemFontOfSize:[txt length] > 3 ? 10 : 12] lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentCenter];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [gBadges setObject:img forKey:key]; return img;
}
+ (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }
+ (NSString *)apiKey { return [[self d] stringForKey:@"ct_api_key"] ?: @""; }
+ (void)setApiKey:(NSString *)k { [[self d] setObject:k forKey:@"ct_api_key"]; [[self d] synchronize]; }
+ (NSString *)token { return [[self d] stringForKey:@"ct_511"] ?: @""; }
+ (void)setToken:(NSString *)t { [[self d] setObject:t forKey:@"ct_511"]; [[self d] synchronize]; }
+ (NSInteger)homeStation { id v = [[self d] objectForKey:@"ct_home"]; return v ? [v integerValue] : [self stationNamed:@"palo alto"]; }
+ (void)setHomeStation:(NSInteger)s { [[self d] setInteger:s forKey:@"ct_home"]; [[self d] synchronize]; }
+ (NSInteger)walkMinutes { id v = [[self d] objectForKey:@"ct_walk"]; return v ? [v integerValue] : 4; }
+ (void)setWalkMinutes:(NSInteger)m { [[self d] setInteger:m forKey:@"ct_walk"]; [[self d] synchronize]; }
+ (NSInteger)homeDir { return [[self d] integerForKey:@"ct_dir"]; }
+ (void)setHomeDir:(NSInteger)dir { [[self d] setInteger:dir forKey:@"ct_dir"]; [[self d] synchronize]; }
@end
