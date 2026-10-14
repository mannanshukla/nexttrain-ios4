#import "CTMap.h"
#import "CTData.h"
#import "CTAgencies.h"
#import "CTControllers.h"
#import "CTAgencyControllers.h"
#import "ORJSON.h"

#define KY 1.262   // 1 / cos(37.6 deg): degrees of latitude are longer than degrees of longitude here

@interface CTTiledLayer : CATiledLayer @end
@implementation CTTiledLayer
+ (CFTimeInterval)fadeDuration { return 0; }
@end

// --- bundled geometry, parsed once into C arrays
typedef struct { CGPoint *pts; int n; CGRect box; } CTPoly;
static CTPoly *gWater = NULL, *gLand = NULL; static int gWaterN = 0, gLandN = 0;
static CTPoly *gTrack = NULL; static int gTrackN = 0;
static CTPoly *gBartLines = NULL; static int gBartN = 0; static NSArray *gBartColors = nil;
static NSArray *gMetroLines = nil, *gMetroStops = nil; static CTPoly *gMetroShapes = NULL;

static id loadJSON(NSString *name) { NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"json"]; return [ORJSON parse:[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil]]; }
static CTPoly polyFrom(NSArray *pairs) {   // [[lon, lat], ...] -> poly in lon/lat
    CTPoly p; p.n = (int)[pairs count]; p.pts = (CGPoint *)malloc(sizeof(CGPoint) * MAX(1, p.n));
    double x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (int i = 0; i < p.n; i++) { NSArray *q = [pairs objectAtIndex:i]; double x = [[q objectAtIndex:0] doubleValue], y = [[q objectAtIndex:1] doubleValue]; p.pts[i] = CGPointMake(x, y); if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    p.box = CGRectMake(x0, y0, x1 - x0, y1 - y0); return p;
}
static CTPoly *polys(NSArray *list, int *n) { *n = (int)[list count]; CTPoly *out = (CTPoly *)malloc(sizeof(CTPoly) * MAX(1, *n)); for (int i = 0; i < *n; i++) out[i] = polyFrom([list objectAtIndex:i]); return out; }
static void loadGeo(void) {
    static BOOL done = NO; if (done) return; done = YES;
    NSDictionary *bay = loadJSON(@"bay"); gWater = polys([bay objectForKey:@"water"], &gWaterN); gLand = polys([bay objectForKey:@"land"], &gLandN);
    NSDictionary *tr = loadJSON(@"track"); gTrack = polys([NSArray arrayWithObjects:[tr objectForKey:@"main"], [tr objectForKey:@"south"], nil], &gTrackN);
    NSArray *bl = [loadJSON(@"bart_map") objectForKey:@"lines"]; NSMutableArray *shapes = [NSMutableArray array], *cols = [NSMutableArray array];
    for (NSDictionary *l in bl) { [shapes addObject:[l objectForKey:@"pts"]]; [cols addObject:[l objectForKey:@"color"]]; }
    gBartLines = polys(shapes, &gBartN); gBartColors = [cols retain];
    gMetroLines = [[loadJSON(@"muni_metro") objectForKey:@"lines"] retain];
    NSMutableArray *ms = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set]; NSMutableArray *mshapes = [NSMutableArray array];
    for (NSDictionary *l in gMetroLines) {
        [mshapes addObject:[l objectForKey:@"shape"]];
        NSArray *dirs = [l objectForKey:@"dirs"]; if (![dirs count]) continue;
        NSArray *stops = [[dirs objectAtIndex:0] objectForKey:@"stops"];
        for (NSUInteger k = 0; k < [stops count]; k++) { NSDictionary *s = [stops objectAtIndex:k];
            NSString *code = [s objectForKey:@"code"]; if ([seen containsObject:code]) continue; [seen addObject:code];
            NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:s]; [d setObject:[l objectForKey:@"id"] forKey:@"line"]; [d setObject:[l objectForKey:@"color"] forKey:@"color"];
            static NSSet *hubs = nil; if (!hubs) hubs = [[NSSet alloc] initWithObjects:@"Embarcadero Station", @"Civic Center Station", @"Castro Station", @"West Portal Station", @"Balboa Park BART", nil];
            BOOL terminus = k == 0 || k == [stops count] - 1 || [hubs containsObject:[s objectForKey:@"name"]];
            [d setObject:[NSNumber numberWithBool:terminus] forKey:@"major"]; [ms addObject:d];
        }
    }
    gMetroStops = [ms retain]; int n; gMetroShapes = polys(mshapes, &n);
}

