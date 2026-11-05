#import "CTControllers.h"
#import "CTData.h"
#import "CTLive.h"
#import "CTPlan.h"
#import "CTTimer.h"
#import "CTAgencies.h"
#import "CTViews.h"
#import <QuartzCore/QuartzCore.h>


static UIView *logoTitle(NSString *png) {   // full-color agency mark on a white pill, for the nav bar
    UIImage *img = [UIImage imageNamed:png]; CGFloat h = 24, w = img.size.width * h / img.size.height;
    UIView *pill = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, w + 20, 32)] autorelease]; pill.backgroundColor = [UIColor whiteColor]; pill.layer.cornerRadius = 7;
    UIImageView *iv = [[[UIImageView alloc] initWithImage:img] autorelease]; iv.frame = CGRectMake(10, 4, w, h); iv.contentMode = UIViewContentModeScaleAspectFit; [pill addSubview:iv];
    return pill;
}
static UIColor *green(void) { return [UIColor colorWithRed:0.80 green:0.10 blue:0.18 alpha:1]; }   // Caltrain red, kept under the old name
static UIColor *amber(CGFloat a) { return [UIColor colorWithRed:1.0 green:0.69 blue:0.0 alpha:a]; }
static UIFont *boardFont(CGFloat sz) { return [UIFont fontWithName:@"CourierNewPS-BoldMT" size:sz] ?: [UIFont boldSystemFontOfSize:sz]; }
static NSString *shortHead(NSString *h) { if ([h isEqualToString:@"San Francisco"]) return @"SF"; if ([h isEqualToString:@"San Jose Diridon"]) return @"San Jose"; return h; }
static NSString *stationName(NSInteger i) { NSArray *s = [CTData stations]; return i >= 0 && i < (NSInteger)[s count] ? [[s objectAtIndex:i] objectForKey:@"name"] : @"?"; }

