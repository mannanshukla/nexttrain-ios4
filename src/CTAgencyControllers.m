#import "CTAgencyControllers.h"
#import "CTMap.h"
#import "CTAgencies.h"
#import "CTData.h"
#import "CTViews.h"
#import <QuartzCore/QuartzCore.h>


static UIView *logoTitle(NSString *png) {   // full-color agency mark on a white pill, for the nav bar
    UIImage *img = [UIImage imageNamed:png]; CGFloat h = 24, w = img.size.width * h / img.size.height;
    UIView *pill = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, w + 20, 32)] autorelease]; pill.backgroundColor = [UIColor whiteColor]; pill.layer.cornerRadius = 7;
    UIImageView *iv = [[[UIImageView alloc] initWithImage:img] autorelease]; iv.frame = CGRectMake(10, 4, w, h); iv.contentMode = UIViewContentModeScaleAspectFit; [pill addSubview:iv];
    return pill;
}
static UIColor *amber(CGFloat a) { return [UIColor colorWithRed:1.0 green:0.69 blue:0.0 alpha:a]; }
static UIFont *boardFont(CGFloat sz) { return [UIFont fontWithName:@"CourierNewPS-BoldMT" size:sz] ?: [UIFont boldSystemFontOfSize:sz]; }
static UIColor *muniRed(void) { return [UIColor colorWithRed:0.80 green:0.10 blue:0.18 alpha:1]; }

static void darkTable(UITableView *tv) { tv.backgroundColor = [UIColor blackColor]; tv.separatorColor = [UIColor colorWithWhite:0.2 alpha:1]; }
static UIView *boardHeader(NSString *text, UIColor *color) {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 26)] autorelease]; v.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    UILabel *l = [[[UILabel alloc] initWithFrame:CGRectMake(12, 0, 296, 26)] autorelease]; l.backgroundColor = [UIColor clearColor]; l.font = boardFont(13); l.textColor = color; l.text = text; l.adjustsFontSizeToFitWidth = YES; l.minimumFontSize = 9;
    [v addSubview:l]; return v;
}
static UITableViewCell *boardCell(UITableView *tv, NSString *rid) {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:rid];
    if (!c) { c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid] autorelease]; c.textLabel.font = boardFont(21); c.detailTextLabel.font = [UIFont systemFontOfSize:13]; c.textLabel.backgroundColor = [UIColor clearColor]; c.detailTextLabel.backgroundColor = [UIColor clearColor]; c.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1]; c.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *sel = [[[UIView alloc] init] autorelease]; sel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1]; c.selectedBackgroundView = sel; }
    c.textLabel.textColor = amber(1); c.accessoryType = UITableViewCellAccessoryNone; c.imageView.image = nil;
    return c;
}
static UITableViewCell *alertCell(NSString *text) {
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.text = text; c.textLabel.numberOfLines = 0; c.textLabel.font = [UIFont systemFontOfSize:14]; c.textLabel.textColor = [UIColor whiteColor]; c.textLabel.backgroundColor = [UIColor clearColor]; c.textLabel.lineBreakMode = UILineBreakModeWordWrap; return c;
}
static CGFloat alertHeight(NSString *text) { return MAX(44, [text sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(290, 600) lineBreakMode:UILineBreakModeWordWrap].height + 20); }
static NSString *minsText(NSInteger m) { return m <= 0 ? @"NOW" : m < 60 ? [NSString stringWithFormat:@"%ld MIN", (long)m] : [NSString stringWithFormat:@"%ldH %ldM", (long)m / 60, (long)m % 60]; }
static UILabel *footer(UITableView *tv) {
    UILabel *foot = (UILabel *)[tv.tableFooterView viewWithTag:77];
    if (!foot) { foot = [[[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 60)] autorelease]; foot.tag = 77; foot.backgroundColor = [UIColor blackColor]; foot.textColor = [UIColor colorWithWhite:0.55 alpha:1]; foot.font = [UIFont systemFontOfSize:13]; foot.numberOfLines = 0; foot.textAlignment = UITextAlignmentCenter; tv.tableFooterView = foot; }
    return foot;
}