@implementation CTMapView
@synthesize displayZoom;
+ (Class)layerClass { return [CTTiledLayer class]; }
+ (NSArray *)metroStops { loadGeo(); return gMetroStops; }
+ (NSArray *)metroLines { loadGeo(); return gMetroLines; }
+ (UIColor *)colorForHex:(NSString *)hex { unsigned v = 0; [[NSScanner scannerWithString:hex] scanHexInt:&v]; return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1]; }
- (id)initWithMode:(CTMapMode)m width:(CGFloat)w {
    loadGeo(); mode = m;
    if (m == CTMapCaltrain) { W = -122.56; E = -121.52; S = 36.97; N = 37.84; }
    else if (m == CTMapBart) { W = -122.56; E = -121.66; S = 37.44; N = 38.06; }
    else { W = -122.525; E = -122.365; S = 37.700; N = 37.815; }
    ppd = w / (E - W); displayZoom = 1;
    if ((self = [super initWithFrame:CGRectMake(0, 0, w, (N - S) * ppd * KY)])) {
        self.backgroundColor = [UIColor colorWithRed:0.93 green:0.91 blue:0.87 alpha:1]; self.opaque = YES;
        CATiledLayer *tl = (CATiledLayer *)self.layer; tl.levelsOfDetail = 1; tl.levelsOfDetailBias = 3;
        CGFloat sc = [UIScreen mainScreen].scale; tl.tileSize = CGSizeMake(256 * sc, 256 * sc);
        [self stations];   // parse station data here, on the main thread, before tile threads start drawing
    }
    return self;
}
- (void)dealloc { [onPick release]; [super dealloc]; }
- (void)setOnPick:(void (^)(NSInteger))b { [onPick release]; onPick = [b copy]; }
- (CGPoint)pointForLon:(double)lon lat:(double)lat { return CGPointMake((lon - W) * ppd, (N - lat) * ppd * KY); }
- (CGRect)viewRectForBox:(CGRect)b { CGPoint a = [self pointForLon:b.origin.x lat:b.origin.y + b.size.height], c = [self pointForLon:b.origin.x + b.size.width lat:b.origin.y]; return CGRectMake(a.x, a.y, c.x - a.x, c.y - a.y); }
- (void)addPoly:(CTPoly)p to:(CGContextRef)ctx { for (int i = 0; i < p.n; i++) { CGPoint q = [self pointForLon:p.pts[i].x lat:p.pts[i].y]; if (i) CGContextAddLineToPoint(ctx, q.x, q.y); else CGContextMoveToPoint(ctx, q.x, q.y); } }

