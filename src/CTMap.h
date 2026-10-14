#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
// Vector map of the Bay: shoreline polygons from OpenStreetMap (res/bay.json) under the Caltrain track,
// the BART lines or the Muni Metro lines, with tappable stations. A plain view that re-renders itself at the
// end of each pinch (1x to 3x), the way maps did before tiled layers behaved on retina.
typedef enum { CTMapCaltrain = 0, CTMapBart = 1, CTMapMuni = 2 } CTMapMode;
@interface CTMapView : UIView { CTMapMode mode; double W, E, S, N; CGFloat ppd, scale; CGSize baseSize; void (^onPick)(NSInteger); }
@property (nonatomic, readonly) CGSize baseSize;     // size at 1x
- (void)setScale:(CGFloat)s;                          // 1..3; resizes the frame and redraws
- (CGFloat)scale;
- (id)initWithMode:(CTMapMode)m width:(CGFloat)w;
- (void)setOnPick:(void (^)(NSInteger))b;      // index into the mode's station list
- (CGPoint)pointForLon:(double)lon lat:(double)lat;
+ (NSArray *)metroStops;                        // every Muni Metro stop (direction 0 of each line, de-duplicated): {code, name, lat, lon, line, color}
+ (NSArray *)metroLines;                        // res/muni_metro.json lines: {id, name, color, dirs:[{head, stops}], shape}
+ (UIColor *)colorForHex:(NSString *)hex;
@end
@interface CTMapViewController : UIViewController <UIScrollViewDelegate> { UIScrollView *scroll; CTMapView *map; UISegmentedControl *seg; CTMapMode mode; }
@end
