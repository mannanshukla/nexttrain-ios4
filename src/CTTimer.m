#import "CTTimer.h"
#import "CTData.h"
#import "CTLive.h"
#import "CTPlan.h"
#import "CTViews.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

NSString *const CTTimerChanged = @"CTTimerChanged";

static UIViewController *gHost = nil; static CTTimerViewController *gScreen = nil; static CTTimer *gHelper = nil;
static NSTimer *gTick = nil, *gSoundTimer = nil; static SystemSoundID gSound = 0; static NSTimeInterval gSoundUntil = 0;
static BOOL gLiveBusy = NO; static NSTimeInterval gLiveAt = 0; static NSString *gLiveText = nil;
static NSArray *gOfferSegs = nil; static NSString *gOfferTitle = nil; static BOOL gOfferLeave = NO;

static NSTimeInterval now(void) { return [[NSDate date] timeIntervalSince1970]; }
static double at(NSDictionary *r) { return [[r objectForKey:@"at"] doubleValue]; }
static UIColor *amber(CGFloat a) { return [UIColor colorWithRed:1.0 green:0.69 blue:0.0 alpha:a]; }
static UIFont *boardFont(CGFloat sz) { return [UIFont fontWithName:@"CourierNewPS-BoldMT" size:sz] ?: [UIFont boldSystemFontOfSize:sz]; }
static NSString *countdown(NSTimeInterval s) { long t = (long)ceil(MAX(0, s)); return t >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", t / 3600, t % 3600 / 60, t % 60] : [NSString stringWithFormat:@"%ld:%02ld", t / 60, t % 60]; }

@implementation CTTimer
+ (void)setHost:(UIViewController *)vc { [gHost release]; gHost = [vc retain]; if (!gHelper) gHelper = [[CTTimer alloc] init]; [self tick]; }
+ (NSDictionary *)current { NSDictionary *t = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ct_timer"]; return [[t objectForKey:@"rings"] count] ? t : nil; }
+ (NSArray *)rings { return [[self current] objectForKey:@"rings"]; }
+ (NSDictionary *)nextRing { NSArray *r = [self rings]; return [r count] ? [r objectAtIndex:0] : nil; }

+ (void)schedule {   // the notifications mirror the rings exactly; nothing else in the app uses them
    UIApplication *app = [UIApplication sharedApplication]; [app cancelAllLocalNotifications];
    NSString *title = [[self current] objectForKey:@"title"];
    for (NSDictionary *r in [self rings]) {
        if (at(r) <= now()) continue;
        UILocalNotification *n = [[UILocalNotification alloc] init];
        n.fireDate = [NSDate dateWithTimeIntervalSince1970:at(r)]; n.timeZone = nil;
        n.alertBody = [[r objectForKey:@"sub"] length] ? [NSString stringWithFormat:@"%@. %@", [r objectForKey:@"say"], [r objectForKey:@"sub"]] : [r objectForKey:@"say"];
        n.alertAction = @"stop"; n.soundName = @"ring.caf"; n.userInfo = [NSDictionary dictionaryWithObject:title ?: @"" forKey:@"title"];
        [app scheduleLocalNotification:n]; [n release];
    }
}
+ (void)save:(NSString *)title rings:(NSArray *)rings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([rings count]) {
        NSArray *sorted = [rings sortedArrayUsingComparator:^NSComparisonResult(id x, id y) { double p = at(x), q = at(y); return p < q ? NSOrderedAscending : p > q ? NSOrderedDescending : NSOrderedSame; }];
        [d setObject:[NSDictionary dictionaryWithObjectsAndKeys:title ?: @"Timer", @"title", sorted, @"rings", nil] forKey:@"ct_timer"];
    } else [d removeObjectForKey:@"ct_timer"];
    [d synchronize];
    [self schedule]; [self tick];
}
+ (void)startTitle:(NSString *)title rings:(NSArray *)rings show:(BOOL)show {
    if (![rings count]) { [[[[UIAlertView alloc] initWithTitle:@"Nothing to ring for" message:@"That train has already reached the stop." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show]; return; }
    [gLiveText release]; gLiveText = nil; gLiveAt = 0;
    [self save:title rings:rings];
    [self refreshLive];
    if (show) [self show];
}
+ (void)cancel { [self stopSound]; [self save:nil rings:nil]; [gScreen close]; }
+ (void)stopRing {
    [self stopSound];
    NSMutableArray *r = [NSMutableArray arrayWithArray:[self rings]];
    while ([r count] && at([r objectAtIndex:0]) <= now() + 5) [r removeObjectAtIndex:0];
    [self save:[[self current] objectForKey:@"title"] rings:r];
    if (![r count]) [gScreen close]; else [gScreen refresh];
}
+ (void)prune {   // rings that went off long ago, as notifications nobody opened
    NSArray *rings = [self rings]; NSMutableArray *r = [NSMutableArray arrayWithArray:rings];
    if ([gScreen isRinging]) return;
    while ([r count] && at([r objectAtIndex:0]) < now() - 180) [r removeObjectAtIndex:0];
    if ([r count] != [rings count]) [self save:[[self current] objectForKey:@"title"] rings:r];
}

#pragma mark Screen
+ (void)present:(CTTimerViewController *)v {
    [[CTDrum shared] hide];
    UIViewController *top = gHost; while (top.modalViewController) top = top.modalViewController;
    UINavigationController *n = [[[UINavigationController alloc] initWithRootViewController:v] autorelease]; n.navigationBar.barStyle = UIBarStyleBlack;
    [top presentModalViewController:n animated:YES];
}
+ (void)show {
    if (![self current]) return;
    if (gScreen) { [gScreen refresh]; return; }
    CTTimerViewController *v = [[[CTTimerViewController alloc] init] autorelease]; gScreen = v; [self present:v];
}
+ (void)showManual:(NSString *)title { [self present:[[[CTTimerViewController alloc] initManual:title] autorelease]]; }
+ (void)resume {
    [self prune]; [self tick];
    NSDictionary *r = [self nextRing]; if (!r) return;
    if (gScreen) { [gScreen refresh]; return; }
    if (at(r) - now() < 90 * 60) [self show];   // on the way: open straight to the countdown
}
+ (void)rang:(BOOL)withSound { [self show]; [gScreen ring:withSound]; }

#pragma mark Tick, badge, 511
+ (void)tick {
    if (![self current]) { [gTick invalidate]; [gTick release]; gTick = nil; }
    else if (!gTick) gTick = [[NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(tick) userInfo:nil repeats:YES] retain];
    NSDictionary *r = [self nextRing]; NSString *badge = nil;
    if (r) { long m = (long)ceil((at(r) - now()) / 60); badge = m <= 0 ? @"now" : m < 100 ? [NSString stringWithFormat:@"%ldm", m] : @"1h+"; }
    for (UIViewController *vc in [(UITabBarController *)gHost viewControllers])
        if ([vc isKindOfClass:[UINavigationController class]] && [[[(UINavigationController *)vc viewControllers] objectAtIndex:0] isKindOfClass:NSClassFromString(@"CTTripViewController")]) vc.tabBarItem.badgeValue = badge;
    if (r && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) [self refreshLive];
    [[NSNotificationCenter defaultCenter] postNotificationName:CTTimerChanged object:nil];
}
+ (NSString *)liveText { return gLiveText ?: @"scheduled"; }
+ (void)refreshLive {   // 511 allows 60 requests an hour and the board shares them: one stop (the next ring's) every two minutes at most
    if (![[CTData token] length] || gLiveBusy || now() - gLiveAt < 110) return;
    NSMutableArray *codes = [NSMutableArray array];
    for (NSDictionary *r in [self rings]) { NSString *c = [r objectForKey:@"code"]; if ([c length] && at(r) > now() && at(r) - now() < 3 * 3600 && ![codes containsObject:c]) [codes addObject:c]; }
    if (![codes count]) return;
    gLiveBusy = YES; gLiveAt = now();
    [self performSelectorInBackground:@selector(liveWork:) withObject:[codes subarrayWithRange:NSMakeRange(0, 1)]];
}
+ (void)liveWork:(NSArray *)codes {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSMutableDictionary *out = [NSMutableDictionary dictionary]; NSString *err = nil;
    for (NSString *c in codes) { NSDictionary *r = [CTLive predictionsForStopCode:c error:&err]; if (r) [out setObject:r forKey:c]; }
    [self performSelectorOnMainThread:@selector(liveDone:) withObject:[NSArray arrayWithObjects:out, err ?: @"", nil] waitUntilDone:NO];
    [p release];
}
+ (void)liveDone:(NSArray *)res {
    gLiveBusy = NO; NSDictionary *preds = [res objectAtIndex:0]; NSString *err = [res objectAtIndex:1];
    NSArray *rings = [self rings]; if (![rings count]) return;
    NSMutableArray *out = [NSMutableArray array]; BOOL changed = NO, heard = NO; NSInteger late = 0; NSTimeInterval mid = [CTData midnightPlus:0];
    for (NSDictionary *r in rings) {
        NSDictionary *lv = [[preds objectForKey:[r objectForKey:@"code"]] objectForKey:[r objectForKey:@"train"]];
        if (!lv) { [out addObject:r]; continue; }
        NSTimeInterval expected = mid + [[lv objectForKey:@"expected"] integerValue] * 60, base = [[r objectForKey:@"base"] doubleValue];
        if (fabs(expected - base) > 90 * 60) { [out addObject:r]; continue; }   // a different day's run of the same train number
        NSMutableDictionary *m = [[r mutableCopy] autorelease];
        [m setObject:[NSNumber numberWithDouble:expected - [[r objectForKey:@"lead"] doubleValue]] forKey:@"at"];
        [m setObject:[NSNumber numberWithInteger:(NSInteger)floor((expected - base) / 60 + 0.5)] forKey:@"late"];
        if (fabs(at(m) - at(r)) >= 1) changed = YES;
        if (!heard) { heard = YES; late = [[m objectForKey:@"late"] integerValue]; }
        [out addObject:m];
    }
    [gLiveText release];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"h:mm"];
    gLiveText = [(heard ? [NSString stringWithFormat:@"live %@: %@", [f stringFromDate:[NSDate date]], late >= 2 ? [NSString stringWithFormat:@"%ld min late", (long)late] : late <= -2 ? [NSString stringWithFormat:@"%ld min early", (long)-late] : @"on time"]
        : [err length] && ![preds count] ? @"511 didn't answer" : @"511 not tracking it yet") copy];
    if (changed) [self save:[[self current] objectForKey:@"title"] rings:out];
    else [[NSNotificationCenter defaultCenter] postNotificationName:CTTimerChanged object:nil];
    [gScreen refresh];
}

#pragma mark Sound
+ (void)playSound {
    if (!gSound) { NSURL *u = [[NSBundle mainBundle] URLForResource:@"ring" withExtension:@"caf"]; if (u) AudioServicesCreateSystemSoundID((CFURLRef)u, &gSound); }
    AudioServicesPlayAlertSound(gSound ? gSound : kSystemSoundID_Vibrate);
}
+ (void)soundTick { if (now() > gSoundUntil) [self stopSound]; else [self playSound]; }
+ (void)startSound {
    [self stopSound]; gSoundUntil = now() + 45; [self playSound];
    gSoundTimer = [[NSTimer scheduledTimerWithTimeInterval:3.4 target:self selector:@selector(soundTick) userInfo:nil repeats:YES] retain];
}
+ (void)stopSound { [gSoundTimer invalidate]; [gSoundTimer release]; gSoundTimer = nil; }

#pragma mark Offer
+ (void)offerSegs:(NSArray *)segs title:(NSString *)title {
    if (![segs count]) return;
    [gOfferSegs release]; gOfferSegs = [segs retain]; [gOfferTitle release]; gOfferTitle = [title copy];
    NSString *dest = [[segs lastObject] objectForKey:@"to"];
    gOfferLeave = [CTRoute leaveRingFor:[segs objectAtIndex:0]] != nil;
    UIActionSheet *s = [[[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"%@\nRings %ld min before you get there%@.", title, (long)[CTData leadMinutes], [self current] ? @", replacing the timer that's running" : @""] delegate:gHelper cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil] autorelease];
    [s addButtonWithTitle:[segs count] > 1 ? [NSString stringWithFormat:@"Ring before changes and %@", dest] : [NSString stringWithFormat:@"Ring before %@", dest]];
    if (gOfferLeave) [s addButtonWithTitle:[NSString stringWithFormat:@"Same, plus when to leave (%ld min walk)", (long)[CTData walkMinutes]]];
    s.cancelButtonIndex = [s addButtonWithTitle:@"Cancel"];
    UIViewController *top = gHost; while (top.modalViewController) top = top.modalViewController;
    [s showInView:top.view];
}
- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (i == s.cancelButtonIndex || !gOfferSegs) return;
    [CTTimer startTitle:gOfferTitle rings:[CTRoute ringsFor:gOfferSegs leave:gOfferLeave && i == 1] show:YES];
}
@end

#pragma mark - Egg
// Geometry, in the view's points: an egg 168 wide and 232 tall, narrower at the top, standing on its shadow.
#define EGG_CX 100.0
#define EGG_CY 124.0
#define EGG_RX 84.0
#define EGG_RY 116.0
#define SEAM_Y 128.0      // where the twisting top meets the base
#define SEAM_TILT 11.0    // the seam is a circle seen a little from above
#define DEG_PER_MIN 5.0   // 0 to 60 covers 300 degrees, like the real thing, with a gap between 60 and 0
static CGPoint eggPoint(double t) { double f = 1 - 0.12 * cos(t); return CGPointMake(EGG_CX + EGG_RX * sin(t) * f, EGG_CY - EGG_RY * cos(t)); }
static CGMutablePathRef eggPath(void) {
    CGMutablePathRef p = CGPathCreateMutable(); CGPoint q = eggPoint(0); CGPathMoveToPoint(p, NULL, q.x, q.y);
    for (int i = 1; i < 160; i++) { q = eggPoint(2 * M_PI * i / 160); CGPathAddLineToPoint(p, NULL, q.x, q.y); }
    CGPathCloseSubpath(p); return p;
}
static double seamHalfWidth(void) { double t = acos((EGG_CY - SEAM_Y) / EGG_RY); return EGG_RX * sin(t) * (1 - 0.12 * cos(t)); }
static void radial(CGContextRef c, CGPoint p0, CGFloat r0, CGPoint p1, CGFloat r1, const CGFloat *comps, const CGFloat *locs, size_t n) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB(); CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, n);
    CGContextDrawRadialGradient(c, g, p0, r0, p1, r1, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
}

