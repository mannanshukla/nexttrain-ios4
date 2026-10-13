#import <UIKit/UIKit.h>
typedef void (^CTDrumChange)(NSInteger row);
// Slide-up wheel picker shared by all screens.
@interface CTDrum : NSObject <UIPickerViewDataSource, UIPickerViewDelegate> { UIView *view; UIPickerView *picker; UILabel *title; NSArray *rows; CTDrumChange onChange; void (^onDone)(void); }
+ (CTDrum *)shared;
- (void)showInView:(UIView *)host title:(NSString *)t rows:(NSArray *)r selected:(NSInteger)i onChange:(CTDrumChange)c onDone:(void (^)(void))d;
- (void)hide;
@end
NSArray *CTTimeRows(void);                 // "12:00 AM" ... in 5 minute steps (288 rows)
NSArray *CTStationRows(void);
