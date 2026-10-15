#import "CTMap.h"
#import "CTData.h"
#import "CTAgencies.h"
#import "CTControllers.h"
#import "CTAgencyControllers.h"
#import "ORJSON.h"

#define KY 1.262   // 1 / cos(37.6 deg): degrees of latitude are longer than degrees of longitude here

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
@synthesize baseSize, style;
+ (NSArray *)metroStops { loadGeo(); return gMetroStops; }
+ (NSArray *)metroLines { loadGeo(); return gMetroLines; }
+ (UIColor *)colorForHex:(NSString *)hex { unsigned v = 0; [[NSScanner scannerWithString:hex] scanHexInt:&v]; return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1]; }
- (id)initWithMode:(CTMapMode)m width:(CGFloat)w {
    loadGeo(); mode = m;
    if (m == CTMapCaltrain) { W = -122.56; E = -121.52; S = 36.97; N = 37.84; }
    else if (m == CTMapBart) { W = -122.56; E = -121.66; S = 37.44; N = 38.06; }
    else { W = -122.525; E = -122.365; S = 37.700; N = 37.815; }
    ppd = w / (E - W); scale = 1; baseSize = CGSizeMake(w, (N - S) * ppd * KY);
    if ((self = [super initWithFrame:CGRectMake(0, 0, baseSize.width, baseSize.height)])) {
        self.backgroundColor = [UIColor colorWithRed:0.949 green:0.937 blue:0.914 alpha:1]; self.opaque = YES;   // #F2EFE9 land, as on the Google tiles iOS 5 Maps drew
        self.contentScaleFactor = [UIScreen mainScreen].scale; self.contentMode = UIViewContentModeRedraw;
        [self stations];   // parse station data up front
    }
    return self;
}
- (CGFloat)scale { return scale; }
- (void)setScale:(CGFloat)s { scale = MAX(1, MIN(3, s)); CGRect f = self.frame; f.size = CGSizeMake(baseSize.width * scale, baseSize.height * scale); self.frame = f; [self setNeedsDisplay]; }
- (void)dealloc { [onPick release]; [satellite release]; [super dealloc]; }
- (void)setStyle:(CTMapStyle)st {
    style = st;
    if (st == CTStyleSatellite && !satellite) satellite = [[UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:mode == CTMapCaltrain ? @"sat-caltrain" : mode == CTMapBart ? @"sat-bart" : @"sat-muni" ofType:@"jpg"]] retain];
    self.backgroundColor = st == CTStyleNight ? [UIColor colorWithWhite:0.13 alpha:1] : [UIColor colorWithRed:0.949 green:0.937 blue:0.914 alpha:1];
    [self setNeedsDisplay];
}
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
    CGFloat zoom = scale;   // geometry is in 1x units; the CTM scales it up, and stroke widths and type are divided back down so they stay constant on screen
    CGContextSetFillColorWithColor(ctx, self.backgroundColor.CGColor); CGContextFillRect(ctx, rect);
    CGContextScaleCTM(ctx, zoom, zoom); rect = CGRectMake(rect.origin.x / zoom, rect.origin.y / zoom, rect.size.width / zoom, rect.size.height / zoom);
    BOOL night = style == CTStyleNight, sat = style == CTStyleSatellite && satellite;
    if (sat) [satellite drawInRect:CGRectMake(0, 0, baseSize.width, baseSize.height)];
    // water and islands
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    for (int pass = 0; pass < 2 && !sat; pass++) {
        CTPoly *set = pass ? gLand : gWater; int n = pass ? gLandN : gWaterN;
        for (int i = 0; i < n; i++) {
            if (!CGRectIntersectsRect([self viewRectForBox:set[i].box], rect)) continue;
            CGContextBeginPath(ctx); [self addPoly:set[i] to:ctx]; CGContextClosePath(ctx);
            if (night) { if (pass) CGContextSetRGBFillColor(ctx, 0.13, 0.13, 0.13, 1); else CGContextSetRGBFillColor(ctx, 0.04, 0.05, 0.08, 1); }
            else { if (pass) CGContextSetRGBFillColor(ctx, 0.949, 0.937, 0.914, 1); else CGContextSetRGBFillColor(ctx, 0.60, 0.70, 0.80, 1); }   // #99B3CC water
            CGContextDrawPath(ctx, kCGPathFill);
        }
    }
    CGContextSetLineCap(ctx, kCGLineCapRound);
    // lines
    if (mode == CTMapCaltrain) {
        for (int i = 0; i < gTrackN; i++) { CGContextBeginPath(ctx); [self addPoly:gTrack[i] to:ctx];
            if (night) CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.8); else CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.9); CGContextSetLineWidth(ctx, 6 / zoom); CGContextStrokePath(ctx);
            CGContextBeginPath(ctx); [self addPoly:gTrack[i] to:ctx]; CGContextSetRGBStrokeColor(ctx, 0.80, 0.06, 0.14, 1); CGContextSetLineWidth(ctx, 3.2 / zoom); CGContextStrokePath(ctx); }
    } else if (mode == CTMapBart) {
        for (int i = 0; i < gBartN; i++) { CGContextBeginPath(ctx); [self addPoly:gBartLines[i] to:ctx];
            if (night) CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.8); else CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.8); CGContextSetLineWidth(ctx, 5 / zoom); CGContextStrokePath(ctx);
            CGContextBeginPath(ctx); [self addPoly:gBartLines[i] to:ctx]; CGContextSetStrokeColorWithColor(ctx, [CTMapView colorForHex:[gBartColors objectAtIndex:i]].CGColor); CGContextSetLineWidth(ctx, 2.8 / zoom); CGContextStrokePath(ctx); }
    } else {
        for (NSUInteger i = 0; i < [gMetroLines count]; i++) { CGContextBeginPath(ctx); [self addPoly:gMetroShapes[i] to:ctx];
            if (night) CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.8); else CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.8); CGContextSetLineWidth(ctx, 5 / zoom); CGContextStrokePath(ctx);
            CGContextBeginPath(ctx); [self addPoly:gMetroShapes[i] to:ctx]; CGContextSetStrokeColorWithColor(ctx, [CTMapView colorForHex:[[gMetroLines objectAtIndex:i] objectForKey:@"color"]].CGColor); CGContextSetLineWidth(ctx, 2.8 / zoom); CGContextStrokePath(ctx); }
    }
    // stations
    NSArray *st = [self stations]; CGFloat labelZoom = mode == CTMapCaltrain ? 1.5 : mode == CTMapBart ? 2.2 : 2.8;
    UIFont *font = [UIFont fontWithName:@"Helvetica-Bold" size:9.5 / zoom] ?: [UIFont boldSystemFontOfSize:9.5 / zoom]; CGFloat r = (mode == CTMapMuni ? 2.6 : 3.4) / zoom;
    CGRect placed[400]; int nPlaced = 0;   // label boxes already drawn, so later ones can step aside
    for (int pass = 0; pass < 2; pass++) for (NSUInteger i = 0; i < [st count]; i++) {   // all the dots, then all the names, so no dot lands on a name
        NSDictionary *s = [st objectAtIndex:i]; CGPoint p = [self pointForLon:[[s objectForKey:@"lon"] doubleValue] lat:[[s objectForKey:@"lat"] doubleValue]];
        BOOL major = [[s objectForKey:@"major"] boolValue]; CGFloat rr = major ? r * 1.35 : r;
        if (!CGRectIntersectsRect(CGRectInset(CGRectMake(p.x, p.y, 0, 0), -170 / zoom, -14 / zoom), rect)) continue;
        if (pass == 0) {
            CGContextSetRGBFillColor(ctx, 1, 1, 1, 1); CGContextFillEllipseInRect(ctx, CGRectMake(p.x - rr, p.y - rr, 2 * rr, 2 * rr));
            if (mode == CTMapMuni) CGContextSetStrokeColorWithColor(ctx, [CTMapView colorForHex:[s objectForKey:@"color"]].CGColor); else CGContextSetRGBStrokeColor(ctx, 0.15, 0.15, 0.15, 1);
            CGContextSetLineWidth(ctx, (major ? 1.8 : 1.3) / zoom); CGContextStrokeEllipseInRect(ctx, CGRectMake(p.x - rr, p.y - rr, 2 * rr, 2 * rr));
            continue;
        }
        if (zoom >= labelZoom || major) {
            NSString *name = [s objectForKey:@"name"]; CGSize sz = [name sizeWithFont:font];
            CGFloat right = p.x + rr + 2.5 / zoom, left = p.x - rr - 2.5 / zoom - sz.width, edge = 2 / zoom;
            BOOL preferLeft = mode == CTMapCaltrain && i % 2 == 1 && zoom >= labelZoom;   // alternate sides so the dense peninsula stays legible
            CGFloat tries[2] = { preferLeft ? left : right, preferLeft ? right : left };
            CGPoint at = CGPointZero; CGRect box = CGRectZero; BOOL ok = NO;
            for (int t = 0; t < 2 && !ok; t++) {   // first side that fits on the map and misses the labels already drawn
                if (tries[t] < edge || tries[t] + sz.width > baseSize.width - edge) continue;
                at = CGPointMake(tries[t], p.y - sz.height / 2); box = CGRectMake(at.x, at.y, sz.width, sz.height); ok = YES;
                for (int k = 0; k < nPlaced && ok; k++) if (CGRectIntersectsRect(placed[k], box)) ok = NO;
            }
            if (!ok) continue;   // a clean map beats a complete one; the label comes back on zoom
            if (nPlaced < 400) placed[nPlaced++] = box;
            CGContextSaveGState(ctx);
            CGContextSetTextDrawingMode(ctx, kCGTextStroke); CGContextSetLineWidth(ctx, 2.6 / zoom); CGContextSetLineJoin(ctx, kCGLineJoinRound);
            BOOL dark = night || sat;
            [(dark ? [UIColor colorWithWhite:0 alpha:0.85] : [UIColor colorWithWhite:1 alpha:0.95]) set]; [name drawAtPoint:at withFont:font];       // halo
            CGContextSetTextDrawingMode(ctx, kCGTextFill);
            [(dark ? [UIColor whiteColor] : [UIColor colorWithRed:0.20 green:0.20 blue:0.22 alpha:1]) set]; [name drawAtPoint:at withFont:font];
            CGContextRestoreGState(ctx);
        }
    }
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)e {
    UITouch *t = [touches anyObject]; if (t.tapCount != 1) return;
    CGPoint p = [t locationInView:self]; CGFloat z = self.transform.a > 0 ? self.transform.a : 1; p.x /= scale; p.y /= scale; CGFloat best = 22 / (scale * z); NSInteger bi = -1;
    NSArray *st = [self stations];
    for (NSUInteger i = 0; i < [st count]; i++) { NSDictionary *s = [st objectAtIndex:i]; CGPoint q = [self pointForLon:[[s objectForKey:@"lon"] doubleValue] lat:[[s objectForKey:@"lat"] doubleValue]]; CGFloat d = hypotf(q.x - p.x, q.y - p.y); if (d < best) { best = d; bi = i; } }
    if (bi >= 0 && onPick) onPick(bi);
}
@end