#pragma mark - BART
@implementation CTBartViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"BART"; self.tabBarItem.title = @"BART"; station = [[CTBart homeStation] copy]; self.navigationItem.titleView = logoTitle(@"logo-bart.png");
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Plan" style:UIBarButtonItemStyleBordered target:self action:@selector(plan)] autorelease];
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)] autorelease];
    }
    return self;
}
- (id)initWithStation:(NSString *)abbr {
    if ((self = [self init])) { pinned = YES; [station release]; station = [abbr copy]; self.navigationItem.titleView = nil; self.title = [self stationName]; self.navigationItem.rightBarButtonItem = self.navigationItem.leftBarButtonItem; self.navigationItem.leftBarButtonItem = nil; self.hidesBottomBarWhenPushed = YES; }   // Refresh moves right so the Back button can show
    return self;
}
- (void)dealloc { [timer invalidate]; [station release]; [deps release]; [status release]; [advisories release]; [stationButton release]; [super dealloc]; }
- (NSString *)stationName { return [[[CTBart stations] objectAtIndex:[CTBart stationIndexForAbbr:station]] objectForKey:@"name"]; }
- (void)viewDidLoad {
    [super viewDidLoad]; darkTable(self.tableView);
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 60)] autorelease]; hdr.backgroundColor = [UIColor blackColor];
    stationButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    stationButton.frame = CGRectMake(10, 10, 300, 40); stationButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    stationButton.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1]; stationButton.layer.cornerRadius = 8; stationButton.layer.borderWidth = 1; stationButton.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1].CGColor;
    stationButton.titleLabel.font = [UIFont boldSystemFontOfSize:19]; [stationButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [stationButton addTarget:self action:@selector(pickStation) forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:stationButton]; self.tableView.tableHeaderView = hdr;
    footer(self.tableView);
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [stationButton setTitle:[NSString stringWithFormat:@"%@  ▾", [self stationName]] forState:UIControlStateNormal]; [self.tableView reloadData]; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; if ([ud boolForKey:@"ct_test_plan"]) { [ud removeObjectForKey:@"ct_test_plan"]; [ud synchronize]; [self plan]; return; } [self refresh]; timer = [[NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refresh) userInfo:nil repeats:YES] retain]; }
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [timer invalidate]; [timer release]; timer = nil; [[CTDrum shared] hide]; }
- (void)pickStation {
    NSMutableArray *rows = [NSMutableArray array]; for (NSDictionary *s in [CTBart stations]) [rows addObject:[s objectForKey:@"name"]];
    [[CTDrum shared] showInView:self.tabBarController.view title:@"BART station" rows:rows selected:[CTBart stationIndexForAbbr:station]
        onChange:^(NSInteger r) { [station release]; station = [[[[CTBart stations] objectAtIndex:r] objectForKey:@"abbr"] copy]; if (!pinned) [CTBart setHomeStation:station]; [stationButton setTitle:[NSString stringWithFormat:@"%@  ▾", [self stationName]] forState:UIControlStateNormal]; }
        onDone:^{ [deps release]; deps = nil; [self.tableView reloadData]; [self refresh]; }];
}
- (void)plan { CTBartTripViewController *t = [[CTBartTripViewController alloc] init]; [self.navigationController pushViewController:t animated:YES]; [t release]; }
- (void)refresh {
    if (busy) return; busy = YES; [status release]; status = @"Checking BART..."; footer(self.tableView).text = status;
    [self performSelectorInBackground:@selector(fetch:) withObject:station];
}
- (void)fetch:(NSString *)abbr {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *err = nil;
    NSArray *d = [CTBart departuresAt:abbr error:&err]; NSString *adv = d ? [CTBart advisoriesWithError:NULL] : nil;
    [self performSelectorOnMainThread:@selector(fetched:) withObject:[NSArray arrayWithObjects:(d ?: [NSArray array]), (err ?: @""), (adv ?: @""), abbr, nil] waitUntilDone:NO];
    [p release];
}
- (void)fetched:(NSArray *)r {
    busy = NO; if (![[r objectAtIndex:3] isEqualToString:station]) return;
    NSString *err = [r objectAtIndex:1];
    if (![err length]) { [deps release]; deps = [[r objectAtIndex:0] retain]; }
    [advisories release]; advisories = [[r objectAtIndex:2] length] ? [[r objectAtIndex:2] copy] : nil;
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"h:mm a"];
    [status release]; status = [err length] ? [err copy] : [[NSString stringWithFormat:@"Live from BART at %@. Refreshes every minute while open.", [f stringFromDate:[NSDate date]]] copy];
    footer(self.tableView).text = status; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return advisories ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? MAX(1, MIN(14, (NSInteger)[deps count])) : 1; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s { return boardHeader(s == 0 ? [[NSString stringWithFormat:@"DEPARTING  ·  %@", [self stationName]] uppercaseString] : @"ADVISORIES", s == 0 ? amber(1) : [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1]); }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return 26; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip { c.backgroundColor = ip.section == 1 ? [UIColor colorWithRed:0.30 green:0.05 blue:0.08 alpha:1] : [UIColor blackColor]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 1 ? alertHeight(advisories) : 58; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1) return alertCell(advisories);
    UITableViewCell *c = boardCell(tv, @"b");
    if (![deps count]) { c.textLabel.text = deps ? @"NO TRAINS" : @"LOADING"; c.textLabel.textColor = amber(0.6); c.detailTextLabel.text = deps ? @"BART reports nothing from this station right now." : @"Asking api.bart.gov"; return c; }
    NSDictionary *d = [deps objectAtIndex:ip.row]; NSInteger delay = [[d objectForKey:@"delay"] integerValue] / 60;
    c.textLabel.text = [NSString stringWithFormat:@"%@  %@", minsText([[d objectForKey:@"minutes"] integerValue]), [d objectForKey:@"dest"]];
    c.textLabel.adjustsFontSizeToFitWidth = YES; c.textLabel.minimumFontSize = 13;
    c.detailTextLabel.text = [NSString stringWithFormat:@"Platform %@ · %@ cars · %@%@", [d objectForKey:@"platform"], [d objectForKey:@"length"], [d objectForKey:@"direction"], delay >= 1 ? [NSString stringWithFormat:@" · %ld min late", (long)delay] : @""];
    c.detailTextLabel.textColor = delay >= 1 ? [UIColor colorWithRed:1 green:0.55 blue:0.55 alpha:1] : [UIColor colorWithWhite:0.75 alpha:1];
    c.imageView.image = [CTBart squareForHex:[d objectForKey:@"hex"]];
    return c;
}
@end

