#import <XCTest/XCTest.h>
@import FSCalendarLegacy;
#import "FSCalendarCalculator.h"
#import "FSCalendarDynamicHeader.h"

@interface TestScopePan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState testState;
@property(nonatomic) CGPoint testTranslation;
@property(nonatomic) CGPoint testVelocity;
@end
@implementation TestScopePan
- (UIGestureRecognizerState)state { return self.testState; }
- (CGPoint)translationInView:(UIView *)view { return self.testTranslation; }
- (CGPoint)velocityInView:(UIView *)view { return self.testVelocity; }
@end

@interface LegacyCharacterizationTests : XCTestCase <FSCalendarDelegate>
@end
@implementation LegacyCharacterizationTests
- (NSDate *)date:(NSString *)value {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter dateFromString:value];
}
- (void)testOutOfBoundsSelectionRaisesException {
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 350, 320)];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    XCTAssertThrowsSpecificNamed([calendar selectDate:[self date:@"1900-01-01"]], NSException, @"FSCalendar date out of bounds exception");
}
- (void)testAlignedSixRowMonthHasLegacyLeadingWeek {
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 350, 320)];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    calendar.firstWeekday = 1;
    calendar.placeholderType = FSCalendarPlaceholderTypeFillSixRows;
    XCTAssertEqual([calendar.calculator numberOfHeadPlaceholdersForMonth:[self date:@"2024-09-01"]], 7);
    calendar.placeholderType = FSCalendarPlaceholderTypeFillHeadTail;
    XCTAssertEqual([calendar.calculator numberOfHeadPlaceholdersForMonth:[self date:@"2024-09-01"]], 0);
}
- (void)testDateIndexRoundTrips {
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 350, 320)];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [calendar reloadData]; // Resolve normalized bounds before querying the internal calculator.
    [calendar.calculator reloadSections];
    for (NSString *value in @[@"2000-02-29", @"2024-12-31", @"2025-01-01"]) {
        NSDate *date = [self date:value];
        for (NSUInteger weekday = 1; weekday <= 7; weekday++) {
            calendar.firstWeekday = weekday;
            [calendar.calculator reloadSections];
            NSIndexPath *index = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeMonth];
            XCTAssertEqualObjects([calendar.calculator dateForIndexPath:index scope:FSCalendarScopeMonth], date);
        }
    }
}
- (void)calendar:(FSCalendar *)calendar boundingRectWillChange:(CGRect)bounds animated:(BOOL)animated {
    calendar.frame = (CGRect){calendar.frame.origin, bounds.size};
}
- (void)testLegacyCancelledPanCommitsTargetScope {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UIViewController *controller = [UIViewController new];
    window.rootViewController = controller;
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 390, 320)];
    calendar.delegate = self;
    [controller.view addSubview:calendar];
    window.hidden = NO;
    [calendar layoutIfNeeded];
    TestScopePan *pan = [TestScopePan new];
    pan.testVelocity = CGPointMake(0, -100);
    pan.testState = UIGestureRecognizerStateBegan;
    [calendar handleScopeGesture:pan];
    pan.testTranslation = CGPointMake(0, -10);
    pan.testState = UIGestureRecognizerStateChanged;
    [calendar handleScopeGesture:pan];
    pan.testState = UIGestureRecognizerStateCancelled;
    [calendar handleScopeGesture:pan];
    // Upstream treats cancellation as completion. The Swift contract deliberately restores month.
    XCTAssertEqual(calendar.scope, FSCalendarScopeWeek);
    window.hidden = YES;
}
@end
