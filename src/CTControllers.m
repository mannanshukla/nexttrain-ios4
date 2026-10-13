#import "CTControllers.h"
#import "CTData.h"
#import "CTLive.h"
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
static UIViewController *settingsModal(UIViewController *from) { CTSettingsViewController *s = [[[CTSettingsViewController alloc] init] autorelease]; UINavigationController *n = [[[UINavigationController alloc] initWithRootViewController:s] autorelease]; n.navigationBar.tintColor = from.navigationController.navigationBar.tintColor; [from presentModalViewController:n animated:YES]; return s; }

@implementation CTDeparturesViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Caltrain"; self.tabBarItem.title = @"Caltrain"; self.navigationItem.titleView = logoTitle(@"logo-caltrain.png"); station = [CTData homeStation]; dir = [CTData homeDir];
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Settings" style:UIBarButtonItemStyleBordered target:self action:@selector(openSettings)] autorelease];
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshLive)] autorelease];
    }
    return self;
}
- (void)dealloc { [deps release]; [live release]; [liveStatus release]; [alerts release]; [dirSeg release]; [stationButton release]; [sheetDep release]; [runAlert release]; [super dealloc]; }
- (void)openSettings { settingsModal(self); }
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
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; if ([CTData homeStation] != station) { station = [CTData homeStation]; [live release]; live = nil; } [self reload]; }
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:@"ct_test_pick"]) { [d removeObjectForKey:@"ct_test_pick"]; [d synchronize]; [self pickStation]; }
    if ([d boolForKey:@"ct_test_run"]) { [d removeObjectForKey:@"ct_test_run"]; [d synchronize]; if ([deps count]) { [sheetDep release]; sheetDep = [[deps objectAtIndex:0] retain]; sheetNext = [deps count] > 1 ? [self minutesFor:[deps objectAtIndex:1]] : 0; [self performSelector:@selector(fakeRun) withObject:nil afterDelay:12]; } }
    if ([[CTData token] length] && [[NSDate date] timeIntervalSince1970] - lastFetch > 90) [self refreshLive];
}
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [[CTDrum shared] hide]; }
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
- (void)fakeRun { [self actionSheet:nil clickedButtonAtIndex:0]; }
- (void)showStops:(NSDictionary *)d { CTTripDetailViewController *v = [[CTTripDetailViewController alloc] initWithTrip:[d objectForKey:@"trip"] from:[[d objectForKey:@"idx"] integerValue] to:-1]; [self.navigationController pushViewController:v animated:YES]; [v release]; }
- (NSInteger)minutesFor:(NSDictionary *)d { NSDictionary *lv = [live objectForKey:[[d objectForKey:@"trip"] objectForKey:@"n"]]; NSInteger shown = lv ? [[lv objectForKey:@"expected"] integerValue] : [[d objectForKey:@"dep"] integerValue]; return shown - [CTData minutesNow]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; if ([self isAlertSection:ip.section] || ![deps count]) return;
    NSDictionary *d = [deps objectAtIndex:ip.row]; NSInteger mins = [self minutesFor:d];
    if (mins <= 10 && [[CTData apiKey] length]) {
        [sheetDep release]; sheetDep = [d retain]; sheetNext = ip.row + 1 < (NSInteger)[deps count] ? [self minutesFor:[deps objectAtIndex:ip.row + 1]] : 0;
        UIActionSheet *s = [[[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"%@ %@ leaves in %ld min", [[d objectForKey:@"trip"] objectForKey:@"type"], [[d objectForKey:@"trip"] objectForKey:@"n"], (long)mins] delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Run for it?", @"Stop list", nil] autorelease];
        [s showFromTabBar:self.tabBarController.tabBar]; return;
    }
    [self showStops:d];
}
- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (!sheetDep) return;
    if (i == 1) { [self showStops:sheetDep]; return; }
    if (i != 0) return;
    NSInteger mins = [self minutesFor:sheetDep];
    [self performSelectorInBackground:@selector(askLaya:) withObject:[NSArray arrayWithObjects:[NSNumber numberWithInteger:mins], [NSNumber numberWithInteger:sheetNext], nil]];
    UIAlertView *a = [[[UIAlertView alloc] initWithTitle:@"Asking Laya..." message:[NSString stringWithFormat:@"%ld min to departure, %ld min walk to the platform.", (long)mins, (long)[CTData walkMinutes]] delegate:nil cancelButtonTitle:nil otherButtonTitles:nil] autorelease];
    [a show]; [runAlert release]; runAlert = [a retain];
}
- (void)askLaya:(NSArray *)a {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *err = nil;
    NSDictionary *r = [CTAI runForTrainIn:[[a objectAtIndex:0] integerValue] walk:[CTData walkMinutes] next:[[a objectAtIndex:1] integerValue] error:&err];
    [self performSelectorOnMainThread:@selector(layaSaid:) withObject:[NSArray arrayWithObjects:(r ?: [NSDictionary dictionary]), (err ?: @""), a, nil] waitUntilDone:NO];
    [p release];
}
- (void)layaSaid:(NSArray *)r {
    [runAlert dismissWithClickedButtonIndex:0 animated:NO]; [runAlert release]; runAlert = nil;
    NSDictionary *ans = [r objectAtIndex:0]; NSString *err = [r objectAtIndex:1]; NSInteger mins = [[[r objectAtIndex:2] objectAtIndex:0] integerValue], next = [[[r objectAtIndex:2] objectAtIndex:1] integerValue];
    NSString *title, *msg;
    if ([err length]) { title = @"No answer"; msg = err; }
    else {
        double p = [[ans objectForKey:@"p"] doubleValue], conf = [[ans objectForKey:@"confidence"] doubleValue];
        title = p >= 0.65 ? @"Run." : p >= 0.4 ? @"Jog. It's tight." : @"Let it go.";
        NSString *nextStr = next > 0 ? [NSString stringWithFormat:@" The next one is in %ld min.", (long)next] : @"";
        msg = [NSString stringWithFormat:@"%@%@\n\nLaya says %d%% yes, %d%% sure.", p >= 0.65 ? [NSString stringWithFormat:@"%ld minutes is enough if you move now.", (long)mins] : p >= 0.4 ? @"You might make it, you might not." : @"Not worth the sprint.", nextStr, (int)(p * 100 + 0.5), (int)(conf * 100 + 0.5)];
    }
    [[[[UIAlertView alloc] initWithTitle:title message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
}
@end

@implementation CTTripViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) { self.title = @"Trip"; self.tabBarItem.title = @"Trip"; from = [CTData homeStation]; to = [CTData stationNamed:[CTData homeStation] == [CTData stationNamed:@"san francisco"] ? @"palo alto" : @"san francisco"]; when = -1; }
    return self;
}
- (void)dealloc { [trips release]; [status release]; [ask release]; [mode release]; [alerts release]; [super dealloc]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    ask = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 260, 30)]; ask.placeholder = @"\"sf to palo alto after work\""; ask.font = [UIFont systemFontOfSize:16]; ask.delegate = self; ask.returnKeyType = UIReturnKeyGo; ask.clearButtonMode = UITextFieldViewModeWhileEditing; ask.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter; ask.autocapitalizationType = UITextAutocapitalizationTypeNone; ask.autocorrectionType = UITextAutocorrectionTypeNo;
    mode = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Leave at", @"Arrive by", nil]]; mode.segmentedControlStyle = UISegmentedControlStyleBar; mode.tintColor = [UIColor colorWithWhite:0.35 alpha:1]; mode.selectedSegmentIndex = 0;
    [mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [self search];
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults]; NSString *q = [d stringForKey:@"ct_test_ask"];
    if (q) { [d removeObjectForKey:@"ct_test_ask"]; [d synchronize]; ask.text = q; [self runAsk]; }
    if ([d objectForKey:@"ct_scroll"]) { [self.tableView setContentOffset:CGPointMake(0, [d floatForKey:@"ct_scroll"]) animated:NO]; [d removeObjectForKey:@"ct_scroll"]; [d synchronize]; }
    if ([d boolForKey:@"ct_test_detail"] && [trips count]) { [d removeObjectForKey:@"ct_test_detail"]; [d synchronize]; [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:[self resultsSection]]]; }
}
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [[CTDrum shared] hide]; }
- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    [alerts release]; alerts = [[CTLive cachedAlerts] length] ? [[CTLive cachedAlerts] copy] : nil; [self.tableView reloadData];
    if ([[CTData token] length] && [CTLive alertsAge] > 600 && !alertsBusy) { alertsBusy = YES; [self performSelectorInBackground:@selector(fetchAlerts) withObject:nil]; }
}
- (void)fetchAlerts { NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *t = [CTLive alertsWithError:NULL]; [self performSelectorOnMainThread:@selector(gotAlerts:) withObject:(t ?: @"") waitUntilDone:NO]; [p release]; }
- (void)gotAlerts:(NSString *)t { alertsBusy = NO; [alerts release]; alerts = [t length] ? [t copy] : nil; [self.tableView reloadData]; }
- (void)modeChanged { arriveBy = mode.selectedSegmentIndex == 1; if (arriveBy && when < 0) when = ((([CTData minutesNow] + 60) / 5) * 5) % 1440; [self search]; }
- (void)search {
    NSInteger leave = arriveBy ? -1 : (when < 0 ? [CTData minutesNow] : when), by = arriveBy ? when : -1;
    [trips release]; trips = [[CTData tripsFrom:from to:to date:[NSDate date] leaveAfter:leave arriveBy:by] retain];
    [self.tableView reloadData];
}
- (void)swap { NSInteger t = from; from = to; to = t; [self search]; }
- (NSInteger)resultsSection { return alerts ? 3 : 2; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return alerts ? 4 : 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 1 : s == 1 ? 4 : s == [self resultsSection] ? MAX(1, MIN(8, (NSInteger)[trips count])) : 1; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return s == 0 ? @"Just say it" : s == 1 ? nil : s == [self resultsSection] ? [NSString stringWithFormat:@"%@ to %@", stationName(from), stationName(to)] : @"Caltrain alerts"; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return status ?: @"OpenRelay reads it and fills in the trip below.";
    if (s == [self resultsSection] && [trips count]) { double fare = [CTData fareFrom:from to:to]; return fare > 0 ? [NSString stringWithFormat:@"Adult Clipper fare $%.2f. Times from the Caltrain timetable, valid through %@.", fare, [CTData feedEnd]] : nil; }
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) { UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; ask.frame = CGRectMake(10, 7, c.contentView.bounds.size.width - 20, 30); ask.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:ask]; return c; }
    if (ip.section == 1) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (ip.row == 0) { c.textLabel.text = @"From"; c.detailTextLabel.text = stationName(from); }
        else if (ip.row == 1) { c.textLabel.text = @"To"; c.detailTextLabel.text = stationName(to); }
        else if (ip.row == 2) { c.accessoryType = UITableViewCellAccessoryNone; c.selectionStyle = UITableViewCellSelectionStyleNone; mode.frame = CGRectMake(8, 7, c.contentView.bounds.size.width - 16, 30); mode.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:mode]; }
        else { c.textLabel.text = arriveBy ? @"Arrive by" : @"Leave at"; c.detailTextLabel.text = when < 0 ? @"Now" : [CTData fmtMin:when]; }
        return c;
    }
    if (alerts && ip.section == 2) { UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; c.textLabel.text = alerts; c.textLabel.numberOfLines = 0; c.textLabel.font = [UIFont systemFontOfSize:14]; c.textLabel.textColor = [UIColor colorWithRed:0.55 green:0.05 blue:0.08 alpha:1]; c.textLabel.lineBreakMode = UILineBreakModeWordWrap; return c; }
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"t"];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"t"] autorelease]; c.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1]; c.textLabel.font = [UIFont boldSystemFontOfSize:17]; }
    if (![trips count]) { c.textLabel.text = @"No trains found"; c.textLabel.textColor = [UIColor grayColor]; c.detailTextLabel.text = arriveBy ? @"Nothing arrives that early. Try a later time." : @"Nothing later today. Try an earlier time or swap the direction."; c.imageView.image = nil; c.accessoryType = UITableViewCellAccessoryNone; c.selectionStyle = UITableViewCellSelectionStyleNone; return c; }
    NSDictionary *d = [trips objectAtIndex:ip.row]; NSDictionary *t = [d objectForKey:@"trip"];
    NSInteger dep = [[d objectForKey:@"dep"] integerValue], arr = [[d objectForKey:@"arr"] integerValue], stops = [[d objectForKey:@"toIdx"] integerValue] - [[d objectForKey:@"fromIdx"] integerValue] - 1;
    c.textLabel.text = [NSString stringWithFormat:@"%@  →  %@", [CTData fmtMin:dep], [CTData fmtMin:arr]]; c.textLabel.textColor = [UIColor blackColor];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%ld min · %@ %@ · %ld stop%@", (long)(arr - dep), [t objectForKey:@"type"], [t objectForKey:@"n"], (long)stops, stops == 1 ? @"" : @"s"];
    c.detailTextLabel.text = [c.detailTextLabel.text stringByReplacingOccurrencesOfString:@" between" withString:@""];
    c.imageView.image = [CTData badgeForType:[t objectForKey:@"type"]]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleBlue;
    return c;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return (alerts && ip.section == 2) ? MAX(44, [alerts sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(270, 600) lineBreakMode:UILineBreakModeWordWrap].height + 20) : ip.section == [self resultsSection] ? 56 : 44; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; [ask resignFirstResponder];
    UIView *host = self.tabBarController.view;
    if (ip.section == 1 && ip.row == 0) [[CTDrum shared] showInView:host title:@"From" rows:CTStationRows() selected:from onChange:^(NSInteger r) { from = r; [self search]; } onDone:nil];
    else if (ip.section == 1 && ip.row == 1) [[CTDrum shared] showInView:host title:@"To" rows:CTStationRows() selected:to onChange:^(NSInteger r) { to = r; [self search]; } onDone:nil];
    else if (ip.section == 1 && ip.row == 3) [[CTDrum shared] showInView:host title:arriveBy ? @"Arrive by" : @"Leave at" rows:CTTimeRows() selected:(when < 0 ? [CTData minutesNow] : when) / 5 onChange:^(NSInteger r) { when = r * 5; [self search]; } onDone:nil];
    else if (ip.section == [self resultsSection] && [trips count]) { NSDictionary *d = [trips objectAtIndex:ip.row]; CTTripDetailViewController *v = [[CTTripDetailViewController alloc] initWithTrip:[d objectForKey:@"trip"] from:[[d objectForKey:@"fromIdx"] integerValue] to:[[d objectForKey:@"toIdx"] integerValue]]; [self.navigationController pushViewController:v animated:YES]; [v release]; }
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; [self runAsk]; return YES; }
- (void)runAsk {
    NSString *q = [ask.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (![q length] || busy) return;
    busy = YES; [status release]; status = @"Asking OpenRelay..."; [self.tableView reloadData];
    [self performSelectorInBackground:@selector(askWork:) withObject:q];
}
- (void)askWork:(NSString *)q { NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *err = nil; NSDictionary *r = [CTAI parseAsk:q error:&err]; [self performSelectorOnMainThread:@selector(asked:) withObject:[NSArray arrayWithObjects:(r ?: [NSDictionary dictionary]), (err ?: @""), nil] waitUntilDone:NO]; [p release]; }
- (void)asked:(NSArray *)r {
    busy = NO; NSDictionary *p = [r objectAtIndex:0]; NSString *err = [r objectAtIndex:1];
    if ([err length]) { [status release]; status = [err copy]; [self.tableView reloadData]; return; }
    from = [[p objectForKey:@"from"] integerValue]; to = [[p objectForKey:@"to"] integerValue]; when = [[p objectForKey:@"when"] integerValue]; arriveBy = [[p objectForKey:@"arriveBy"] boolValue];
    if (when >= 0 && when < 12 * 60 && when + 60 < [CTData minutesNow]) when += 12 * 60;   // "by 6" at 8 AM means 6 PM mode.selectedSegmentIndex = arriveBy ? 1 : 0;
    [status release]; status = [[NSString stringWithFormat:@"Got it: %@ to %@, %@ %@.", stationName(from), stationName(to), arriveBy ? @"arrive by" : @"leave at", when < 0 ? @"now" : [CTData fmtMin:when]] copy];
    [self search];
}
@end

@implementation CTTripDetailViewController
- (id)initWithTrip:(NSDictionary *)t from:(NSInteger)a to:(NSInteger)b { if ((self = [super initWithStyle:UITableViewStylePlain])) { trip = [t retain]; fromIdx = a; toIdx = b; self.title = [NSString stringWithFormat:@"%@ %@", [t objectForKey:@"type"], [t objectForKey:@"n"]]; } return self; }
- (void)dealloc { [trip release]; [super dealloc]; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if (fromIdx > 0) [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:fromIdx inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [[trip objectForKey:@"stops"] count]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"s"];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"s"] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; }
    NSArray *st = [[trip objectForKey:@"stops"] objectAtIndex:ip.row];
    BOOL in = ip.row >= fromIdx && (toIdx < 0 || ip.row <= toIdx), end = ip.row == fromIdx || ip.row == toIdx;
    c.textLabel.text = stationName([[st objectAtIndex:0] integerValue]); c.detailTextLabel.text = [CTData fmtMin:[[st objectAtIndex:1] integerValue]];
    c.textLabel.font = end ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:17];
    c.textLabel.textColor = in ? [UIColor blackColor] : [UIColor grayColor]; c.detailTextLabel.textColor = in ? green() : [UIColor grayColor];
    c.imageView.image = [CTData badgeForType:[trip objectForKey:@"type"]]; c.imageView.alpha = end ? 1 : 0;
    return c;
}
@end