// station list for the current mode: array of {name, lat, lon, major}
- (NSArray *)stations {
    static NSArray *ct = nil, *bart = nil;
    if (mode == CTMapCaltrain) {
        if (!ct) { NSMutableArray *a = [NSMutableArray array]; NSSet *major = [NSSet setWithObjects:@"san_francisco", @"millbrae", @"redwood_city", @"palo_alto", @"mountain_view", @"san_jose_diridon", @"gilroy", nil];
            for (NSDictionary *s in [CTData stations]) [a addObject:[NSDictionary dictionaryWithObjectsAndKeys:[s objectForKey:@"name"], @"name", [s objectForKey:@"lat"], @"lat", [s objectForKey:@"lon"], @"lon", [NSNumber numberWithBool:[major containsObject:[s objectForKey:@"id"]]], @"major", nil]];
            ct = [a retain]; }
        return ct;
    }
    if (mode == CTMapBart) {
        if (!bart) { NSMutableArray *a = [NSMutableArray array]; NSSet *major = [NSSet setWithObjects:@"RICH", @"ANTC", @"DUBL", @"BERY", @"SFIA", @"MLBR", @"DALY", @"EMBR", @"19TH", @"COLS", @"BAYF", @"MCAR", @"BALB", @"OAKL", nil];
            for (NSDictionary *s in [CTBart stations]) { NSString *name = [s objectForKey:@"name"]; NSRange r = [name rangeOfString:@"/"]; if (r.location != NSNotFound && r.location > 4) name = [name substringToIndex:r.location];
                [a addObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", [s objectForKey:@"lat"], @"lat", [s objectForKey:@"lon"], @"lon", [NSNumber numberWithBool:[major containsObject:[s objectForKey:@"abbr"]]], @"major", nil]]; }
            bart = [a retain]; }
        return bart;
    }
    return gMetroStops;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat zoom = CGContextGetCTM(ctx).a / [UIScreen mainScreen].scale; if (zoom <= 0) zoom = 1;   // tiles are rendered at the screen scale, so divide that out
    CGContextSetFillColorWithColor(ctx, self.backgroundColor.CGColor); CGContextFillRect(ctx, rect);
    // water and islands
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    for (int pass = 0; pass < 2; pass++) {
        CTPoly *set = pass ? gLand : gWater; int n = pass ? gLandN : gWaterN;
        for (int i = 0; i < n; i++) {
            if (!CGRectIntersectsRect([self viewRectForBox:set[i].box], rect)) continue;
            CGContextBeginPath(ctx); [self addPoly:set[i] to:ctx]; CGContextClosePath(ctx);
            if (pass) CGContextSetRGBFillColor(ctx, 0.93, 0.91, 0.87, 1); else CGContextSetRGBFillColor(ctx, 0.64, 0.78, 0.90, 1);
            CGContextSetRGBStrokeColor(ctx, 0.42, 0.60, 0.78, 1); CGContextSetLineWidth(ctx, 0.8 / zoom);
            CGContextDrawPath(ctx, kCGPathFillStroke);
        }
    }
    CGContextSetLineCap(ctx, kCGLineCapRound);
    // lines
    if (mode == CTMapCaltrain) {
        for (int i = 0; i < gTrackN; i++) { CGContextBeginPath(ctx); [self addPoly:gTrack[i] to:ctx];
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.9); CGContextSetLineWidth(ctx, 6 / zoom); CGContextStrokePath(ctx);
            CGContextBeginPath(ctx); [self addPoly:gTrack[i] to:ctx]; CGContextSetRGBStrokeColor(ctx, 0.80, 0.06, 0.14, 1); CGContextSetLineWidth(ctx, 3.2 / zoom); CGContextStrokePath(ctx); }
    } else if (mode == CTMapBart) {
        for (int i = 0; i < gBartN; i++) { CGContextBeginPath(ctx); [self addPoly:gBartLines[i] to:ctx];
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.8); CGContextSetLineWidth(ctx, 5 / zoom); CGContextStrokePath(ctx);
            CGContextBeginPath(ctx); [self addPoly:gBartLines[i] to:ctx]; CGContextSetStrokeColorWithColor(ctx, [CTMapView colorForHex:[gBartColors objectAtIndex:i]].CGColor); CGContextSetLineWidth(ctx, 2.8 / zoom); CGContextStrokePath(ctx); }
    } else {
        for (NSUInteger i = 0; i < [gMetroLines count]; i++) { CGContextBeginPath(ctx); [self addPoly:gMetroShapes[i] to:ctx];
            CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.8); CGContextSetLineWidth(ctx, 5 / zoom); CGContextStrokePath(ctx);
            CGContextBeginPath(ctx); [self addPoly:gMetroShapes[i] to:ctx]; CGContextSetStrokeColorWithColor(ctx, [CTMapView colorForHex:[[gMetroLines objectAtIndex:i] objectForKey:@"color"]].CGColor); CGContextSetLineWidth(ctx, 2.8 / zoom); CGContextStrokePath(ctx); }
    }
    // stations
    NSArray *st = [self stations]; CGFloat labelZoom = mode == CTMapCaltrain ? 1.5 : mode == CTMapBart ? 2.2 : 2.8;
    UIFont *font = [UIFont boldSystemFontOfSize:9.5 / zoom]; CGFloat r = (mode == CTMapMuni ? 2.6 : 3.4) / zoom;
    for (NSUInteger i = 0; i < [st count]; i++) {
        NSDictionary *s = [st objectAtIndex:i]; CGPoint p = [self pointForLon:[[s objectForKey:@"lon"] doubleValue] lat:[[s objectForKey:@"lat"] doubleValue]];
        BOOL major = [[s objectForKey:@"major"] boolValue]; CGFloat rr = major ? r * 1.35 : r;
        if (!CGRectIntersectsRect(CGRectInset(CGRectMake(p.x, p.y, 0, 0), -170 / zoom, -14 / zoom), rect)) continue;
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 1); CGContextFillEllipseInRect(ctx, CGRectMake(p.x - rr, p.y - rr, 2 * rr, 2 * rr));
        if (mode == CTMapMuni) CGContextSetStrokeColorWithColor(ctx, [CTMapView colorForHex:[s objectForKey:@"color"]].CGColor); else CGContextSetRGBStrokeColor(ctx, 0.15, 0.15, 0.15, 1);
        CGContextSetLineWidth(ctx, (major ? 1.8 : 1.3) / zoom); CGContextStrokeEllipseInRect(ctx, CGRectMake(p.x - rr, p.y - rr, 2 * rr, 2 * rr));
        if (displayZoom >= labelZoom || major) {
            NSString *name = [s objectForKey:@"name"]; CGSize sz = [name sizeWithFont:font];
            CGPoint at = CGPointMake(p.x + rr + 2.5 / zoom, p.y - sz.height / 2);
            if (mode == CTMapCaltrain && i % 2 == 1 && displayZoom >= labelZoom) at.x = p.x - rr - 2.5 / zoom - sz.width;   // alternate sides so the dense peninsula stays legible
            CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.72); CGContextFillRect(ctx, CGRectInset(CGRectMake(at.x, at.y, sz.width, sz.height), -1.5 / zoom, 0));
            [[UIColor colorWithWhite:0.1 alpha:1] set]; [name drawAtPoint:at withFont:font];
        }
    }
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)e {
    UITouch *t = [touches anyObject]; if (t.tapCount != 1) return;
    CGPoint p = [t locationInView:self]; CGFloat zoom = self.transform.a > 0 ? self.transform.a : 1; CGFloat best = 22 / zoom; NSInteger bi = -1;
    NSArray *st = [self stations];
    for (NSUInteger i = 0; i < [st count]; i++) { NSDictionary *s = [st objectAtIndex:i]; CGPoint q = [self pointForLon:[[s objectForKey:@"lon"] doubleValue] lat:[[s objectForKey:@"lat"] doubleValue]]; CGFloat d = hypotf(q.x - p.x, q.y - p.y); if (d < best) { best = d; bi = i; } }
    if (bi >= 0 && onPick) onPick(bi);
}
@end

