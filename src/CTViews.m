#import "CTViews.h"
#import "CTData.h"

NSArray *CTTimeRows(void) { static NSArray *r = nil; if (!r) { NSMutableArray *a = [NSMutableArray array]; for (int m = 0; m < 1440; m += 5) [a addObject:[CTData fmtMin:m]]; r = [a retain]; } return r; }
NSArray *CTStationRows(void) { static NSArray *r = nil; if (!r) { NSMutableArray *a = [NSMutableArray array]; for (NSDictionary *s in [CTData stations]) [a addObject:[s objectForKey:@"name"]]; r = [a retain]; } return r; }

@implementation CTDrum
+ (CTDrum *)shared { static CTDrum *d = nil; if (!d) d = [[CTDrum alloc] init]; return d; }
- (void)showInView:(UIView *)host title:(NSString *)t rows:(NSArray *)r selected:(NSInteger)i onChange:(CTDrumChange)c onDone:(void (^)(void))d {
    CGRect b = host.bounds;
    if (!view) {
        view = [[UIView alloc] initWithFrame:CGRectMake(0, b.size.height, b.size.width, 260)];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        UIToolbar *bar = [[[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 44)] autorelease]; bar.barStyle = UIBarStyleBlack; bar.translucent = NO;
        title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 190, 44)]; title.font = [UIFont boldSystemFontOfSize:14]; title.adjustsFontSizeToFitWidth = YES; title.minimumFontSize = 10; title.textColor = [UIColor whiteColor]; title.backgroundColor = [UIColor clearColor]; title.textAlignment = UITextAlignmentCenter;
        UIBarButtonItem *flex = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease];
        bar.items = [NSArray arrayWithObjects:flex, [[[UIBarButtonItem alloc] initWithCustomView:title] autorelease], flex, [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)] autorelease], nil];
        [view addSubview:bar];
        picker = [[UIPickerView alloc] initWithFrame:CGRectMake(0, 44, b.size.width, 216)]; picker.dataSource = self; picker.delegate = self; picker.showsSelectionIndicator = YES; picker.backgroundColor = [UIColor blackColor];
        [view addSubview:picker];
    }
    title.text = t; [rows release]; rows = [r retain]; [onChange release]; onChange = [c copy]; [onDone release]; onDone = [d copy];
    [view removeFromSuperview]; [host addSubview:view];
    [picker reloadAllComponents]; [picker selectRow:MIN((NSInteger)[rows count] - 1, MAX(0, i)) inComponent:0 animated:NO];
    view.frame = CGRectMake(0, b.size.height, b.size.width, 260);
    [UIView beginAnimations:nil context:NULL]; [UIView setAnimationDuration:0.3]; view.frame = CGRectMake(0, b.size.height - 260, b.size.width, 260); [UIView commitAnimations];
}
- (void)hide {
    if (!view || !view.superview) return;
    CGRect b = view.superview.bounds;
    [UIView beginAnimations:nil context:NULL]; [UIView setAnimationDuration:0.3]; view.frame = CGRectMake(0, b.size.height, b.size.width, 260); [UIView commitAnimations];
    [view performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:0.3];
}
- (void)done { void (^d)(void) = [[onDone copy] autorelease]; [self hide]; if (d) d(); }
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pv { return 1; }
- (NSInteger)pickerView:(UIPickerView *)pv numberOfRowsInComponent:(NSInteger)c { return [rows count]; }
- (NSString *)pickerView:(UIPickerView *)pv titleForRow:(NSInteger)row forComponent:(NSInteger)c { return [rows objectAtIndex:row]; }
- (CGFloat)pickerView:(UIPickerView *)pv widthForComponent:(NSInteger)c { return 260; }
- (void)pickerView:(UIPickerView *)pv didSelectRow:(NSInteger)row inComponent:(NSInteger)c { if (onChange) onChange(row); }
@end
