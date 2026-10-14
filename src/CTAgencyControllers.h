#import <UIKit/UIKit.h>
@interface CTBartViewController : UITableViewController { NSString *station; NSArray *deps; NSString *status, *advisories; BOOL busy, pinned; NSTimer *timer; UIButton *stationButton; }
- (id)initWithStation:(NSString *)abbr;   // pushed board for one station (Map tab); does not touch the home station
@end
// Muni Metro: J K L M N T from res/muni_metro.json. A line lists its stops per direction; a stop is a 511 board for that stop code.
@interface CTMetroLineViewController : UITableViewController { NSDictionary *line; NSInteger dir; UISegmentedControl *dirSeg; }
- (id)initWithLine:(NSDictionary *)l;
@end
@interface CTMetroStopViewController : UITableViewController { NSDictionary *stop; NSArray *preds; NSString *status; BOOL busy; }
- (id)initWithStop:(NSDictionary *)s;      // {code, name, lat, lon, line, color}
@end
@interface CTBartTripViewController : UITableViewController { NSInteger from, to, when; NSArray *trips; NSString *status; BOOL busy; }
@end
@interface CTMuniViewController : UITableViewController { NSArray *stops; NSMutableDictionary *preds; NSString *status; BOOL busy; NSTimeInterval lastFetch; }
- (void)refresh;
@end
@interface CTMuniAddViewController : UITableViewController <UITextFieldDelegate> { UITextField *code; UILabel *nameLabel; }
@end