@implementation CTBartTripViewController
- (id)init { if ((self = [super initWithStyle:UITableViewStyleGrouped])) { self.title = @"BART Trip"; from = [CTBart stationIndexForAbbr:[CTBart homeStation]]; to = [CTBart stationIndexForAbbr:@"SFIA"]; when = -1; } return self; }
- (void)dealloc { [trips release]; [status release]; [super dealloc]; }
- (NSString *)abbr:(NSInteger)i { return [[[CTBart stations] objectAtIndex:i] objectForKey:@"abbr"]; }
- (NSString *)name:(NSInteger)i { return [[[CTBart stations] objectAtIndex:i] objectForKey:@"name"]; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if (!trips) [self search]; }
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [[CTDrum shared] hide]; }
- (void)search {
    if (busy) return; busy = YES; [status release]; status = @"Asking BART..."; [self.tableView reloadData];
    [self performSelectorInBackground:@selector(work:) withObject:[NSArray arrayWithObjects:[self abbr:from], [self abbr:to], when < 0 ? @"" : [CTData fmtMin:when], nil]];
}
- (void)work:(NSArray *)a { NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *err = nil; NSArray *t = [CTBart tripsFrom:[a objectAtIndex:0] to:[a objectAtIndex:1] time:[[a objectAtIndex:2] length] ? [a objectAtIndex:2] : nil error:&err]; [self performSelectorOnMainThread:@selector(done:) withObject:[NSArray arrayWithObjects:(t ?: [NSArray array]), (err ?: @""), nil] waitUntilDone:NO]; [p release]; }
- (void)done:(NSArray *)r { busy = NO; [trips release]; trips = [[r objectAtIndex:0] retain]; [status release]; status = [[r objectAtIndex:1] length] ? [[r objectAtIndex:1] copy] : nil; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 3 : MAX(1, (NSInteger)[trips count]); }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return s == 1 ? [NSString stringWithFormat:@"%@ to %@", [self name:from], [self name:to]] : nil; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return s == 1 ? (status ?: ([trips count] ? @"Clipper fare shown. Trips with a transfer list both legs." : nil)) : nil; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 1 && [trips count] ? 60 : 44; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.textLabel.text = ip.row == 0 ? @"From" : ip.row == 1 ? @"To" : @"Leave at"; c.detailTextLabel.text = ip.row == 0 ? [self name:from] : ip.row == 1 ? [self name:to] : (when < 0 ? @"Now" : [CTData fmtMin:when]); return c;
    }
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; c.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1]; c.textLabel.font = [UIFont boldSystemFontOfSize:17];
    if (![trips count]) { c.textLabel.text = busy ? @"Asking BART..." : @"No trips"; c.textLabel.textColor = [UIColor grayColor]; return c; }
    NSDictionary *t = [trips objectAtIndex:ip.row]; NSArray *legs = [t objectForKey:@"legs"];
    c.textLabel.text = [NSString stringWithFormat:@"%@  →  %@", [t objectForKey:@"dep"], [t objectForKey:@"arr"]];
    NSMutableArray *parts = [NSMutableArray array]; for (NSDictionary *l in legs) [parts addObject:[l objectForKey:@"head"]];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ min · $%@ · %@%@", [t objectForKey:@"mins"], [t objectForKey:@"fare"], [legs count] > 1 ? [NSString stringWithFormat:@"change at %@ · ", [[legs objectAtIndex:0] objectForKey:@"to"]] : @"", [parts componentsJoinedByString:@" then "]];
    c.detailTextLabel.numberOfLines = 2; c.detailTextLabel.font = [UIFont systemFontOfSize:12];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; if (ip.section != 0) return;
    NSMutableArray *rows = [NSMutableArray array]; for (NSDictionary *s in [CTBart stations]) [rows addObject:[s objectForKey:@"name"]];
    UIView *host = self.tabBarController.view;
    if (ip.row == 0) [[CTDrum shared] showInView:host title:@"From" rows:rows selected:from onChange:^(NSInteger r) { from = r; [tv reloadRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationNone]; } onDone:^{ [self search]; }];
    else if (ip.row == 1) [[CTDrum shared] showInView:host title:@"To" rows:rows selected:to onChange:^(NSInteger r) { to = r; [tv reloadRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationNone]; } onDone:^{ [self search]; }];
    else [[CTDrum shared] showInView:host title:@"Leave at" rows:CTTimeRows() selected:(when < 0 ? [CTData minutesNow] : when) / 5 onChange:^(NSInteger r) { when = r * 5; [tv reloadRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationNone]; } onDone:^{ [self search]; }];
}
@end