@implementation CTMapViewController
- (id)init { if ((self = [super initWithNibName:nil bundle:nil])) { self.title = @"Map"; self.tabBarItem.title = @"Map"; mode = (CTMapMode)[[NSUserDefaults standardUserDefaults] integerForKey:@"ct_map_mode"]; style = (CTMapStyle)[[NSUserDefaults standardUserDefaults] integerForKey:@"ct_map_style"];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Style" style:UIBarButtonItemStyleBordered target:self action:@selector(pickStyle)] autorelease]; } return self; }
- (void)pickStyle { UIActionSheet *a = [[UIActionSheet alloc] initWithTitle:@"Map style" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Standard", @"Satellite", @"Night", nil]; [a showFromTabBar:self.tabBarController.tabBar]; [a release]; }
- (void)actionSheet:(UIActionSheet *)a clickedButtonAtIndex:(NSInteger)i { if (i < 0 || i > 2) return; style = (CTMapStyle)i; [[NSUserDefaults standardUserDefaults] setInteger:style forKey:@"ct_map_style"]; [self applyStyle]; }
- (void)applyStyle { map.style = style; scroll.backgroundColor = style == CTStyleNight ? [UIColor colorWithWhite:0.04 alpha:1] : style == CTStyleSatellite ? [UIColor colorWithWhite:0.2 alpha:1] : [UIColor colorWithRed:0.60 green:0.70 blue:0.80 alpha:1]; self.view.backgroundColor = scroll.backgroundColor; credit.text = style != CTStyleSatellite ? @"Pinch to zoom, tap a station  ·  Map data © OpenStreetMap contributors" : mode == CTMapMuni ? @"Pinch to zoom, tap a station  ·  Imagery USGS National Map, lines © OpenStreetMap contributors" : @"Imagery Sentinel-2 cloudless 2016 by EOX, CC BY 4.0  ·  lines © OpenStreetMap contributors"; }
- (void)dealloc { [scroll release]; [map release]; [seg release]; [credit release]; [super dealloc]; }
- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]; root.backgroundColor = [UIColor colorWithRed:0.60 green:0.70 blue:0.80 alpha:1];
    scroll = [[UIScrollView alloc] initWithFrame:root.bounds]; scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; scroll.backgroundColor = root.backgroundColor;
    scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5; scroll.bouncesZoom = YES; scroll.showsHorizontalScrollIndicator = NO; scroll.showsVerticalScrollIndicator = NO;
    [root addSubview:scroll];
    credit = [[UILabel alloc] initWithFrame:CGRectMake(0, root.bounds.size.height - 14, root.bounds.size.width, 14)]; credit.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    credit.text = @"Pinch to zoom, tap a station  ·  Map data © OpenStreetMap contributors"; credit.font = [UIFont systemFontOfSize:8.5]; credit.adjustsFontSizeToFitWidth = YES; credit.minimumFontSize = 7; credit.textAlignment = UITextAlignmentCenter; credit.textColor = [UIColor colorWithWhite:0.25 alpha:1]; credit.backgroundColor = [UIColor colorWithWhite:1 alpha:0.75];
    [root addSubview:credit]; self.view = root;
    credit.adjustsFontSizeToFitWidth = YES; credit.minimumFontSize = 6;
    seg = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Caltrain", @"BART", @"Muni", nil]]; seg.segmentedControlStyle = UISegmentedControlStyleBar; seg.selectedSegmentIndex = mode; [seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = seg;
    [self setMode:mode];
}
- (void)segChanged { [self setMode:(CTMapMode)seg.selectedSegmentIndex]; [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ct_map_mode"]; }
- (void)setMode:(CTMapMode)m {
    mode = m; [map removeFromSuperview]; [map release];
    map = [[CTMapView alloc] initWithMode:m width:scroll.bounds.size.width];
    scroll.zoomScale = 1; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 3; scroll.contentSize = map.bounds.size; [scroll addSubview:map]; [self center];
    [map setOnPick:^(NSInteger i) { [self pick:i]; }]; [self applyStyle];
}
- (void)center {   // keep a small map centered in the scroll view
    CGSize b = scroll.bounds.size; CGRect f = map.frame;
    f.origin.x = f.size.width < b.width ? (b.width - f.size.width) / 2 : 0; f.origin.y = f.size.height < b.height ? (b.height - f.size.height) / 2 : 0; map.frame = f;
}
- (void)applyScale:(CGFloat)s centeredOn:(CGPoint)c {   // c in 1x map units
    [map setScale:s]; scroll.zoomScale = 1; scroll.minimumZoomScale = 1 / map.scale; scroll.maximumZoomScale = 3 / map.scale; scroll.contentSize = map.bounds.size; [self center];
    CGSize b = scroll.bounds.size; CGPoint off = CGPointMake(c.x * map.scale - b.width / 2, c.y * map.scale - b.height / 2);
    off.x = MAX(0, MIN(off.x, scroll.contentSize.width - b.width)); off.y = MAX(0, MIN(off.y, scroll.contentSize.height - b.height));
    if (scroll.contentSize.width <= b.width) off.x = 0; if (scroll.contentSize.height <= b.height) off.y = 0;
    scroll.contentOffset = off;
}
- (void)pick:(NSInteger)i {
    UIViewController *v = nil;
    if (mode == CTMapCaltrain) v = [[CTDeparturesViewController alloc] initWithStation:i];
    else if (mode == CTMapBart) v = [[CTBartViewController alloc] initWithStation:[[[CTBart stations] objectAtIndex:i] objectForKey:@"abbr"]];
    else v = [[CTMetroStopViewController alloc] initWithStop:[[CTMapView metroStops] objectAtIndex:i]];
    [self.navigationController pushViewController:v animated:YES]; [v release];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return map; }
- (void)scrollViewDidZoom:(UIScrollView *)sv { [self center]; }
- (void)scrollViewDidEndZooming:(UIScrollView *)sv withView:(UIView *)v atScale:(float)z {   // bake the pinch into a sharp re-render
    CGSize b = sv.bounds.size; CGPoint c = CGPointMake((sv.contentOffset.x + b.width / 2) / (map.scale * z), (sv.contentOffset.y + b.height / 2) / (map.scale * z));
    [self applyScale:map.scale * z centeredOn:c];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self center]; }
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a]; NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:@"ct_map_zoom"]) { CGFloat z = [d floatForKey:@"ct_map_zoom"]; CGPoint c = CGPointMake([d floatForKey:@"ct_map_x"], [d floatForKey:@"ct_map_y"]); [d removeObjectForKey:@"ct_map_zoom"]; [d removeObjectForKey:@"ct_map_x"]; [d removeObjectForKey:@"ct_map_y"]; [d synchronize]; [self applyScale:z centeredOn:c]; }   // test hook: zoom and the 1x map point to center on
    if ([d objectForKey:@"ct_map_style_test"]) { style = (CTMapStyle)[d integerForKey:@"ct_map_style_test"]; [d removeObjectForKey:@"ct_map_style_test"]; [d synchronize]; [self applyStyle]; }
    if ([d objectForKey:@"ct_test_map_pick"]) { NSInteger i = [d integerForKey:@"ct_test_map_pick"]; [d removeObjectForKey:@"ct_test_map_pick"]; [d synchronize]; [self pick:i]; }
}
@end