@implementation CTEggView
@synthesize minutes, ringing, settable;
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor]; self.opaque = NO;
        self.layer.anchorPoint = CGPointMake(0.5, (EGG_CY + EGG_RY) / f.size.height); self.frame = f;   // it rocks on its base
    }
    return self;
}
- (void)dealloc { [anim invalidate]; [body release]; [super dealloc]; }
- (void)setTarget:(id)t action:(SEL)a { target = t; action = a; }
- (void)setMinutes:(double)m { minutes = MAX(0, m); if (!anim) { shown = minutes; [self setNeedsDisplay]; } }
- (void)setRinging:(BOOL)r {
    ringing = r; [self.layer removeAnimationForKey:@"rock"];
    if (!r) return;
    [self windTo:0];
    CAKeyframeAnimation *rock = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];   // the bell shakes the egg on its base
    rock.values = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:-0.09], [NSNumber numberWithDouble:0.09], [NSNumber numberWithDouble:-0.07], [NSNumber numberWithDouble:0.07], [NSNumber numberWithDouble:0], nil];
    rock.duration = 0.32; rock.repeatCount = 120; [self.layer addAnimation:rock forKey:@"rock"];
}
- (void)windTo:(double)m {   // a quick twist with a little overshoot, like turning the top by hand
    minutes = MAX(0, m); [anim invalidate];
    double from = shown; NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    NSMutableDictionary *st = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:from], @"from", [NSNumber numberWithDouble:start], @"start", nil];
    anim = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30 target:self selector:@selector(step:) userInfo:st repeats:YES];
}
- (void)step:(NSTimer *)t {
    double from = [[t.userInfo objectForKey:@"from"] doubleValue], dur = 0.35 + MIN(0.6, fabs(minutes - from) / 60 * 0.9);
    double p = MIN(1, ([NSDate timeIntervalSinceReferenceDate] - [[t.userInfo objectForKey:@"start"] doubleValue]) / dur);
    double e = 1 + 2.2 * pow(p - 1, 3) + 1.2 * pow(p - 1, 2);   // ease out with a small overshoot
    shown = from + (minutes - from) * e; [self setNeedsDisplay];
    if (p >= 1) { shown = minutes; [anim invalidate]; anim = nil; [self setNeedsDisplay]; }
}
- (void)hop {
    CAKeyframeAnimation *h = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    h.values = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:-16], [NSNumber numberWithDouble:0], [NSNumber numberWithDouble:-5], [NSNumber numberWithDouble:0], nil];
    h.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:0.3], [NSNumber numberWithDouble:0.6], [NSNumber numberWithDouble:0.8], [NSNumber numberWithDouble:1], nil];
    h.duration = 0.5; [self.layer addAnimation:h forKey:@"hop"];
}
- (UIImage *)renderBody {   // everything that doesn't turn, drawn once
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext(); CGFloat floorY = EGG_CY + EGG_RY;
    CGContextSaveGState(c); CGContextTranslateCTM(c, EGG_CX, floorY); CGContextScaleCTM(c, 1, 0.16);   // shadow on the floor
    { CGFloat k[] = { 0, 0, 0, 0.75, 0, 0, 0, 0 }, l[] = { 0, 1 }; radial(c, CGPointZero, 0, CGPointZero, EGG_RX * 1.15, k, l, 2); }
    CGContextRestoreGState(c);
    CGMutablePathRef egg = eggPath(); double sw = seamHalfWidth();
    CGAffineTransform squash = CGAffineTransformMake(1, 0, 0, SEAM_TILT / sw, EGG_CX, SEAM_Y);
    CGContextSaveGState(c); CGContextAddPath(c, egg); CGContextClip(c);
    { CGFloat k[] = { 1.0, 0.55, 0.58, 1,  0.93, 0.12, 0.25, 1,  0.78, 0.05, 0.17, 1,  0.40, 0.02, 0.07, 1 }, l[] = { 0, 0.3, 0.68, 1 };   // the top: glossy Caltrain red, lit from the upper left
      radial(c, CGPointMake(EGG_CX - 0.35 * EGG_RX, EGG_CY - 0.5 * EGG_RY), 0, CGPointMake(EGG_CX - 0.05 * EGG_RX, EGG_CY - 0.05 * EGG_RY), EGG_RY * 1.12, k, l, 4); }
    CGMutablePathRef base = CGPathCreateMutable();   // the base: everything below the seam
    CGPathAddArc(base, &squash, 0, 0, sw + 2, M_PI, 0, true); CGPathAddLineToPoint(base, NULL, self.bounds.size.width, SEAM_Y);
    CGPathAddLineToPoint(base, NULL, self.bounds.size.width, self.bounds.size.height); CGPathAddLineToPoint(base, NULL, 0, self.bounds.size.height); CGPathAddLineToPoint(base, NULL, 0, SEAM_Y); CGPathCloseSubpath(base);
    CGContextSaveGState(c); CGContextAddPath(c, base); CGContextClip(c);
    { CGFloat k[] = { 1.0, 0.99, 0.97, 1,  0.97, 0.95, 0.91, 1,  0.86, 0.83, 0.78, 1,  0.58, 0.55, 0.51, 1 }, l[] = { 0, 0.35, 0.75, 1 };   // warm white, same light
      radial(c, CGPointMake(EGG_CX - 0.35 * EGG_RX, EGG_CY - 0.5 * EGG_RY), 0, CGPointMake(EGG_CX - 0.05 * EGG_RX, EGG_CY - 0.05 * EGG_RY), EGG_RY * 1.12, k, l, 4); }
    { CGFloat k[] = { 1, 0.97, 0.92, 0.35,  1, 0.97, 0.92, 0 }, l[] = { 0, 1 };   // light bouncing up off the floor
      radial(c, CGPointMake(EGG_CX + 10, floorY + 20), 0, CGPointMake(EGG_CX + 10, floorY + 20), 70, k, l, 2); }
    UIImage *logo = [UIImage imageNamed:@"logo-caltrain.png"];   // printed on the front of the base
    if (logo) { CGFloat lw = 78, lh = lw * logo.size.height / logo.size.width; [logo drawInRect:CGRectMake(EGG_CX - lw / 2, SEAM_Y + SEAM_TILT + 34, lw, lh) blendMode:kCGBlendModeNormal alpha:0.95]; }
    CGContextRestoreGState(c); CGPathRelease(base);
    CGMutablePathRef seam = CGPathCreateMutable(); CGPathAddArc(seam, &squash, 0, 0, sw + 2, 0, M_PI, 0);
    CGContextSetLineCap(c, kCGLineCapButt);
    CGContextAddPath(c, seam); CGContextSetRGBStrokeColor(c, 0.2, 0.02, 0.05, 0.3); CGContextSetLineWidth(c, 6); CGContextStrokePath(c);   // the top's shadow on the base
    CGContextAddPath(c, seam); CGContextSetRGBStrokeColor(c, 0.25, 0.04, 0.08, 0.9); CGContextSetLineWidth(c, 1.5); CGContextStrokePath(c);   // the groove
    CGContextSaveGState(c); CGContextTranslateCTM(c, 0, 1.6); CGContextAddPath(c, seam); CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.6); CGContextSetLineWidth(c, 1); CGContextStrokePath(c); CGContextRestoreGState(c);
    CGPathRelease(seam);
    CGContextRestoreGState(c);
    CGContextSaveGState(c); CGContextTranslateCTM(c, EGG_CX - 0.42 * EGG_RX, EGG_CY - 0.58 * EGG_RY); CGContextRotateCTM(c, -0.5); CGContextScaleCTM(c, 1, 1.6);   // the shine on the lacquer
    { CGFloat k[] = { 1, 1, 1, 0.95,  1, 1, 1, 0 }, l[] = { 0, 1 }; radial(c, CGPointZero, 0, CGPointZero, 18, k, l, 2); }
    CGContextRestoreGState(c);
    CGContextAddPath(c, egg); CGContextSetRGBStrokeColor(c, 0.3, 0.05, 0.08, 0.35); CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
    CGPathRelease(egg);
    CGFloat py = SEAM_Y + SEAM_TILT + 5;   // the pointer on the base, in Caltrain red
    CGContextMoveToPoint(c, EGG_CX, py); CGContextAddLineToPoint(c, EGG_CX - 8, py + 13); CGContextAddLineToPoint(c, EGG_CX + 8, py + 13); CGContextClosePath(c);
    CGContextSetRGBFillColor(c, 0.89, 0.09, 0.22, 1); CGContextFillPath(c);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
