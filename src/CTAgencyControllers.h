#import <UIKit/UIKit.h>
@interface CTBartViewController : UITableViewController { NSString *station; NSArray *deps; NSString *status, *advisories; BOOL busy; NSTimer *timer; UIButton *stationButton; }
@end
@interface CTBartTripViewController : UITableViewController { NSInteger from, to, when; NSArray *trips; NSString *status; BOOL busy; }
@end
@interface CTMuniViewController : UITableViewController { NSArray *stops; NSMutableDictionary *preds; NSString *status; BOOL busy; NSTimeInterval lastFetch; }
- (void)refresh;
@end
@interface CTMuniAddViewController : UITableViewController <UITextFieldDelegate> { UITextField *code; UILabel *nameLabel; }
@end