#pragma mark - Muni
@implementation CTMuniViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Muni"; self.tabBarItem.title = @"Muni"; preds = [[NSMutableDictionary alloc] init]; self.navigationItem.titleView = logoTitle(@"logo-muni.png");
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)] autorelease];
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)] autorelease];
    }
    return self;
}
- (void)dealloc { [stops release]; [preds release]; [status release]; [super dealloc]; }
- (void)viewDidLoad { [super viewDidLoad]; darkTable(self.tableView); footer(self.tableView); }
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [stops release]; stops = [[CTMuni savedStops] retain]; footer(self.tableView).text = status ?: ([stops count] ? @"" : @"Tap + and type the stop number from the pole or shelter. Each saved stop costs one 511 request per refresh."); [self.tableView reloadData]; }
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a]; NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:@"ct_test_metro_line"]) { NSInteger i = [d integerForKey:@"ct_test_metro_line"]; [d removeObjectForKey:@"ct_test_metro_line"]; [d synchronize]; [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]]; return; }
    if ([stops count] && [[NSDate date] timeIntervalSince1970] - lastFetch > 90) [self refresh];
}
- (void)add { CTMuniAddViewController *v = [[CTMuniAddViewController alloc] init]; UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:v]; n.navigationBar.tintColor = self.navigationController.navigationBar.tintColor; [self presentModalViewController:n animated:YES]; [n release]; [v release]; }
- (void)refresh {
    if (busy || ![stops count]) return; busy = YES; lastFetch = [[NSDate date] timeIntervalSince1970]; [status release]; status = @"Checking 511..."; footer(self.tableView).text = status;
    [self performSelectorInBackground:@selector(fetch:) withObject:[NSArray arrayWithArray:stops]];
}
- (void)fetch:(NSArray *)codes {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSMutableDictionary *out = [NSMutableDictionary dictionary]; NSString *err = nil;
    for (NSString *c in codes) { NSString *e = nil; NSArray *r = [CTMuni predictionsForStop:c error:&e]; if (r) [out setObject:r forKey:c]; else if (e && !err) err = e; }
    [self performSelectorOnMainThread:@selector(fetched:) withObject:[NSArray arrayWithObjects:out, (err ?: @""), nil] waitUntilDone:NO];
    [p release];
}
- (void)fetched:(NSArray *)r {
    busy = NO; [preds addEntriesFromDictionary:[r objectAtIndex:0]];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"h:mm a"];
    [status release]; status = [[r objectAtIndex:1] length] ? [[r objectAtIndex:1] copy] : [[NSString stringWithFormat:@"Live from 511 at %@. Pull the refresh button for new times.", [f stringFromDate:[NSDate date]]] copy];
    footer(self.tableView).text = status; [self.tableView reloadData];
}
// section 0 is Muni Metro (one row per line); saved stops follow
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1 + MAX(1, (NSInteger)[stops count]); }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { if (s == 0) return [[CTMapView metroLines] count]; s--; if (![stops count]) return 1; NSArray *p = [preds objectForKey:[stops objectAtIndex:s]]; return MAX(1, MIN(6, (NSInteger)[p count])); }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    if (s == 0) return boardHeader(@"MUNI METRO", amber(1)); s--;
    if (![stops count]) return boardHeader(@"NO STOPS SAVED", amber(1));
    NSString *code = [stops objectAtIndex:s]; NSString *name = [CTMuni nameForStop:code] ?: @"Unknown stop";
    return boardHeader([[NSString stringWithFormat:@"%@  ·  #%@", name, code] uppercaseString], amber(1));
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return 26; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip { c.backgroundColor = [UIColor blackColor]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 0 ? 44 : 58; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *c = boardCell(tv, @"ml"); NSDictionary *l = [[CTMapView metroLines] objectAtIndex:ip.row];
        c.textLabel.text = [NSString stringWithFormat:@"%@  %@", [l objectForKey:@"id"], [[l objectForKey:@"name"] uppercaseString]]; c.textLabel.textColor = [UIColor whiteColor];
        NSArray *dirs = [l objectForKey:@"dirs"]; c.detailTextLabel.text = [dirs count] > 1 ? [NSString stringWithFormat:@"%@ ↔ %@", [[dirs objectAtIndex:0] objectForKey:@"head"], [[dirs objectAtIndex:1] objectForKey:@"head"]] : @"";
        c.imageView.image = [CTData badgeText:[l objectForKey:@"id"] color:[CTMapView colorForHex:[l objectForKey:@"color"]]]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleGray;
        return c;
    }
    UITableViewCell *c = boardCell(tv, @"m"); ip = [NSIndexPath indexPathForRow:ip.row inSection:ip.section - 1];
    if (![stops count]) { c.textLabel.text = @"ADD A STOP"; c.textLabel.textColor = amber(0.6); c.detailTextLabel.text = @"The 5 digit number on the pole, like 15726."; return c; }
    NSString *code = [stops objectAtIndex:ip.section]; NSArray *p = [preds objectForKey:code];
    if (![p count]) { c.textLabel.text = p ? @"NO PREDICTIONS" : @"..."; c.textLabel.textColor = amber(0.6); c.detailTextLabel.text = p ? @"Nothing due at this stop right now." : @"Waiting for 511"; return c; }
    NSDictionary *d = [p objectAtIndex:ip.row];
    c.textLabel.text = [NSString stringWithFormat:@"%@  %@", minsText([[d objectForKey:@"minutes"] integerValue]), [d objectForKey:@"route"]];
    c.detailTextLabel.text = [NSString stringWithFormat:@"to %@", [d objectForKey:@"dest"]];
    c.imageView.image = [CTData badgeText:[d objectForKey:@"route"] color:muniRed()];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; if (ip.section != 0) return;
    CTMetroLineViewController *v = [[CTMetroLineViewController alloc] initWithLine:[[CTMapView metroLines] objectAtIndex:ip.row]]; [self.navigationController pushViewController:v animated:YES]; [v release];
}
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return ip.section > 0 && [stops count] > 0; }
- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return @"Remove stop"; }
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)st forRowAtIndexPath:(NSIndexPath *)ip {
    if (st != UITableViewCellEditingStyleDelete) return;
    NSMutableArray *a = [NSMutableArray arrayWithArray:stops]; [a removeObjectAtIndex:ip.section - 1]; [CTMuni setSavedStops:a]; [stops release]; stops = [a retain]; [tv reloadData];
}
@end