- (void)drawRect:(CGRect)rect {
    if (!body) body = [[self renderBody] retain];
    [body drawAtPoint:CGPointZero];
    CGContextRef c = UIGraphicsGetCurrentContext(); double sw = seamHalfWidth(), m = MIN(60, MAX(0, shown));
    CGContextSaveGState(c); CGMutablePathRef egg = eggPath(); CGContextAddPath(c, egg); CGContextClip(c); CGPathRelease(egg);
    UIFont *nf = [UIFont boldSystemFontOfSize:13];
    for (int v = 0; v <= 60; v++) {   // the printed scale round the top, turned so that m sits over the pointer
        double th = (v - m) * DEG_PER_MIN * M_PI / 180, cs = cos(th); if (cs < 0.1) continue;
        CGFloat x = EGG_CX + sw * sin(th), y = SEAM_Y + SEAM_TILT * cs - 3; BOOL five = v % 5 == 0;
        UIColor *col = v == 0 ? [UIColor colorWithWhite:0.07 alpha:0.35 + 0.65 * cs] : [UIColor colorWithRed:0.97 green:0.96 blue:0.95 alpha:0.25 + 0.75 * cs];   // printed white on the red, 0 in black
        [col setStroke]; CGContextSetLineWidth(c, (five ? 2.0 : 1.0) * (0.5 + 0.5 * cs));
        CGContextMoveToPoint(c, x, y); CGContextAddLineToPoint(c, x, y - (five ? 11 : 6)); CGContextStrokePath(c);
        if (five) {
            CGContextSaveGState(c); CGContextTranslateCTM(c, x, y - 22); CGContextScaleCTM(c, cs, 1);   // printed on a curve: squeezed toward the sides
            [col setFill]; [[NSString stringWithFormat:@"%d", v] drawInRect:CGRectMake(-16, -8, 32, 16) withFont:nf lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentCenter];
            CGContextRestoreGState(c);
        }
    }
    CGContextRestoreGState(c);
}
- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { touchStart = [[t anyObject] locationInView:self]; dragFrom = shown; moved = NO; }
- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    CGFloat dx = [[t anyObject] locationInView:self].x - touchStart.x; if (fabs(dx) > 4) moved = YES;
    if (!settable || !moved) return;
    [anim invalidate]; anim = nil;   // twisting by hand: the scale follows the finger, about 7 points a minute
    shown = MIN(60, MAX(1, dragFrom - dx / (seamHalfWidth() * DEG_PER_MIN * M_PI / 180))); minutes = shown; [self setNeedsDisplay];
    [target performSelector:action withObject:self];
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    if (!moved) { [self hop]; return; }
    if (settable) { [self windTo:MIN(60, MAX(1, round(shown)))]; [target performSelector:action withObject:self]; }
}
@end

