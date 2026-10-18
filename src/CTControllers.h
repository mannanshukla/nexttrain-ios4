#import <UIKit/UIKit.h>
@interface CTDeparturesViewController : UITableViewController <UIActionSheetDelegate> { NSInteger station, dir; NSArray *deps; NSDictionary *live; NSString *liveStatus, *alerts; BOOL busy; NSTimeInterval lastFetch; UISegmentedControl *dirSeg; UIButton *stationButton; NSDictionary *sheetDep; NSInteger sheetNext; UIAlertView *runAlert; BOOL pinned; NSTimer *timer; }
- (id)initWithStation:(NSInteger)s;   // pushed board for one station (Line tab)
@end
@interface CTTripViewController : UITableViewController <UITextFieldDelegate> { NSInteger from, to, when; BOOL arriveBy, busy, alertsBusy; NSArray *trips; NSString *status, *alerts; UITextField *ask; UISegmentedControl *mode; }
@end
@interface CTTripDetailViewController : UITableViewController { NSDictionary *trip; NSInteger fromIdx, toIdx; }
- (id)initWithTrip:(NSDictionary *)t from:(NSInteger)a to:(NSInteger)b;
@end
