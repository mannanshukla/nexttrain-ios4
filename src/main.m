#import <UIKit/UIKit.h>
#import "CTControllers.h"
#import "CTAgencyControllers.h"
#import "CTMap.h"
#import <QuartzCore/QuartzCore.h>
@interface CTAppDelegate : NSObject <UIApplicationDelegate> { UIWindow *window; UITabBarController *tabs; }
@end
@implementation CTAppDelegate
- (UINavigationController *)wrap:(UIViewController *)vc { UINavigationController *n = [[[UINavigationController alloc] initWithRootViewController:vc] autorelease]; n.navigationBar.tintColor = [UIColor colorWithRed:0.72 green:0.08 blue:0.16 alpha:1]; return n; }
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    tabs = [[UITabBarController alloc] init];
    CTDeparturesViewController *d = [[[CTDeparturesViewController alloc] init] autorelease]; CTTripViewController *t = [[[CTTripViewController alloc] init] autorelease]; CTMapViewController *l = [[[CTMapViewController alloc] init] autorelease]; l.tabBarItem.image = [UIImage imageNamed:@"tab-line.png"];
    CTBartViewController *b = [[[CTBartViewController alloc] init] autorelease]; b.tabBarItem.image = [UIImage imageNamed:@"logo-bart-tab.png"];
    CTMuniViewController *mu = [[[CTMuniViewController alloc] init] autorelease]; mu.tabBarItem.image = [UIImage imageNamed:@"logo-muni-tab.png"];
    d.tabBarItem.image = [UIImage imageNamed:@"logo-caltrain-tab.png"]; d.tabBarItem.title = @"Caltrain";
    t.tabBarItem.image = [UIImage imageNamed:@"tab-trip.png"]; d.tabBarItem.image = [UIImage imageNamed:@"logo-caltrain-tab.png"];
    tabs.viewControllers = [NSArray arrayWithObjects:[self wrap:d], [self wrap:b], [self wrap:mu], [self wrap:t], [self wrap:l], nil];
    tabs.selectedIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"ct_tab"];
    [window addSubview:tabs.view]; [window makeKeyAndVisible];
    return YES;
}
- (void)applicationWillTerminate:(UIApplication *)app { [[NSUserDefaults standardUserDefaults] setInteger:tabs.selectedIndex forKey:@"ct_tab"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
- (void)dealloc { [tabs release]; [window release]; [super dealloc]; }
@end
int main(int argc, char *argv[]) { NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init]; int r = UIApplicationMain(argc, argv, nil, @"CTAppDelegate"); [p release]; return r; }