#pragma mark - Muni Metro
@implementation CTMetroLineViewController
- (id)initWithLine:(NSDictionary *)l { if ((self = [super initWithStyle:UITableViewStylePlain])) { line = [l retain]; self.title = [NSString stringWithFormat:@"%@ %@", [l objectForKey:@"id"], [l objectForKey:@"name"]]; self.hidesBottomBarWhenPushed = YES; } return self; }
- (void)dealloc { [line release]; [dirSeg release]; [super dealloc]; }
- (NSArray *)dirs { return [line objectForKey:@"dirs"]; }
- (NSArray *)stops { NSArray *d = [self dirs]; return [d count] > dir ? [[d objectAtIndex:dir] objectForKey:@"stops"] : [NSArray array]; }
- (void)viewDidLoad {
    [super viewDidLoad]; darkTable(self.tableView);
    NSMutableArray *items = [NSMutableArray array]; for (NSDictionary *d in [self dirs]) [items addObject:[NSString stringWithFormat:@"→ %@", [d objectForKey:@"head"]]];
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 54)] autorelease]; hdr.backgroundColor = [UIColor blackColor];
    dirSeg = [[UISegmentedControl alloc] initWithItems:items]; dirSeg.frame = CGRectMake(10, 10, 300, 34); dirSeg.autoresizingMask = UIViewAutoresizingFlexibleWidth; dirSeg.segmentedControlStyle = UISegmentedControlStyleBar; dirSeg.tintColor = [UIColor colorWithWhite:0.25 alpha:1]; dirSeg.selectedSegmentIndex = 0;
    [dirSeg addTarget:self action:@selector(dirChanged) forControlEvents:UIControlEventValueChanged]; [hdr addSubview:dirSeg]; self.tableView.tableHeaderView = hdr;
    footer(self.tableView).text = @"Tap a stop for live arrivals from 511.";
}
- (void)dirChanged { dir = dirSeg.selectedSegmentIndex; [self.tableView reloadData]; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; NSUserDefaults *d = [NSUserDefaults standardUserDefaults]; if ([d objectForKey:@"ct_test_metro_stop"]) { NSInteger i = [d integerForKey:@"ct_test_metro_stop"]; [d removeObjectForKey:@"ct_test_metro_stop"]; [d synchronize]; [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]]; } }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [[self stops] count]; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s { return boardHeader([[NSString stringWithFormat:@"%@ LINE  ·  %ld STOPS", [line objectForKey:@"id"], (long)[[self stops] count]] uppercaseString], amber(1)); }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return 26; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip { c.backgroundColor = [UIColor blackColor]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 44; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = boardCell(tv, @"ms"); NSDictionary *s = [[self stops] objectAtIndex:ip.row]; NSArray *st = [self stops];
    c.textLabel.text = [s objectForKey:@"name"]; c.textLabel.font = [UIFont boldSystemFontOfSize:15]; c.textLabel.textColor = [UIColor whiteColor]; c.textLabel.adjustsFontSizeToFitWidth = YES; c.textLabel.minimumFontSize = 11;
    c.detailTextLabel.text = ip.row == 0 ? @"First stop" : ip.row == (NSInteger)[st count] - 1 ? @"Last stop" : [NSString stringWithFormat:@"Stop #%@", [s objectForKey:@"code"]];
    c.imageView.image = [CTData badgeText:[line objectForKey:@"id"] color:[CTMapView colorForHex:[line objectForKey:@"color"]]]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; c.selectionStyle = UITableViewCellSelectionStyleGray;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSMutableDictionary *s = [NSMutableDictionary dictionaryWithDictionary:[[self stops] objectAtIndex:ip.row]]; [s setObject:[line objectForKey:@"id"] forKey:@"line"]; [s setObject:[line objectForKey:@"color"] forKey:@"color"];
    CTMetroStopViewController *v = [[CTMetroStopViewController alloc] initWithStop:s]; [self.navigationController pushViewController:v animated:YES]; [v release];
}
@end

