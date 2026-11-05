#import <UIKit/UIKit.h>
// The egg timer. One timer runs at a time and is a list of rings, each a moment with something to say:
// {at (NSNumber, seconds since 1970), say ("Palo Alto is next"), sub ("Get your stuff."), kind ("leave" | "stop" | "manual"),
//  and for Caltrain: code (511 stop code), train, base (the train's scheduled time there), lead (seconds before it), late (minutes, from 511)}.
// Every ring is a UILocalNotification with the bundled bell, so it goes off with the app suspended or the screen locked.
// While the app is open the timer asks 511 where the train is and moves its rings.
extern NSString *const CTTimerChanged;   // posted when rings move, go off, or the minute changes

@interface CTTimer : NSObject <UIActionSheetDelegate>
+ (void)setHost:(UIViewController *)vc;                      // the tab bar controller; the timer screen is presented over it
+ (NSDictionary *)current;                                  // {title, rings} or nil
+ (NSDictionary *)nextRing;                                 // the earliest ring still to go off (or going off now)
+ (void)startTitle:(NSString *)title rings:(NSArray *)rings show:(BOOL)show;   // replaces any running timer
+ (void)cancel;
+ (void)stopRing;                                           // the ring going off now was acknowledged
+ (void)show;                                               // presents the timer screen
+ (void)showManual:(NSString *)title;                       // dial-it-yourself timer (Muni has no trip times)
+ (void)resume;                                             // app became active
+ (void)rang:(BOOL)withSound;                               // a ring's notification arrived
+ (void)offerSegs:(NSArray *)segs title:(NSString *)title;  // asks "ring before X" / "and when to leave", then starts it
+ (NSString *)liveText;                                     // "Live from 511: 3 min late", "Scheduled times", ...
+ (void)startSound; + (void)stopSound;
@end

// A wind-up kitchen egg timer seen from the front: the top half carries the minutes round its seam and turns back toward the pointer as time runs out.
@interface CTEggView : UIView { double minutes, shown, dragFrom; BOOL ringing, settable, moved; id target; SEL action; UIImage *body; CGPoint touchStart; NSTimer *anim; }
@property (nonatomic) double minutes;                       // where the top is turned to (0 to 60)
@property (nonatomic) BOOL ringing, settable;               // settable: drag sideways to twist it
- (void)setTarget:(id)t action:(SEL)a;                      // called while it is twisted by hand
- (void)windTo:(double)m;                                   // turn the top to m with a short twist
- (void)hop;
@end

@interface CTTimerViewController : UIViewController { CTEggView *egg; UILabel *big, *what, *when, *later, *caption; UIButton *button, *ticking; NSTimer *tick; BOOL manual, ringing; NSString *manualTitle; NSTimeInterval lastLeft; }
- (id)initManual:(NSString *)title;
- (void)refresh;
- (void)ring:(BOOL)withSound;
- (void)close;
- (BOOL)isRinging;
@end