@implementation CTSettingsViewController
- (id)init { if ((self = [super initWithStyle:UITableViewStyleGrouped])) { self.title = @"Settings"; self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)] autorelease]; } return self; }
- (void)dealloc { [tokenField release]; [keyField release]; [super dealloc]; }
- (UITextField *)field:(NSString *)ph text:(NSString *)t { UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 260, 30)]; f.placeholder = ph; f.text = t; f.font = [UIFont systemFontOfSize:15]; f.delegate = self; f.returnKeyType = UIReturnKeyDone; f.clearButtonMode = UITextFieldViewModeWhileEditing; f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; return f; }
- (void)viewDidLoad { [super viewDidLoad]; tokenField = [self field:@"xxxxxxxx-xxxx-..." text:[CTData token]]; keyField = [self field:@"or_..." text:[CTData apiKey]]; keyField.secureTextEntry = YES; }
- (void)save { [CTData setToken:[tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]; [CTData setApiKey:[keyField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]; }
- (void)done { [self save]; [self dismissModalViewControllerAnimated:YES]; }
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)tf { [self save]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return [[NSArray arrayWithObjects:@"Home station", @"511.org token", @"OpenRelay API key", @"About", nil] objectAtIndex:s]; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return s == 0 ? @"Walk time feeds \"Run for it?\" on the board: tap a train leaving in 10 minutes or less and Laya decides." : s == 1 ? @"Free at 511.org/open-data/token. Turns on live predictions and service alerts. 511 allows 60 requests an hour, so the app only refreshes when you ask." : s == 2 ? @"Only used for the \"just say it\" box in Trip." : s == 3 ? [NSString stringWithFormat:@"Timetable: Caltrain GTFS, %@, valid through %@. Real-time by 511 SF Bay.", [CTData feedVersion], [CTData feedEnd]] : nil; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; CGFloat w = c.contentView.bounds.size.width;
    if (ip.section == 0 && ip.row == 1) { c.textLabel.text = @"Walk to platform"; c.detailTextLabel.text = [NSString stringWithFormat:@"%ld min", (long)[CTData walkMinutes]]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleBlue; }
    else if (ip.section == 0) { c.textLabel.text = @"Station"; c.detailTextLabel.text = stationName([CTData homeStation]); c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleBlue; }
    else if (ip.section == 1) { tokenField.frame = CGRectMake(10, 7, w - 20, 30); tokenField.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:tokenField]; }
    else if (ip.section == 2) { keyField.frame = CGRectMake(10, 7, w - 20, 30); keyField.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:keyField]; }
    else { c.textLabel.text = @"Next Train"; c.detailTextLabel.text = @"1.0"; }
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; [self.view endEditing:YES]; if (ip.section != 0) return;
    if (ip.row == 1) { NSMutableArray *rows = [NSMutableArray array]; for (int i = 1; i <= 15; i++) [rows addObject:[NSString stringWithFormat:@"%d min", i]];
        [[CTDrum shared] showInView:self.navigationController.view title:@"Walk to the platform" rows:rows selected:[CTData walkMinutes] - 1 onChange:^(NSInteger r) { [CTData setWalkMinutes:r + 1]; [tv reloadRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationNone]; } onDone:nil]; return; }
    [[CTDrum shared] showInView:self.navigationController.view title:@"Home station" rows:CTStationRows() selected:[CTData homeStation] onChange:^(NSInteger r) { [CTData setHomeStation:r]; [tv reloadRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationNone]; } onDone:nil];
}
@end

