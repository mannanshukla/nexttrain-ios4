#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
// Vector map of the Bay: shoreline polygons from OpenStreetMap (res/bay.json) under the Caltrain track,
// the BART lines or the Muni Metro lines, with tappable stations. Drawn through CATiledLayer so pinch zoom re-renders sharp.
typedef enum { CTMapCaltrain = 0, CTMapBart = 1, CTMapMuni = 2 } CTMapMode;
@interface CTMapView : UIView { CTMapMode mode; double W, E, S, N; CGFloat ppd, displayZoom; void (^onPick)(NSInteger); }
@property (nonatomic, assign) CGFloat displayZoom;   // the scroll view's zoomScale, used to decide which labels to draw
- (id)initWithMode:(CTMapMode)m width:(CGFloat)w;
- (void)setOnPick:(void (^)(NSInteger))b;      // index into the mode's station list
- (CGPoint)pointForLon:(double)lon lat:(double)lat;
+ (NSArray *)metroStops;                        // every Muni Metro stop (direction 0 of each line, de-duplicated): {code, name, lat, lon, line, color}
+ (NSArray *)metroLines;                        // res/muni_metro.json lines: {id, name, color, dirs:[{head, stops}], shape}
+ (UIColor *)colorForHex:(NSString *)hex;
@end
@interface CTMapViewController : UIViewController <UIScrollViewDelegate> { UIScrollView *scroll; CTMapView *map; UISegmentedControl *seg; CTMapMode mode; }
@end