#pragma mark - Screen
static UIImage *spotlight(CGSize sz) {   // the egg stands in a pool of light; black at the edges to meet the nav bar
    UIGraphicsBeginImageContextWithOptions(sz, YES, 0); CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(c, 0, 0, 0, 1); CGContextFillRect(c, CGRectMake(0, 0, sz.width, sz.height));
    CGFloat k[] = { 0.24, 0.22, 0.20, 1,  0.10, 0.09, 0.085, 1,  0, 0, 0, 1 }, l[] = { 0, 0.55, 1 };
    radial(c, CGPointMake(sz.width / 2, 150), 0, CGPointMake(sz.width / 2, 170), 250, k, l, 3);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return img;
}
static BOOL tickingOn(void) { id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"ct_tick"]; return v ? [v boolValue] : YES; }
static void playTick(void) {
    static SystemSoundID tickSound = 0;
    if (!tickSound) { NSURL *u = [[NSBundle mainBundle] URLForResource:@"tick" withExtension:@"caf"]; if (u) AudioServicesCreateSystemSoundID((CFURLRef)u, &tickSound); }
    if (tickSound) AudioServicesPlaySystemSound(tickSound);
}

@implementation CTTimerViewController
- (id)init { if ((self = [super init])) { self.title = @"Timer"; lastLeft = -1; } return self; }
- (id)initManual:(NSString *)t { if ((self = [self init])) { manual = YES; manualTitle = [t copy]; } return self; }
- (void)dealloc { if (gScreen == self) gScreen = nil; [tick invalidate]; [manualTitle release]; [egg release]; [caption release]; [big release]; [what release]; [when release]; [later release]; [super dealloc]; }
- (UILabel *)label:(CGRect)f font:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] initWithFrame:f]; l.backgroundColor = [UIColor clearColor]; l.font = font; l.textColor = color; l.textAlignment = UITextAlignmentCenter;
    l.adjustsFontSizeToFitWidth = YES; l.minimumFontSize = 11; l.autoresizingMask = UIViewAutoresizingFlexibleWidth; [self.view addSubview:l]; return l;
}
- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 416)] autorelease]; self.view.backgroundColor = [UIColor blackColor];
    UIImageView *bg = [[[UIImageView alloc] initWithImage:spotlight(CGSizeMake(320, 416))] autorelease]; bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [self.view addSubview:bg];
    egg = [[CTEggView alloc] initWithFrame:CGRectMake(60, 2, 200, 260)]; egg.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin; [egg setTarget:self action:@selector(twisted:)]; [self.view addSubview:egg];
    big = [self label:CGRectMake(10, 262, 300, 50) font:boardFont(46) color:amber(1)]; big.minimumFontSize = 18;
    what = [self label:CGRectMake(10, 312, 300, 24) font:[UIFont boldSystemFontOfSize:18] color:[UIColor whiteColor]];
    when = [self label:CGRectMake(10, 336, 300, 20) font:[UIFont systemFontOfSize:13] color:[UIColor colorWithWhite:0.6 alpha:1]];
    later = [self label:CGRectMake(10, 358, 300, 48) font:[UIFont systemFontOfSize:13] color:[UIColor colorWithWhite:0.45 alpha:1]]; later.numberOfLines = 3; later.adjustsFontSizeToFitWidth = NO;
    button = [UIButton buttonWithType:UIButtonTypeCustom]; button.frame = CGRectMake(50, 360, 220, 48); button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    button.backgroundColor = [UIColor colorWithRed:0.80 green:0.10 blue:0.18 alpha:1]; button.layer.cornerRadius = 24; button.layer.borderWidth = 1; button.layer.borderColor = [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1].CGColor;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:21]; [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:button];
    caption = [self label:CGRectMake(8, 6, 108, 30) font:[UIFont systemFontOfSize:11] color:[UIColor colorWithWhite:0.5 alpha:1]]; caption.textAlignment = UITextAlignmentLeft; caption.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    caption.numberOfLines = 2; caption.adjustsFontSizeToFitWidth = NO; caption.lineBreakMode = UILineBreakModeTailTruncation;   // which train, small; the nav bar is too narrow for it
    ticking = [UIButton buttonWithType:UIButtonTypeCustom]; ticking.frame = CGRectMake(228, 2, 88, 26); ticking.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    ticking.titleLabel.font = [UIFont systemFontOfSize:12]; [ticking setTitleColor:[UIColor colorWithWhite:0.5 alpha:1] forState:UIControlStateNormal]; ticking.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [ticking addTarget:self action:@selector(toggleTicking) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:ticking];
    if (manual) egg.settable = YES;
    [self layout];
}
- (void)layout {   // which controls show depends on the state: setting the egg, counting down, or ringing
    BOOL showButton = manual || ringing;
    button.hidden = !showButton; when.hidden = ringing; later.hidden = showButton; ticking.hidden = manual || ringing;
    [button setTitle:manual ? @"Start" : @"Stop" forState:UIControlStateNormal];
    [ticking setTitle:tickingOn() ? @"ticking on" : @"ticking off" forState:UIControlStateNormal];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:manual ? @"Cancel" : @"Hide" style:UIBarButtonItemStyleBordered target:self action:@selector(close)] autorelease];
    self.navigationItem.rightBarButtonItem = manual || ringing ? nil : [[[UIBarButtonItem alloc] initWithTitle:@"End timer" style:UIBarButtonItemStyleBordered target:self action:@selector(endTimer)] autorelease];
}
- (void)toggleTicking { [[NSUserDefaults standardUserDefaults] setBool:!tickingOn() forKey:@"ct_tick"]; [[NSUserDefaults standardUserDefaults] synchronize]; [self layout]; }
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a]; [self refresh];
    [tick invalidate]; tick = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(second) userInfo:nil repeats:YES];
}
- (void)viewDidAppear:(BOOL)a {   // wind it up: the top turns from 0 to the time left
    [super viewDidAppear:a];
    if (ringing) return;
    double m = manual ? 10 : MIN(60, MAX(0, (at([CTTimer nextRing]) - now()) / 60));
    egg.minutes = 0; [egg windTo:m];
}
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [tick invalidate]; tick = nil; }
- (void)second {
    [self refresh];
    if (!manual && !ringing && tickingOn() && [CTTimer nextRing] && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) playTick();
}
- (void)twisted:(CTEggView *)e { [self refresh]; }
- (void)refresh {
    if (![self isViewLoaded]) return;
    if (manual) { long m = lround(egg.minutes); big.text = [NSString stringWithFormat:@"%ld MIN", MAX(1, m)]; what.text = manualTitle; when.text = @"Twist the egg to how long you ride."; return; }
    NSDictionary *r = [CTTimer nextRing]; NSArray *rings = [[CTTimer current] objectForKey:@"rings"];
    if (!r) { [self close]; return; }
    caption.text = [[CTTimer current] objectForKey:@"title"];
    NSTimeInterval left = at(r) - now(); BOOL crossed = lastLeft > 0; lastLeft = left;
    // ring aloud only if it ran out while you watched; opened from the notification, the bell has already played
    if (left <= 0 && !ringing) { [self ring:crossed && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive]; return; }
    if (ringing) return;
    egg.minutes = MIN(60, left / 60); big.text = countdown(left); what.text = [r objectForKey:@"say"];
    when.text = [NSString stringWithFormat:@"Rings at %@ · %@", [CTData fmtTime:at(r)], [r objectForKey:@"code"] ? [CTTimer liveText] : @"scheduled"];
    NSMutableArray *next = [NSMutableArray array];
    for (NSUInteger i = 1; i < [rings count] && i < 3; i++) [next addObject:[NSString stringWithFormat:@"then %@  %@", [CTData fmtTime:at([rings objectAtIndex:i])], [[rings objectAtIndex:i] objectForKey:@"say"]]];
    later.text = [next count] ? [next componentsJoinedByString:@"\n"] : [[r objectForKey:@"kind"] isEqualToString:@"manual"] ? @"" : [r objectForKey:@"sub"];   // a dialed timer's line is already in the caption
}
- (void)ring:(BOOL)withSound {
    [self view];   // a screen presented just now has not loaded yet
    if (manual || ringing) return;
    NSDictionary *r = [CTTimer nextRing]; if (!r || at(r) > now() + 5) return;
    ringing = YES; [self layout];
    egg.ringing = YES; big.text = [[r objectForKey:@"say"] uppercaseString]; what.text = [r objectForKey:@"sub"];
    if (withSound) [CTTimer startSound];
}
- (void)pressed {
    if (manual) {   // this screen becomes the running timer
        double m = MAX(1, lround(egg.minutes));
        manual = NO; egg.settable = NO; gScreen = self; ringing = NO; lastLeft = -1;
        NSDictionary *r = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:now() + m * 60], @"at", @"Your stop is coming up", @"say", manualTitle ?: @"", @"sub", @"manual", @"kind", nil];
        [CTTimer startTitle:manualTitle ?: @"Timer" rings:[NSArray arrayWithObject:r] show:NO];
        [self layout]; [self refresh]; return;
    }
    ringing = NO; egg.ringing = NO; [self layout];
    [CTTimer stopRing];
    NSDictionary *r = [CTTimer nextRing]; if (r) { lastLeft = -1; [egg windTo:MIN(60, MAX(0, (at(r) - now()) / 60))]; }   // wound up again for the next ring
}
- (void)endTimer { [CTTimer cancel]; }
- (void)close {
    [CTTimer stopSound]; [tick invalidate]; tick = nil;
    if (gScreen == self) gScreen = nil;
    [self dismissModalViewControllerAnimated:YES];
}
- (BOOL)isRinging { return ringing; }
@end