@implementation CTMetroStopViewController
- (id)initWithStop:(NSDictionary *)s {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        stop = [s retain]; self.title = [s objectForKey:@"name"]; self.hidesBottomBarWhenPushed = YES;
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)] autorelease];
    }
    return self;
}
- (void)dealloc { [stop release]; [preds release]; [status release]; [super dealloc]; }
- (NSString *)code { return [stop objectForKey:@"code"]; }
- (void)viewDidLoad {
    [super viewDidLoad]; darkTable(self.tableView);
    UIView *hdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)] autorelease]; hdr.backgroundColor = [UIColor blackColor];
    UIButton *save = [UIButton buttonWithType:UIButtonTypeCustom]; save.frame = CGRectMake(10, 7, 300, 30); save.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    save.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1]; save.layer.cornerRadius = 6; save.layer.borderWidth = 1; save.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1].CGColor; save.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    BOOL saved = [[CTMuni savedStops] containsObject:[self code]];
    [save setTitle:saved ? @"Saved to the Muni tab" : @"Save stop to the Muni tab" forState:UIControlStateNormal]; [save setTitleColor:saved ? [UIColor grayColor] : [UIColor whiteColor] forState:UIControlStateNormal]; save.enabled = !saved;
    [save addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside]; [hdr addSubview:save]; self.tableView.tableHeaderView = hdr;
    footer(self.tableView);
}
- (void)save:(UIButton *)b { NSMutableArray *a = [NSMutableArray arrayWithArray:[CTMuni savedStops]]; if (![a containsObject:[self code]]) [a addObject:[self code]]; [CTMuni setSavedStops:a]; [b setTitle:@"Saved to the Muni tab" forState:UIControlStateNormal]; [b setTitleColor:[UIColor grayColor] forState:UIControlStateNormal]; b.enabled = NO; }
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; if (!preds) [self refresh]; }
- (void)refresh {
    if (busy) return; busy = YES; [status release]; status = @"Checking 511..."; footer(self.tableView).text = status;
    [self performSelectorInBackground:@selector(fetch:) withObject:[self code]];
}
- (void)fetch:(NSString *)c { NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; NSString *e = nil; NSArray *r = [CTMuni predictionsForStop:c error:&e]; [self performSelectorOnMainThread:@selector(fetched:) withObject:[NSArray arrayWithObjects:(r ?: [NSArray array]), (e ?: @""), nil] waitUntilDone:NO]; [p release]; }
- (void)fetched:(NSArray *)r {
    busy = NO; NSString *err = [r objectAtIndex:1]; [preds release]; preds = [[r objectAtIndex:0] retain];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"h:mm a"];
    [status release]; status = [err length] ? [err copy] : [[NSString stringWithFormat:@"Live from 511 at %@. Tap refresh for new times.", [f stringFromDate:[NSDate date]]] copy];
    footer(self.tableView).text = status; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return MAX(1, MIN(10, (NSInteger)[preds count])); }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s { return boardHeader([[NSString stringWithFormat:@"%@  ·  #%@", [stop objectForKey:@"name"], [self code]] uppercaseString], amber(1)); }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return 26; }
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip { c.backgroundColor = [UIColor blackColor]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 58; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = boardCell(tv, @"mp");
    if (![preds count]) { c.textLabel.text = preds ? @"NO PREDICTIONS" : @"LOADING"; c.textLabel.textColor = amber(0.6); c.detailTextLabel.text = preds ? @"Nothing due at this stop right now." : @"Asking 511"; return c; }
    NSDictionary *d = [preds objectAtIndex:ip.row]; NSString *route = [d objectForKey:@"route"];
    c.textLabel.text = [NSString stringWithFormat:@"%@  %@", minsText([[d objectForKey:@"minutes"] integerValue]), route];
    c.detailTextLabel.text = [NSString stringWithFormat:@"to %@", [d objectForKey:@"dest"]];
    NSString *hex = nil; for (NSDictionary *l in [CTMapView metroLines]) if ([[l objectForKey:@"id"] isEqualToString:route]) hex = [l objectForKey:@"color"];
    c.imageView.image = [CTData badgeText:route color:hex ? [CTMapView colorForHex:hex] : muniRed()];
    return c;
}
@end