#define ROW_H 34
@implementation CTLineView
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor whiteColor]; } return self; }
- (void)dealloc { [express release]; [super dealloc]; }
- (void)setExpress:(NSSet *)e { [express release]; express = [e retain]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext(); NSArray *st = [CTData stations]; NSUInteger n = [st count];
    CGFloat lx = 44, top = 30, w = self.bounds.size.width; NSInteger home = [CTData homeStation];
    // zone bands
    NSString *lastZone = nil; int zoneNo = 0; CGFloat bandStart = top - ROW_H / 2;
    for (NSUInteger i = 0; i <= n; i++) {
        NSString *z = i < n ? [[st objectAtIndex:i] objectForKey:@"zone"] : nil;
        if (i == n || ![z isEqualToString:lastZone]) {
            if (lastZone) { CGFloat y = top + (i - 1) * ROW_H + ROW_H / 2; [(zoneNo % 2 ? [UIColor colorWithWhite:0.96 alpha:1] : [UIColor whiteColor]) set]; CGContextFillRect(c, CGRectMake(0, bandStart, w, y - bandStart)); [[UIColor colorWithWhite:0.6 alpha:1] set]; [[NSString stringWithFormat:@"ZONE %d", zoneNo] drawInRect:CGRectMake(w - 70, bandStart + 4, 60, 12) withFont:[UIFont boldSystemFontOfSize:9] lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentRight]; bandStart = y; }
            lastZone = z; zoneNo++;
        }
    }
    // the line
    [green() set]; CGContextSetLineWidth(c, 8); CGContextSetLineCap(c, kCGLineCapRound);
    CGContextMoveToPoint(c, lx, top); CGContextAddLineToPoint(c, lx, top + (n - 1) * ROW_H); CGContextStrokePath(c);
    for (NSUInteger i = 0; i < n; i++) {
        CGFloat y = top + i * ROW_H; BOOL ex = [express containsObject:[NSNumber numberWithInteger:i]], isHome = (NSInteger)i == home;
        CGRect d = CGRectMake(lx - (ex ? 8 : 6), y - (ex ? 8 : 6), ex ? 16 : 12, ex ? 16 : 12);
        [[UIColor whiteColor] set]; CGContextFillEllipseInRect(c, d);
        [green() set]; CGContextSetLineWidth(c, ex ? 3.5 : 2.5); CGContextStrokeEllipseInRect(c, d);
        if (isHome) { [green() set]; CGContextFillEllipseInRect(c, CGRectInset(d, 4, 4)); }
        [(isHome ? green() : [UIColor blackColor]) set];
        [[[st objectAtIndex:i] objectForKey:@"name"] drawInRect:CGRectMake(lx + 22, y - 10, w - lx - 100, 20) withFont:isHome || ex ? [UIFont boldSystemFontOfSize:16] : [UIFont systemFontOfSize:16] lineBreakMode:UILineBreakModeTailTruncation alignment:UITextAlignmentLeft];
    }
    // ends
    [[UIColor colorWithWhite:0.5 alpha:1] set];
    [@"NORTH" drawInRect:CGRectMake(lx - 30, 4, 60, 12) withFont:[UIFont boldSystemFontOfSize:9] lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentCenter];
    [@"SOUTH" drawInRect:CGRectMake(lx - 30, top + (n - 1) * ROW_H + 14, 60, 12) withFont:[UIFont boldSystemFontOfSize:9] lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentCenter];
}
+ (CGFloat)height { return 30 + ([[CTData stations] count] - 1) * ROW_H + 40; }
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)e {
    CGPoint p = [[touches anyObject] locationInView:self]; NSInteger i = (NSInteger)floorf((p.y - 30 + ROW_H / 2) / ROW_H);
    if (i >= 0 && i < (NSInteger)[[CTData stations] count] && onPick) onPick(i);
}
- (void)setOnPick:(void (^)(NSInteger))b { [onPick release]; onPick = [b copy]; }
@end

