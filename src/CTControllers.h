#import <UIKit/UIKit.h>
@interface CTDeparturesViewController : UITableViewController <UIActionSheetDelegate, UIAlertViewDelegate> { NSInteger station, dir; NSArray *deps; NSDictionary *live; NSString *liveStatus, *alerts; BOOL busy; NSTimeInterval lastFetch; UISegmentedControl *dirSeg; UIButton *stationButton; NSDictionary *sheetDep, *nextDep; BOOL pinned; NSTimer *timer; }
- (id)initWithStation:(NSInteger)s;   // pushed board for one station (Line tab)
@end
// Trip tab: "Just say it" (Caltrain and BART routes from a sentence), the Caltrain planner, and the running timer.
@interface CTTripViewController : UITableViewController <UITextFieldDelegate> { NSInteger from, to, when, day; BOOL arriveBy, express, busy, alertsBusy; NSArray *trips, *routes; NSString *status, *alerts, *routeTitle; UITextField *ask; UISegmentedControl *mode; }
@end
// A train's stops. Tapping a stop after yours offers to ring before it.
@interface CTTripDetailViewController : UITableViewController { NSDictionary *trip; NSInteger fromIdx, toIdx; NSTimeInterval base; }
- (id)initWithTrip:(NSDictionary *)t from:(NSInteger)a to:(NSInteger)b base:(NSTimeInterval)midnight;   // midnight of the trip's service day; b = -1 when the rider hasn't picked a stop
@end
// One itinerary from "Just say it": its rides, changes, and a timer for the whole thing.
@interface CTRouteViewController : UITableViewController { NSDictionary *it; }
- (id)initWithItinerary:(NSDictionary *)i;
@end
// The board's Timer button: "Where are you getting off?" for the train you're on, one tap to ring before that stop.
@interface CTTimerPickViewController : UITableViewController { NSInteger station, dir, pick; NSDictionary *live; NSArray *cands, *stops; UISegmentedControl *seg; UILabel *info; }
- (id)initWithStation:(NSInteger)s dir:(NSInteger)d live:(NSDictionary *)lv;
- (BOOL)hasTrain;
@end