@implementation CTMuniAddViewController
- (id)init { if ((self = [super initWithStyle:UITableViewStyleGrouped])) { self.title = @"Add Muni Stop"; self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)] autorelease]; self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)] autorelease]; } return self; }
- (void)dealloc { [code release]; [nameLabel release]; [super dealloc]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    code = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 260, 30)]; code.placeholder = @"15726"; code.font = boardFont(22); code.keyboardType = UIKeyboardTypeNumberPad; code.delegate = self; code.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter; code.clearButtonMode = UITextFieldViewModeWhileEditing;
    [code addTarget:self action:@selector(changed) forControlEvents:UIControlEventEditingChanged];
    nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 280, 30)]; nameLabel.font = [UIFont systemFontOfSize:15]; nameLabel.textColor = [UIColor grayColor]; nameLabel.backgroundColor = [UIColor clearColor];
}
- (void)viewDidAppear:(BOOL)a { [super viewDidAppear:a]; [code becomeFirstResponder]; }
- (void)changed { NSString *n = [CTMuni nameForStop:code.text]; nameLabel.text = n ?: ([code.text length] >= 5 ? @"Not a Muni stop number." : @"Stop name appears here."); nameLabel.textColor = n ? [UIColor blackColor] : [UIColor grayColor]; }
- (void)cancel { [self dismissModalViewControllerAnimated:YES]; }
- (void)save {
    NSString *c = [code.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if (![c length]) return;
    NSMutableArray *a = [NSMutableArray arrayWithArray:[CTMuni savedStops]]; if (![a containsObject:c]) [a addObject:c]; [CTMuni setSavedStops:a];
    [self dismissModalViewControllerAnimated:YES];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return 2; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return @"Stop number"; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return @"Printed on every Muni pole and shelter, and on the 511 stop signs. Buses, Metro and cable cars all work."; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease]; c.selectionStyle = UITableViewCellSelectionStyleNone; CGFloat w = c.contentView.bounds.size.width;
    UIView *v = ip.row == 0 ? (UIView *)code : (UIView *)nameLabel; v.frame = CGRectMake(10, 7, w - 20, 30); v.autoresizingMask = UIViewAutoresizingFlexibleWidth; [c.contentView addSubview:v];
    if (ip.row == 1) [self changed];
    return c;
}
@end