@implementation CTLineViewController
- (id)init { if ((self = [super initWithNibName:nil bundle:nil])) { self.title = @"Line"; self.tabBarItem.title = @"Line"; } return self; }
- (void)loadView {
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]]; sv.backgroundColor = [UIColor whiteColor]; sv.alwaysBounceVertical = YES;
    CTLineView *lv = [[[CTLineView alloc] initWithFrame:CGRectMake(0, 0, sv.bounds.size.width, [CTLineView height])] autorelease];
    NSMutableSet *ex = [NSMutableSet set];
    for (NSDictionary *t in [[CTData feed] objectForKey:@"trips"]) if ([[t objectForKey:@"type"] isEqualToString:@"Express"]) for (NSArray *s in [t objectForKey:@"stops"]) [ex addObject:[NSNumber numberWithInteger:[[s objectAtIndex:0] integerValue]]];
    [lv setExpress:ex];
    [lv setOnPick:^(NSInteger i) { [CTData setHomeStation:i]; [lv setNeedsDisplay]; self.tabBarController.selectedIndex = 0; }];
    [sv addSubview:lv]; sv.contentSize = CGSizeMake(sv.bounds.size.width, lv.bounds.size.height);
    self.view = sv; [sv release];
    UILabel *legend = [[[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 30)] autorelease]; legend.text = @"Bold ring = Express stop. Tap a station."; legend.font = [UIFont systemFontOfSize:11]; legend.textColor = [UIColor whiteColor]; legend.backgroundColor = [UIColor clearColor]; legend.textAlignment = UITextAlignmentCenter;
    self.navigationItem.titleView = legend;
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [[self.view.subviews objectAtIndex:0] setNeedsDisplay]; }
@end