@implementation CTDeparturesViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Caltrain"; self.tabBarItem.title = @"Caltrain"; self.navigationItem.titleView = logoTitle(@"logo-caltrain.png"); station = [CTData homeStation]; dir = [CTData homeDir];
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshLive)] autorelease];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(foreground) name:UIApplicationWillEnterForegroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timerButton) name:CTTimerChanged object:nil];
        [self timerButton];
    }
    return self;
}
- (void)timerButton {   // top left of the home board: the timer, showing minutes left while one runs
    if (pinned) return;
    NSDictionary *r = [CTTimer nextRing]; long m = r ? (long)ceil(([[r objectForKey:@"at"] doubleValue] - [[NSDate date] timeIntervalSince1970]) / 60) : 0;
    NSString *t = !r ? @"Timer" : m <= 0 ? @"Ringing" : m < 100 ? [NSString stringWithFormat:@"%ld min", m] : @"Timer";
    if ([self.navigationItem.leftBarButtonItem.title isEqualToString:t]) return;
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:t style:r ? UIBarButtonItemStyleDone : UIBarButtonItemStyleBordered target:self action:@selector(openTimer)] autorelease];
}
- (void)openTimer {
    if ([CTTimer current]) { [CTTimer show]; return; }
    CTTimerPickViewController *v = [[CTTimerPickViewController alloc] initWithStation:station dir:dir live:live];
    if (![v hasTrain]) { [[[[UIAlertView alloc] initWithTitle:@"No train to time" message:[NSString stringWithFormat:@"Nothing has left %@ %@ in the last half hour, and nothing leaves in the next hour.", stationName(station), dir == 0 ? @"northbound" : @"southbound"] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show]; [v release]; return; }
    [self.navigationController pushViewController:v animated:YES]; [v release];
}
- (id)initWithStation:(NSInteger)s {
    if ((self = [self init])) { pinned = YES; station = s; self.navigationItem.titleView = nil; self.title = stationName(s); self.navigationItem.leftBarButtonItem = nil; self.hidesBottomBarWhenPushed = YES; }   // a pushed board keeps its Back button
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [timer invalidate]; [deps release]; [live release]; [liveStatus release]; [alerts release]; [dirSeg release]; [stationButton release]; [sheetDep release]; [nextDep release]; [super dealloc]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor blackColor]; self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)] autorelease]; hdr.backgroundColor = [UIColor blackColor];
    stationButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    stationButton.frame = CGRectMake(10, 10, 300, 40); stationButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    stationButton.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1]; stationButton.layer.cornerRadius = 8; stationButton.layer.borderWidth = 1; stationButton.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1].CGColor;
    stationButton.titleLabel.font = [UIFont boldSystemFontOfSize:19]; [stationButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [stationButton addTarget:self action:@selector(pickStation) forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:stationButton];
    dirSeg = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Northbound", @"Southbound", nil]]; dirSeg.segmentedControlStyle = UISegmentedControlStyleBar; dirSeg.tintColor = [UIColor colorWithWhite:0.25 alpha:1];
    dirSeg.frame = CGRectMake(10, 58, 300, 30); dirSeg.autoresizingMask = UIViewAutoresizingFlexibleWidth; dirSeg.selectedSegmentIndex = dir; [dirSeg addTarget:self action:@selector(dirChanged) forControlEvents:UIControlEventValueChanged];
    [hdr addSubview:dirSeg];
    self.tableView.tableHeaderView = hdr;
    UILabel *foot = [[[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 60)] autorelease]; foot.tag = 77; foot.backgroundColor = [UIColor blackColor]; foot.textColor = [UIColor colorWithWhite:0.55 alpha:1]; foot.font = [UIFont systemFontOfSize:13]; foot.numberOfLines = 0; foot.textAlignment = UITextAlignmentCenter;
    self.tableView.tableFooterView = foot;
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; if (!pinned && [CTData homeStation] != station) { station = [CTData homeStation]; [live release]; live = nil; } [self reload]; }
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:@"ct_test_pick"]) { [d removeObjectForKey:@"ct_test_pick"]; [d synchronize]; [self pickStation]; }
    if ([[CTData token] length] && [[NSDate date] timeIntervalSince1970] - lastFetch > 90) [self refreshLive];
    [timer invalidate]; [timer release]; timer = [[NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(reload) userInfo:nil repeats:YES] retain];   // keep the countdowns current
}
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [timer invalidate]; [timer release]; timer = nil; [[CTDrum shared] hide]; }
- (void)foreground {   // back from the background hours later: the board must not show trains that already left
    if (!self.isViewLoaded || !self.view.window) return;
    [self reload]; if ([[CTData token] length] && [[NSDate date] timeIntervalSince1970] - lastFetch > 90) [self refreshLive];
}
- (void)reload {
    [stationButton setTitle:[NSString stringWithFormat:@"%@  ▾", stationName(station)] forState:UIControlStateNormal];
    [deps release]; deps = [[CTData departuresFrom:station dir:dir date:[NSDate date] after:[CTData minutesNow]] retain];
    UILabel *foot = (UILabel *)[self.tableView.tableFooterView viewWithTag:77];
    foot.text = liveStatus ?: ([[CTData token] length] ? @"" : @"Scheduled times. Add a 511 token in Settings for live predictions.");
    [self.tableView reloadData];
}
- (void)pickStation {
    [[CTDrum shared] showInView:self.tabBarController.view title:@"Station" rows:CTStationRows() selected:station
        onChange:^(NSInteger r) { station = r; [CTData setHomeStation:r]; [self reload]; }
        onDone:^{ [live release]; live = nil; [self reload]; if ([[CTData token] length]) [self refreshLive]; }];
}
- (void)dirChanged { dir = dirSeg.selectedSegmentIndex; [CTData setHomeDir:dir]; [live release]; live = nil; [self reload]; if ([[CTData token] length]) [self refreshLive]; }
- (void)refreshLive {
    if (busy) return;
    if (![[CTData token] length]) { [liveStatus release]; liveStatus = @"Scheduled times. Add a 511 token in Settings for live predictions."; [self.tableView reloadData]; return; }
    busy = YES; lastFetch = [[NSDate date] timeIntervalSince1970]; [liveStatus release]; liveStatus = @"Checking 511..."; [self.tableView reloadData];
    NSString *code = [[[[CTData stations] objectAtIndex:station] objectForKey:@"codes"] objectForKey:dir == 0 ? @"N" : @"S"];
    [self performSelectorInBackground:@selector(fetch:) withObject:code];
}
- (void)fetch:(NSString *)code {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *err = nil;
    NSDictionary *r = [CTLive predictionsForStopCode:code error:&err];
    NSString *al = r ? [CTLive alertsWithError:NULL] : nil;
    [self performSelectorOnMainThread:@selector(fetched:) withObject:[NSArray arrayWithObjects:(r ?: [NSDictionary dictionary]), (err ?: @""), (al ?: @""), nil] waitUntilDone:NO];
    [p release];
}
- (void)fetched:(NSArray *)r {
    busy = NO; NSString *err = [r objectAtIndex:1];
    [live release]; live = [err length] ? nil : [[r objectAtIndex:0] retain];
    [alerts release]; alerts = [[r objectAtIndex:2] length] ? [[r objectAtIndex:2] copy] : nil;
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"h:mm a"];
    [liveStatus release]; liveStatus = [err length] ? [err copy] : [[NSString stringWithFormat:@"Live from 511 at %@. %lu train%@ reporting.", [f stringFromDate:[NSDate date]], (unsigned long)[live count], [live count] == 1 ? @"" : @"s"] copy];
    [self.tableView reloadData];
}
- (BOOL)isAlertSection:(NSInteger)s { return alerts && s == 0; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return alerts ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [self isAlertSection:s] ? 1 : MAX(1, MIN(12, (NSInteger)[deps count])); }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    BOOL al = [self isAlertSection:s];
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 26)] autorelease]; v.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    UILabel *l = [[[UILabel alloc] initWithFrame:CGRectMake(12, 0, 296, 26)] autorelease]; l.backgroundColor = [UIColor clearColor]; l.font = boardFont(13); l.textColor = al ? [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1] : amber(1);
    l.text = al ? @"SERVICE ALERTS" : [[NSString stringWithFormat:@"%@BOUND  ·  %@", dir == 0 ? @"NORTH" : @"SOUTH", stationName(station)] uppercaseString];
    [v addSubview:l]; return v;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return 26; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip { c.backgroundColor = [self isAlertSection:ip.section] ? [UIColor colorWithRed:0.30 green:0.05 blue:0.08 alpha:1] : [UIColor blackColor]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { if ([self isAlertSection:ip.section]) return MAX(44, [alerts sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(290, 400) lineBreakMode:UILineBreakModeWordWrap].height + 20); return 58; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isAlertSection:ip.section]) { UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; c.textLabel.text = alerts; c.textLabel.numberOfLines = 0; c.textLabel.font = [UIFont systemFontOfSize:14]; c.textLabel.textColor = [UIColor whiteColor]; c.textLabel.backgroundColor = [UIColor clearColor]; c.textLabel.lineBreakMode = UILineBreakModeWordWrap; return c; }
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"d"];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"d"] autorelease]; c.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1]; c.textLabel.font = boardFont(21); c.detailTextLabel.font = [UIFont systemFontOfSize:13]; c.textLabel.backgroundColor = [UIColor clearColor]; c.detailTextLabel.backgroundColor = [UIColor clearColor];
        UIView *sel = [[[UIView alloc] init] autorelease]; sel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1]; c.selectedBackgroundView = sel; }
    if (![deps count]) { c.textLabel.text = @"NO MORE TRAINS"; c.textLabel.textColor = amber(0.6); c.detailTextLabel.text = @"Check the other direction, or tomorrow's first train in Trip."; c.imageView.image = nil; c.accessoryType = UITableViewCellAccessoryNone; c.selectionStyle = UITableViewCellSelectionStyleNone; return c; }
    NSDictionary *d = [deps objectAtIndex:ip.row]; NSDictionary *t = [d objectForKey:@"trip"];
    NSInteger dep = [[d objectForKey:@"dep"] integerValue], now = [CTData minutesNow], shown = dep; NSString *note = nil;
    NSDictionary *lv = [live objectForKey:[t objectForKey:@"n"]];
    if (lv) { NSInteger exp = [[lv objectForKey:@"expected"] integerValue], late = exp - dep; shown = exp; note = late >= 2 ? [NSString stringWithFormat:@"%ld min late", (long)late] : late <= -2 ? [NSString stringWithFormat:@"%ld min early", (long)-late] : @"on time"; }
    NSInteger mins = shown - now;
    c.textLabel.text = [NSString stringWithFormat:@"%@  %@", [[CTData fmtMin:shown] stringByReplacingOccurrencesOfString:@" " withString:@""], mins <= 0 ? @"NOW" : mins < 60 ? [NSString stringWithFormat:@"%ld MIN", (long)mins] : [NSString stringWithFormat:@"%ldH %ldM", (long)mins / 60, (long)mins % 60]];
    c.textLabel.textColor = amber(lv ? 1.0 : 0.6);
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@ → %@ · %@", [t objectForKey:@"type"], [t objectForKey:@"n"], shortHead([t objectForKey:@"head"]), note ?: @"scheduled"];
    c.detailTextLabel.textColor = lv ? [UIColor colorWithWhite:0.85 alpha:1] : [UIColor colorWithWhite:0.5 alpha:1];
    c.imageView.image = [CTData badgeForType:[t objectForKey:@"type"]];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleBlue;
    return c;
}
- (NSInteger)minutesFor:(NSDictionary *)d { NSDictionary *lv = [live objectForKey:[[d objectForKey:@"trip"] objectForKey:@"n"]]; NSInteger shown = lv ? [[lv objectForKey:@"expected"] integerValue] : [[d objectForKey:@"dep"] integerValue]; return shown - [CTData minutesNow]; }
- (NSTimeInterval)baseFor:(NSDictionary *)d {   // midnight of the train's service day; last night's trains run past midnight
    NSInteger raw = [[[[[d objectForKey:@"trip"] objectForKey:@"stops"] objectAtIndex:[[d objectForKey:@"idx"] integerValue]] objectAtIndex:1] integerValue];
    return [CTData midnightPlus:0] + ([[d objectForKey:@"dep"] integerValue] - raw) * 60;
}
- (NSDictionary *)segFor:(NSDictionary *)d {   // this train from this station, leaving when 511 says it will
    NSDictionary *t = [d objectForKey:@"trip"]; NSInteger idx = [[d objectForKey:@"idx"] integerValue];
    NSMutableDictionary *seg = [[[CTRoute caltrainTrip:t from:idx to:[[t objectForKey:@"stops"] count] - 1 base:[self baseFor:d]] mutableCopy] autorelease];
    NSDictionary *lv = [live objectForKey:[t objectForKey:@"n"]];
    if (lv) [seg setObject:[NSNumber numberWithDouble:[CTData midnightPlus:0] + [[lv objectForKey:@"expected"] integerValue] * 60] forKey:@"depAt"];
    return seg;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; if ([self isAlertSection:ip.section] || ![deps count]) return;
    NSDictionary *d = [deps objectAtIndex:ip.row]; NSInteger mins = [self minutesFor:d];
    [sheetDep release]; sheetDep = [d retain];
    UIActionSheet *s = [[[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"%@ %@ leaves in %ld min", [[d objectForKey:@"trip"] objectForKey:@"type"], [[d objectForKey:@"trip"] objectForKey:@"n"], (long)MAX(0, mins)] delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Ring me when to leave", @"Ring before my stop", nil] autorelease];
    [s showInView:self.tabBarController ? self.tabBarController.view : self.view];
}
- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (!sheetDep) return;
    if (i == 1) {   // the stop list, where tapping your stop sets the timer
        CTTripDetailViewController *v = [[CTTripDetailViewController alloc] initWithTrip:[sheetDep objectForKey:@"trip"] from:[[sheetDep objectForKey:@"idx"] integerValue] to:-1 base:[self baseFor:sheetDep]];
        [self.navigationController pushViewController:v animated:YES]; [v release]; return;
    }
    if (i != 0) return;
    NSUInteger k = [deps indexOfObject:sheetDep];
    [self leaveFor:sheetDep next:k != NSNotFound && k + 1 < [deps count] ? [deps objectAtIndex:k + 1] : nil];
}
// Ring when it's time to walk to the platform, or say plainly whether this one is still makeable.
- (void)leaveFor:(NSDictionary *)d next:(NSDictionary *)n {
    NSDictionary *seg = [self segFor:d], *ring = [CTRoute leaveRingFor:seg];
    if (ring) { [CTTimer startTitle:[NSString stringWithFormat:@"%@ from %@", [seg objectForKey:@"label"], stationName(station)] rings:[NSArray arrayWithObject:ring] show:YES]; return; }
    NSInteger mins = [self minutesFor:d], walk = [CTData walkMinutes]; NSString *title, *msg;
    [nextDep release]; nextDep = nil;
    if (mins >= walk) { title = @"Leave now."; msg = [NSString stringWithFormat:@"It leaves in %ld min and the walk is %ld.", (long)mins, (long)walk]; }
    else if (mins * 2 >= walk) { title = @"Go now, at a jog."; msg = [NSString stringWithFormat:@"%ld min to go. The walk is %ld; jogging takes about half that.", (long)MAX(0, mins), (long)walk]; }
    else {
        title = @"Let this one go.";
        msg = n ? [NSString stringWithFormat:@"%ld min isn't enough for a %ld min walk. The next one leaves in %ld min.", (long)MAX(0, mins), (long)walk, (long)[self minutesFor:n]] : @"It's the last train this way today.";
        nextDep = [n retain];
    }
    [[[[UIAlertView alloc] initWithTitle:title message:msg delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nextDep ? @"Ring for the next one" : nil, nil] autorelease] show];
}
- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)i {
    if (i != 1 || !nextDep) return;
    NSDictionary *d = [[nextDep retain] autorelease]; NSUInteger k = [deps indexOfObject:d];
    [self leaveFor:d next:k != NSNotFound && k + 1 < [deps count] ? [deps objectAtIndex:k + 1] : nil];
}
@end