@implementation CTMapViewController
- (id)init { if ((self = [super initWithNibName:nil bundle:nil])) { self.title = @"Map"; self.tabBarItem.title = @"Map"; mode = (CTMapMode)[[NSUserDefaults standardUserDefaults] integerForKey:@"ct_map_mode"]; } return self; }
- (void)dealloc { [scroll release]; [map release]; [seg release]; [super dealloc]; }
- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]; root.backgroundColor = [UIColor colorWithRed:0.64 green:0.78 blue:0.90 alpha:1];
    scroll = [[UIScrollView alloc] initWithFrame:root.bounds]; scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; scroll.backgroundColor = root.backgroundColor;
    scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5; scroll.bouncesZoom = YES; scroll.showsHorizontalScrollIndicator = NO; scroll.showsVerticalScrollIndicator = NO;
    [root addSubview:scroll];
    UILabel *credit = [[[UILabel alloc] initWithFrame:CGRectMake(0, root.bounds.size.height - 14, root.bounds.size.width, 14)] autorelease]; credit.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    credit.text = @"Pinch to zoom, tap a station  ·  Map data © OpenStreetMap contributors"; credit.font = [UIFont systemFontOfSize:8.5]; credit.textAlignment = UITextAlignmentCenter; credit.textColor = [UIColor colorWithWhite:0.25 alpha:1]; credit.backgroundColor = [UIColor colorWithWhite:1 alpha:0.75];
    [root addSubview:credit]; self.view = root;
    seg = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Caltrain", @"BART", @"Muni", nil]]; seg.segmentedControlStyle = UISegmentedControlStyleBar; seg.selectedSegmentIndex = mode; [seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = seg;
    [self setMode:mode];
}
- (void)segChanged { [self setMode:(CTMapMode)seg.selectedSegmentIndex]; [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ct_map_mode"]; }
- (void)setMode:(CTMapMode)m {
    mode = m; [map removeFromSuperview]; [map release];
    map = [[CTMapView alloc] initWithMode:m width:scroll.bounds.size.width];
    scroll.zoomScale = 1; scroll.contentSize = map.bounds.size; [scroll addSubview:map]; [self scrollViewDidZoom:scroll];
    [map setOnPick:^(NSInteger i) { [self pick:i]; }];
}
- (void)pick:(NSInteger)i {
    UIViewController *v = nil;
    if (mode == CTMapCaltrain) v = [[CTDeparturesViewController alloc] initWithStation:i];
    else if (mode == CTMapBart) v = [[CTBartViewController alloc] initWithStation:[[[CTBart stations] objectAtIndex:i] objectForKey:@"abbr"]];
    else v = [[CTMetroStopViewController alloc] initWithStop:[[CTMapView metroStops] objectAtIndex:i]];
    [self.navigationController pushViewController:v animated:YES]; [v release];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return map; }
- (void)scrollViewDidZoom:(UIScrollView *)sv {   // keep a small map centered
    map.displayZoom = sv.zoomScale;
    CGSize b = sv.bounds.size; CGRect f = map.frame;
    f.origin.x = f.size.width < b.width ? (b.width - f.size.width) / 2 : 0; f.origin.y = f.size.height < b.height ? (b.height - f.size.height) / 2 : 0; map.frame = f;
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self scrollViewDidZoom:scroll]; }
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a]; NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:@"ct_map_zoom"]) { CGFloat z = [d floatForKey:@"ct_map_zoom"]; [d removeObjectForKey:@"ct_map_zoom"]; [d synchronize]; [scroll setZoomScale:z animated:NO]; if ([d objectForKey:@"ct_map_y"]) { [scroll setContentOffset:CGPointMake([d floatForKey:@"ct_map_x"], [d floatForKey:@"ct_map_y"]) animated:NO]; [d removeObjectForKey:@"ct_map_x"]; [d removeObjectForKey:@"ct_map_y"]; [d synchronize]; } }
    if ([d objectForKey:@"ct_test_map_pick"]) { NSInteger i = [d integerForKey:@"ct_test_map_pick"]; [d removeObjectForKey:@"ct_test_map_pick"]; [d synchronize]; [self pick:i]; }
}
@end