enum { kTimer, kAsk, kRoute, kForm, kResults, kAlerts };
static BOOL isExpress(NSDictionary *trip) { NSString *t = [trip objectForKey:@"type"]; return [t isEqualToString:@"Express"] || [t isEqualToString:@"Limited"]; }
static NSString *dayName(NSInteger day) {
    if (day <= 0) return @"today"; if (day == 1) return @"tomorrow";
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"EEE"]; return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[CTData midnightPlus:day] + 43200]];
}

@implementation CTTripViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Trip"; self.tabBarItem.title = @"Trip"; from = [CTData homeStation]; to = [CTData stationNamed:[CTData homeStation] == [CTData stationNamed:@"san francisco"] ? @"palo alto" : @"san francisco"]; when = -1;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timerChanged) name:CTTimerChanged object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [trips release]; [routes release]; [routeTitle release]; [status release]; [ask release]; [mode release]; [alerts release]; [super dealloc]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    ask = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 260, 30)]; ask.placeholder = @"\"stanford to sfo friday by 10\""; ask.font = [UIFont systemFontOfSize:16]; ask.delegate = self; ask.returnKeyType = UIReturnKeyGo; ask.clearButtonMode = UITextFieldViewModeWhileEditing; ask.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter; ask.autocapitalizationType = UITextAutocapitalizationTypeNone; ask.autocorrectionType = UITextAutocorrectionTypeNo;
    mode = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Leave at", @"Arrive by", nil]]; mode.segmentedControlStyle = UISegmentedControlStyleBar; mode.tintColor = [UIColor colorWithWhite:0.35 alpha:1]; mode.selectedSegmentIndex = 0;
    [mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [self search];
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults]; NSString *q = [d stringForKey:@"ct_test_ask"];
    if (q) { [d removeObjectForKey:@"ct_test_ask"]; [d synchronize]; ask.text = q; [self runAsk]; }
    if ([d objectForKey:@"ct_scroll"]) { [self.tableView setContentOffset:CGPointMake(0, [d floatForKey:@"ct_scroll"]) animated:NO]; [d removeObjectForKey:@"ct_scroll"]; [d synchronize]; }
    if ([d boolForKey:@"ct_test_detail"] && [trips count] && !routes) { [d removeObjectForKey:@"ct_test_detail"]; [d synchronize]; [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:[self sectionOf:kResults]]]; }
}
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [[CTDrum shared] hide]; }
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    [alerts release]; alerts = [[CTLive cachedAlerts] length] ? [[CTLive cachedAlerts] copy] : nil; [self.tableView reloadData];
    if ([[CTData token] length] && [CTLive alertsAge] > 600 && !alertsBusy) { alertsBusy = YES; [self performSelectorInBackground:@selector(fetchAlerts) withObject:nil]; }
}
- (void)timerChanged { if (![self isViewLoaded] || [ask isFirstResponder]) return; [self.tableView reloadData]; }   // a reload would take the keyboard away mid-sentence
- (void)fetchAlerts { NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *t = [CTLive alertsWithError:NULL]; [self performSelectorOnMainThread:@selector(gotAlerts:) withObject:(t ?: @"") waitUntilDone:NO]; [p release]; }
- (void)gotAlerts:(NSString *)t { alertsBusy = NO; [alerts release]; alerts = [t length] ? [t copy] : nil; [self.tableView reloadData]; }
- (NSArray *)secs {
    NSMutableArray *a = [NSMutableArray array];
    if ([CTTimer current]) [a addObject:[NSNumber numberWithInt:kTimer]];
    [a addObject:[NSNumber numberWithInt:kAsk]];
    if (routes) [a addObject:[NSNumber numberWithInt:kRoute]];
    else { [a addObject:[NSNumber numberWithInt:kForm]]; [a addObject:[NSNumber numberWithInt:kResults]]; }
    if (alerts) [a addObject:[NSNumber numberWithInt:kAlerts]];
    return a;
}
- (NSInteger)kind:(NSInteger)s { NSArray *a = [self secs]; return s < (NSInteger)[a count] ? [[a objectAtIndex:s] integerValue] : -1; }
- (NSInteger)sectionOf:(NSInteger)k { NSUInteger i = [[self secs] indexOfObject:[NSNumber numberWithInt:(int)k]]; return i == NSNotFound ? 0 : i; }
- (void)setRoutes:(NSArray *)r title:(NSString *)t { [routes release]; routes = [r retain]; [routeTitle release]; routeTitle = [t copy]; }
- (void)updateClear {   // anything "Just say it" set that the form can't show or undo
    BOOL on = routes || day || express;
    if (on != (self.navigationItem.leftBarButtonItem != nil)) self.navigationItem.leftBarButtonItem = on ? [[[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStyleBordered target:self action:@selector(clearAsk)] autorelease] : nil;
}
- (void)clearAsk { [self setRoutes:nil title:nil]; [status release]; status = nil; ask.text = @""; day = 0; express = NO; when = -1; arriveBy = NO; [self search]; }
- (void)modeChanged { arriveBy = mode.selectedSegmentIndex == 1; if (arriveBy && when < 0) when = ((([CTData minutesNow] + 60) / 5) * 5) % 1440; [self search]; }
- (void)search {
    NSInteger leave = arriveBy ? -1 : (when < 0 ? (day == 0 ? [CTData minutesNow] : 0) : when), by = arriveBy ? when : -1;
    NSArray *all = [CTData tripsFrom:from to:to date:[NSDate dateWithTimeIntervalSince1970:[CTData midnightPlus:day] + 43200] leaveAfter:leave arriveBy:by];
    NSMutableArray *fast = [NSMutableArray array]; if (express) for (NSDictionary *d in all) if (isExpress([d objectForKey:@"trip"])) [fast addObject:d];
    [trips release]; trips = [([fast count] ? fast : all) retain];
    [self updateClear]; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [[self secs] count]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch ([self kind:s]) { case kForm: return 4; case kResults: return MAX(1, MIN(8, (NSInteger)[trips count])); case kRoute: return MAX(1, (NSInteger)[routes count]); default: return 1; }
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch ([self kind:s]) {
        case kTimer: return @"Timer";
        case kAsk: return @"Just say it";
        case kRoute: return routeTitle;
        case kResults: return [NSString stringWithFormat:@"%@ to %@%@", stationName(from), stationName(to), day ? [NSString stringWithFormat:@", %@", dayName(day)] : @""];
        case kAlerts: return @"Caltrain alerts";
    }
    return nil;
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch ([self kind:s]) {
        case kAsk: return status ?: @"Where you're going and when, in your own words. Caltrain and BART, with the change at Millbrae.";
        case kRoute: return [routes count] ? @"Times from the Caltrain timetable and BART's schedule. Tap a trip to set a timer." : nil;
        case kResults: if ([trips count]) { double fare = [CTData fareFrom:from to:to]; NSString *x = express && [trips count] && isExpress([[trips objectAtIndex:0] objectForKey:@"trip"]) ? @"Express and Limited only. " : @""; return fare > 0 ? [NSString stringWithFormat:@"%@Adult Clipper fare $%.2f. Times from the Caltrain timetable, valid through %@.", x, fare, [CTData feedEnd]] : nil; }
    }
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger k = [self kind:ip.section];
    if (k == kTimer) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        NSDictionary *r = [CTTimer nextRing]; long m = (long)ceil(([[r objectForKey:@"at"] doubleValue] - [[NSDate date] timeIntervalSince1970]) / 60);
        c.textLabel.text = m <= 0 ? @"Ringing" : m < 60 ? [NSString stringWithFormat:@"Rings in %ld min", m] : [NSString stringWithFormat:@"Rings in %ld h %ld min", m / 60, m % 60];
        c.textLabel.textColor = [UIColor colorWithRed:0.80 green:0.10 blue:0.18 alpha:1];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [r objectForKey:@"say"], [CTData fmtTime:[[r objectForKey:@"at"] doubleValue]]];
        return c;
    }
    if (k == kAsk) { UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; ask.frame = CGRectMake(10, 7, c.contentView.bounds.size.width - 20, 30); ask.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:ask]; return c; }
    if (k == kForm) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (ip.row == 0) { c.textLabel.text = @"From"; c.detailTextLabel.text = stationName(from); }
        else if (ip.row == 1) { c.textLabel.text = @"To"; c.detailTextLabel.text = stationName(to); }
        else if (ip.row == 2) { c.accessoryType = UITableViewCellAccessoryNone; c.selectionStyle = UITableViewCellSelectionStyleNone; mode.selectedSegmentIndex = arriveBy ? 1 : 0; mode.frame = CGRectMake(8, 7, c.contentView.bounds.size.width - 16, 30); mode.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:mode]; }
        else { c.textLabel.text = arriveBy ? @"Arrive by" : @"Leave at"; c.detailTextLabel.text = when < 0 ? (day ? [dayName(day) capitalizedString] : @"Now") : day ? [NSString stringWithFormat:@"%@ %@", [CTData fmtMin:when], dayName(day)] : [CTData fmtMin:when]; }
        return c;
    }
    if (k == kAlerts) { UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; c.textLabel.text = alerts; c.textLabel.numberOfLines = 0; c.textLabel.font = [UIFont systemFontOfSize:14]; c.textLabel.textColor = [UIColor colorWithRed:0.55 green:0.05 blue:0.08 alpha:1]; c.textLabel.lineBreakMode = UILineBreakModeWordWrap; return c; }
    if (k == kRoute) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease]; c.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1]; c.textLabel.font = [UIFont boldSystemFontOfSize:17];
        if (![routes count]) { c.textLabel.text = busy ? @"Finding times..." : @"No trips found"; c.textLabel.textColor = [UIColor grayColor]; c.selectionStyle = UITableViewCellSelectionStyleNone; return c; }
        NSDictionary *it = [routes objectAtIndex:ip.row]; double dep = [[it objectForKey:@"depAt"] doubleValue], arr = [[it objectForKey:@"arrAt"] doubleValue];
        c.textLabel.text = [NSString stringWithFormat:@"%@  →  %@", [CTData fmtTime:dep], [CTData fmtTime:arr]];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%ld min · %@", (long)floor((arr - dep) / 60 + 0.5), [CTRoute summary:it]]; c.detailTextLabel.numberOfLines = 2; c.detailTextLabel.font = [UIFont systemFontOfSize:12];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"t"];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"t"] autorelease]; c.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1]; c.textLabel.font = [UIFont boldSystemFontOfSize:17]; }
    if (![trips count]) { c.textLabel.text = @"No trains found"; c.textLabel.textColor = [UIColor grayColor]; c.detailTextLabel.text = arriveBy ? @"Nothing arrives that early. Try a later time." : @"Nothing later that day. Try an earlier time or swap the direction."; c.imageView.image = nil; c.accessoryType = UITableViewCellAccessoryNone; c.selectionStyle = UITableViewCellSelectionStyleNone; return c; }
    NSDictionary *d = [trips objectAtIndex:ip.row]; NSDictionary *t = [d objectForKey:@"trip"];
    NSInteger dep = [[d objectForKey:@"dep"] integerValue], arr = [[d objectForKey:@"arr"] integerValue], stops = [[d objectForKey:@"toIdx"] integerValue] - [[d objectForKey:@"fromIdx"] integerValue] - 1;
    c.textLabel.text = [NSString stringWithFormat:@"%@  →  %@", [CTData fmtMin:dep], [CTData fmtMin:arr]]; c.textLabel.textColor = [UIColor blackColor];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%ld min · %@ %@ · %ld stop%@", (long)(arr - dep), [t objectForKey:@"type"], [t objectForKey:@"n"], (long)stops, stops == 1 ? @"" : @"s"];
    c.imageView.image = [CTData badgeForType:[t objectForKey:@"type"]]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleBlue;
    return c;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    switch ([self kind:ip.section]) {
        case kAlerts: return MAX(44, [alerts sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(270, 600) lineBreakMode:UILineBreakModeWordWrap].height + 20);
        case kResults: return 56; case kRoute: return [routes count] ? 62 : 44; case kTimer: return 52;
    }
    return 44;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; [ask resignFirstResponder];
    UIView *host = self.tabBarController.view; NSInteger k = [self kind:ip.section];
    if (k == kTimer) [CTTimer show];
    else if (k == kForm && ip.row == 0) [[CTDrum shared] showInView:host title:@"From" rows:CTStationRows() selected:from onChange:^(NSInteger r) { from = r; [self search]; } onDone:nil];
    else if (k == kForm && ip.row == 1) [[CTDrum shared] showInView:host title:@"To" rows:CTStationRows() selected:to onChange:^(NSInteger r) { to = r; [self search]; } onDone:nil];
    else if (k == kForm && ip.row == 3) [[CTDrum shared] showInView:host title:arriveBy ? @"Arrive by" : @"Leave at" rows:CTTimeRows() selected:(when < 0 ? (day ? 8 * 60 : [CTData minutesNow]) : when) / 5 onChange:^(NSInteger r) { when = r * 5; [self search]; } onDone:nil];
    else if (k == kResults && [trips count]) { NSDictionary *d = [trips objectAtIndex:ip.row]; CTTripDetailViewController *v = [[CTTripDetailViewController alloc] initWithTrip:[d objectForKey:@"trip"] from:[[d objectForKey:@"fromIdx"] integerValue] to:[[d objectForKey:@"toIdx"] integerValue] base:[CTData midnightPlus:day]]; [self.navigationController pushViewController:v animated:YES]; [v release]; }
    else if (k == kRoute && [routes count]) { CTRouteViewController *v = [[CTRouteViewController alloc] initWithItinerary:[routes objectAtIndex:ip.row]]; [self.navigationController pushViewController:v animated:YES]; [v release]; }
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self runAsk]; return YES; }
- (void)runAsk {
    NSString *q = [ask.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (![q length] || busy) return;
    busy = YES; [status release]; status = @"Asking OpenRelay..."; [self.tableView reloadData];
    [self performSelectorInBackground:@selector(askWork:) withObject:q];
}
- (void)askWork:(NSString *)q {   // the model picks the route; a plan with BART in it also needs BART's times, fetched here too
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *err = nil;
    NSDictionary *plan = [CTAI planTrip:q error:&err]; NSArray *its = nil; NSArray *legs = [plan objectForKey:@"legs"];
    if (plan && ([legs count] > 1 || ![[[legs objectAtIndex:0] objectForKey:@"mode"] isEqualToString:@"caltrain"])) its = [CTRoute itinerariesFor:plan error:&err] ?: [NSArray array];
    [self performSelectorOnMainThread:@selector(asked:) withObject:[NSArray arrayWithObjects:(plan ?: [NSDictionary dictionary]), (err ?: @""), (its ?: (id)[NSNull null]), nil] waitUntilDone:NO];
    [p release];
}
- (void)asked:(NSArray *)r {
    busy = NO; NSDictionary *p = [r objectAtIndex:0]; NSString *err = [r objectAtIndex:1]; id its = [r objectAtIndex:2];
    if (![p count]) { [status release]; status = [([err length] ? err : @"No answer. Try again.") copy]; [self.tableView reloadData]; return; }
    NSArray *legs = [p objectForKey:@"legs"]; NSString *note = [[p objectForKey:@"note"] length] ? [NSString stringWithFormat:@" %@", [p objectForKey:@"note"]] : @"";
    day = [[p objectForKey:@"day"] integerValue]; when = [[p objectForKey:@"when"] integerValue]; arriveBy = [[p objectForKey:@"arriveBy"] boolValue]; express = [[p objectForKey:@"express"] boolValue];
    NSString *whenStr = when < 0 ? (day ? dayName(day) : @"now") : [NSString stringWithFormat:@"%@ %@%@", arriveBy ? @"by" : @"at", [CTData fmtMin:when], day ? [NSString stringWithFormat:@" %@", dayName(day)] : @""];
    NSString *first = [[legs objectAtIndex:0] objectForKey:@"fromName"], *last = [[legs lastObject] objectForKey:@"toName"];
    [status release];
    if (its == [NSNull null]) {   // Caltrain alone: the regular planner shows it
        from = [[[legs objectAtIndex:0] objectForKey:@"from"] integerValue]; to = [[[legs objectAtIndex:0] objectForKey:@"to"] integerValue];
        [self setRoutes:nil title:nil];
        status = [[NSString stringWithFormat:@"Got it: %@ to %@, %@%@.%@", first, last, whenStr, express ? @", express" : @"", note] copy];
        [self search]; return;
    }
    [self setRoutes:its title:[NSString stringWithFormat:@"%@ to %@", first, last]]; [self updateClear];
    status = [([its count] ? [NSString stringWithFormat:@"Got it: %@ to %@, %@.%@", first, last, whenStr, note] : [NSString stringWithFormat:@"%@%@", [err length] ? err : @"No trips found.", note]) copy];
    [self.tableView reloadData];
}
@end

@implementation CTTripDetailViewController
- (id)initWithTrip:(NSDictionary *)t from:(NSInteger)a to:(NSInteger)b base:(NSTimeInterval)midnight { if ((self = [super initWithStyle:UITableViewStylePlain])) { trip = [t retain]; fromIdx = a; toIdx = b; base = midnight; self.title = [NSString stringWithFormat:@"%@ %@", [t objectForKey:@"type"], [t objectForKey:@"n"]]; } return self; }
- (void)dealloc { [trip release]; [super dealloc]; }
- (NSString *)stopName:(NSInteger)i { return stationName([[[[trip objectForKey:@"stops"] objectAtIndex:i] objectAtIndex:0] integerValue]); }
- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 54)] autorelease]; hdr.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1];
    if (toIdx > fromIdx) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeRoundedRect]; b.frame = CGRectMake(10, 8, 300, 38); b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [b setTitle:[NSString stringWithFormat:@"Ring before %@", [self stopName:toIdx]] forState:UIControlStateNormal]; [b setTitleColor:[UIColor colorWithRed:0.80 green:0.10 blue:0.18 alpha:1] forState:UIControlStateNormal]; b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [b addTarget:self action:@selector(ringTo) forControlEvents:UIControlEventTouchUpInside]; [hdr addSubview:b];
    } else {
        UILabel *l = [[[UILabel alloc] initWithFrame:CGRectMake(12, 0, 296, 54)] autorelease]; l.backgroundColor = [UIColor clearColor]; l.numberOfLines = 2; l.font = [UIFont systemFontOfSize:14]; l.textColor = [UIColor colorWithWhite:0.3 alpha:1]; l.textAlignment = UITextAlignmentCenter; l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        l.text = [NSString stringWithFormat:@"Tap your stop. The timer rings %ld min before you get there.", (long)[CTData leadMinutes]]; [hdr addSubview:l];
    }
    self.tableView.tableHeaderView = hdr;
}
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if (fromIdx > 0) [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:fromIdx inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO]; }
- (void)ringTo { [self offer:toIdx]; }
- (void)offer:(NSInteger)i {
    NSDictionary *seg = [CTRoute caltrainTrip:trip from:fromIdx to:i base:base];
    [CTTimer offerSegs:[NSArray arrayWithObject:seg] title:[NSString stringWithFormat:@"%@ to %@", [seg objectForKey:@"label"], [seg objectForKey:@"to"]]];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [[trip objectForKey:@"stops"] count]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"s"];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"s"] autorelease]; }
    NSArray *st = [[trip objectForKey:@"stops"] objectAtIndex:ip.row];
    BOOL in = ip.row >= fromIdx && (toIdx < 0 || ip.row <= toIdx), end = ip.row == fromIdx || ip.row == toIdx;
    c.textLabel.text = stationName([[st objectAtIndex:0] integerValue]); c.detailTextLabel.text = [CTData fmtMin:[[st objectAtIndex:1] integerValue]];
    c.textLabel.font = end ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:17];
    c.textLabel.textColor = in ? [UIColor blackColor] : [UIColor grayColor]; c.detailTextLabel.textColor = in ? green() : [UIColor grayColor];
    c.imageView.image = [CTData badgeForType:[trip objectForKey:@"type"]]; c.imageView.alpha = end ? 1 : 0;
    c.selectionStyle = ip.row > fromIdx ? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; if (ip.row > fromIdx) [self offer:ip.row]; }
@end

@implementation CTRouteViewController
- (id)initWithItinerary:(NSDictionary *)i { if ((self = [super initWithStyle:UITableViewStyleGrouped])) { it = [i retain]; self.title = @"Route"; } return self; }
- (void)dealloc { [it release]; [super dealloc]; }
- (NSArray *)segs { return [it objectForKey:@"segs"]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 56)] autorelease];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeRoundedRect]; b.frame = CGRectMake(10, 12, 300, 40); b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [b setTitle:@"Set a timer for this trip" forState:UIControlStateNormal]; [b setTitleColor:[UIColor colorWithRed:0.80 green:0.10 blue:0.18 alpha:1] forState:UIControlStateNormal]; b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b addTarget:self action:@selector(offerTimer) forControlEvents:UIControlEventTouchUpInside]; [hdr addSubview:b];
    self.tableView.tableHeaderView = hdr;
}
- (void)offerTimer { NSArray *s = [self segs]; [CTTimer offerSegs:s title:[NSString stringWithFormat:@"%@ to %@", [[s objectAtIndex:0] objectForKey:@"from"], [[s lastObject] objectForKey:@"to"]]]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [[self segs] count]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 2; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { NSDictionary *g = [[self segs] objectAtIndex:s]; return [[g objectForKey:@"mode"] isEqualToString:@"caltrain"] ? [NSString stringWithFormat:@"Caltrain %@", [g objectForKey:@"label"]] : [g objectForKey:@"label"]; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    NSArray *segs = [self segs]; NSDictionary *g = [segs objectAtIndex:s];
    if (s + 1 == (NSInteger)[segs count]) return [NSString stringWithFormat:@"%ld min door to door, platform to platform.", (long)floor(([[it objectForKey:@"arrAt"] doubleValue] - [[it objectForKey:@"depAt"] doubleValue]) / 60 + 0.5)];
    NSDictionary *n = [segs objectAtIndex:s + 1]; long wait = (long)floor(([[n objectForKey:@"depAt"] doubleValue] - [[g objectForKey:@"arrAt"] doubleValue]) / 60 + 0.5);
    return [[n objectForKey:@"from"] isEqualToString:[g objectForKey:@"to"]] ? [NSString stringWithFormat:@"Change here. %ld min to make it.", wait] : [NSString stringWithFormat:@"Get to %@: %ld min.", [n objectForKey:@"from"], wait];
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease];
    NSDictionary *g = [[self segs] objectAtIndex:ip.section]; BOOL caltrain = [[g objectForKey:@"mode"] isEqualToString:@"caltrain"];
    c.textLabel.text = [NSString stringWithFormat:@"%@ %@", ip.row == 0 ? @"Board at" : @"Off at", [g objectForKey:ip.row == 0 ? @"from" : @"to"]]; c.textLabel.font = [UIFont systemFontOfSize:16]; c.textLabel.adjustsFontSizeToFitWidth = YES; c.textLabel.minimumFontSize = 11;
    c.detailTextLabel.text = [CTData fmtTime:[[g objectForKey:ip.row == 0 ? @"depAt" : @"arrAt"] doubleValue]]; c.detailTextLabel.textColor = green();
    c.selectionStyle = caltrain ? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone; c.accessoryType = caltrain ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *g = [[self segs] objectAtIndex:ip.section]; if (![[g objectForKey:@"mode"] isEqualToString:@"caltrain"]) return;
    NSDictionary *t = [g objectForKey:@"trip"]; NSInteger fi = [[g objectForKey:@"fromIdx"] integerValue];
    NSTimeInterval base = [[g objectForKey:@"depAt"] doubleValue] - [[[[t objectForKey:@"stops"] objectAtIndex:fi] objectAtIndex:1] integerValue] * 60;
    CTTripDetailViewController *v = [[CTTripDetailViewController alloc] initWithTrip:t from:fi to:[[g objectForKey:@"toIdx"] integerValue] base:base]; [self.navigationController pushViewController:v animated:YES]; [v release];
}
@end

// The egg timer's own screen: the train you're on (the one that just left your board station, or the next one), and the stops ahead with
// how far each is. One tap rings before it.
@implementation CTTimerPickViewController
static NSInteger shownMin(NSDictionary *d, NSDictionary *live) { NSDictionary *lv = [live objectForKey:[[d objectForKey:@"trip"] objectForKey:@"n"]]; return lv ? [[lv objectForKey:@"expected"] integerValue] : [[d objectForKey:@"dep"] integerValue]; }
- (id)initWithStation:(NSInteger)s dir:(NSInteger)d live:(NSDictionary *)lv {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        station = s; dir = d; live = [lv retain]; self.title = @"Timer"; self.hidesBottomBarWhenPushed = YES;
        NSInteger now = [CTData minutesNow]; NSDictionary *last = nil, *next = nil;
        for (NSDictionary *x in [CTData departuresFrom:s dir:d date:[NSDate date] after:now - 30]) {
            NSInteger m = shownMin(x, live);
            if (m <= now) { if (!last || m >= shownMin(last, live)) last = x; }
            else if (m - now <= 60 && (!next || m < shownMin(next, live))) next = x;
        }
        NSMutableArray *c = [NSMutableArray array]; if (last) [c addObject:last]; if (next) [c addObject:next];
        cands = [c retain];
        pick = last && (now - shownMin(last, live) <= 10 || !next) ? 0 : [c count] - 1;   // just left: you're probably on it
    }
    return self;
}
- (void)dealloc { [cands release]; [live release]; [stops release]; [seg release]; [info release]; [super dealloc]; }
- (BOOL)hasTrain { return [cands count] > 0; }
- (NSDictionary *)dep { return [cands objectAtIndex:pick]; }
- (NSInteger)late { NSDictionary *d = [self dep], *lv = [live objectForKey:[[d objectForKey:@"trip"] objectForKey:@"n"]]; return lv ? [[lv objectForKey:@"expected"] integerValue] - [[d objectForKey:@"dep"] integerValue] : 0; }
- (NSTimeInterval)base {
    NSDictionary *d = [self dep]; NSInteger raw = [[[[[d objectForKey:@"trip"] objectForKey:@"stops"] objectAtIndex:[[d objectForKey:@"idx"] integerValue]] objectAtIndex:1] integerValue];
    return [CTData midnightPlus:0] + ([[d objectForKey:@"dep"] integerValue] - raw) * 60;
}
- (NSTimeInterval)arrivalAt:(NSInteger)i { return [self base] + ([[[[[[self dep] objectForKey:@"trip"] objectForKey:@"stops"] objectAtIndex:i] objectAtIndex:2] integerValue] + [self late]) * 60; }
- (void)load {   // stops still ahead of this train
    NSDictionary *d = [self dep], *t = [d objectForKey:@"trip"]; NSInteger idx = [[d objectForKey:@"idx"] integerValue]; NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray *a = [NSMutableArray array];
    for (NSInteger i = idx + 1; i < (NSInteger)[[t objectForKey:@"stops"] count]; i++) if ([self arrivalAt:i] > now + 30) [a addObject:[NSNumber numberWithInteger:i]];
    [stops release]; stops = [a retain];
    NSInteger m = shownMin(d, live) - [CTData minutesNow], late = [self late];
    info.text = [NSString stringWithFormat:@"%@ %@ to %@, %@ %@ %@%@", [t objectForKey:@"type"], [t objectForKey:@"n"], shortHead([t objectForKey:@"head"]), m <= 0 ? @"left" : @"leaves", stationName(station), m <= 0 ? [NSString stringWithFormat:@"%ld min ago", (long)-m] : [NSString stringWithFormat:@"in %ld min", (long)m],
        late >= 2 ? [NSString stringWithFormat:@", %ld late", (long)late] : @""];
    [self.tableView reloadData];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor blackColor]; self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    BOOL two = [cands count] > 1; CGFloat h = two ? 100 : 62;
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, h)] autorelease]; hdr.backgroundColor = [UIColor blackColor];
    UILabel *q = [[[UILabel alloc] initWithFrame:CGRectMake(12, 10, 296, 22)] autorelease]; q.backgroundColor = [UIColor clearColor]; q.font = boardFont(17); q.textColor = amber(1); q.text = @"WHERE ARE YOU GETTING OFF?"; q.adjustsFontSizeToFitWidth = YES; q.autoresizingMask = UIViewAutoresizingFlexibleWidth; [hdr addSubview:q];
    if (two) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *d in cands) { NSInteger m = shownMin(d, live); [items addObject:[NSString stringWithFormat:@"%@ the %@", m <= [CTData minutesNow] ? @"On" : @"Boarding", [[CTData fmtMin:m] stringByReplacingOccurrencesOfString:@" " withString:@""]]]; }
        seg = [[UISegmentedControl alloc] initWithItems:items]; seg.segmentedControlStyle = UISegmentedControlStyleBar; seg.tintColor = [UIColor colorWithWhite:0.25 alpha:1];
        seg.frame = CGRectMake(10, 38, 300, 30); seg.autoresizingMask = UIViewAutoresizingFlexibleWidth; seg.selectedSegmentIndex = pick; [seg addTarget:self action:@selector(picked) forControlEvents:UIControlEventValueChanged]; [hdr addSubview:seg];
    }
    info = [[UILabel alloc] initWithFrame:CGRectMake(12, h - 26, 296, 18)]; info.backgroundColor = [UIColor clearColor]; info.font = [UIFont systemFontOfSize:13]; info.textColor = [UIColor colorWithWhite:0.6 alpha:1]; info.adjustsFontSizeToFitWidth = YES; info.minimumFontSize = 10; info.autoresizingMask = UIViewAutoresizingFlexibleWidth; [hdr addSubview:info];
    self.tableView.tableHeaderView = hdr;
    UILabel *foot = [[[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 50)] autorelease]; foot.backgroundColor = [UIColor blackColor]; foot.textColor = [UIColor colorWithWhite:0.5 alpha:1]; foot.font = [UIFont systemFontOfSize:13]; foot.numberOfLines = 2; foot.textAlignment = UITextAlignmentCenter;
    foot.text = [NSString stringWithFormat:@"Rings %ld min before you get there, even with the screen locked.", (long)[CTData leadMinutes]]; self.tableView.tableFooterView = foot;
    [self load];
}
- (void)picked { pick = seg.selectedSegmentIndex; [self load]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return MAX(1, (NSInteger)[stops count]); }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 52; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip { c.backgroundColor = [UIColor blackColor]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"p"];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"p"] autorelease]; c.textLabel.font = [UIFont boldSystemFontOfSize:19]; c.textLabel.backgroundColor = [UIColor clearColor]; c.detailTextLabel.backgroundColor = [UIColor clearColor]; c.detailTextLabel.font = boardFont(17);
        UIView *sel = [[[UIView alloc] init] autorelease]; sel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1]; c.selectedBackgroundView = sel; }
    if (![stops count]) { c.textLabel.text = @"No stops left"; c.textLabel.textColor = [UIColor grayColor]; c.detailTextLabel.text = nil; c.selectionStyle = UITableViewCellSelectionStyleNone; return c; }
    NSInteger i = [[stops objectAtIndex:ip.row] integerValue]; NSTimeInterval arr = [self arrivalAt:i];
    long m = (long)ceil((arr - [[NSDate date] timeIntervalSince1970]) / 60);
    c.textLabel.text = stationName([[[[[[self dep] objectForKey:@"trip"] objectForKey:@"stops"] objectAtIndex:i] objectAtIndex:0] integerValue]); c.textLabel.textColor = [UIColor whiteColor];
    c.detailTextLabel.text = m < 60 ? [NSString stringWithFormat:@"%ld MIN", m] : [NSString stringWithFormat:@"%ldH %ldM", m / 60, m % 60]; c.detailTextLabel.textColor = amber(1);
    c.selectionStyle = UITableViewCellSelectionStyleBlue;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; if (![stops count]) return;
    NSDictionary *d = [self dep]; NSInteger i = [[stops objectAtIndex:ip.row] integerValue], late = [self late];
    NSMutableDictionary *s = [[[CTRoute caltrainTrip:[d objectForKey:@"trip"] from:[[d objectForKey:@"idx"] integerValue] to:i base:[self base]] mutableCopy] autorelease];
    [s setObject:[NSNumber numberWithDouble:[[s objectForKey:@"depAt"] doubleValue] + late * 60] forKey:@"depAt"]; [s setObject:[NSNumber numberWithDouble:[[s objectForKey:@"arrAt"] doubleValue] + late * 60] forKey:@"arrAt"];
    NSMutableArray *rings = [NSMutableArray array];   // start from the delay the board already knows; 511 keeps it current from here
    for (NSDictionary *r in [CTRoute ringsFor:[NSArray arrayWithObject:s] leave:NO]) {
        NSMutableDictionary *m = [[r mutableCopy] autorelease];
        if ([m objectForKey:@"base"]) { [m setObject:[NSNumber numberWithDouble:[[m objectForKey:@"base"] doubleValue] - late * 60] forKey:@"base"]; [m setObject:[NSNumber numberWithInteger:late] forKey:@"late"]; }
        [rings addObject:m];
    }
    NSString *title = [NSString stringWithFormat:@"%@ to %@", [s objectForKey:@"label"], [s objectForKey:@"to"]];
    UINavigationController *nav = self.navigationController; [[self retain] autorelease];
    [nav popViewControllerAnimated:NO];   // back to the board underneath the timer
    [CTTimer startTitle:title rings:rings show:YES];
}
@end
