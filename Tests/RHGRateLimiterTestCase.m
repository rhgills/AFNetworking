//
//  RHGRateLimiterTestCase.m
//  Phoenix
//
//  Created by Robert Gilliam on 5/22/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>

#import "AFNetworking.h"

#define LRMOCKY_SHORTHAND
#define LRMOCKY_SUGAR
#import "LRMocky.h"

#define HC_SHORTHAND
#import "OCHamcrest.h"

#import "RHGPerformDelayedSelectorWrapper.h"

@interface RHGRateLimiterTestCase : SenTestCase

@end




@implementation RHGRateLimiterTestCase {
    LRMockery *context;
    
    RHGRateLimiter *limiter;
    id <RHGCurrentDateWrapper> currentDateWrapper;
    id performDelayedSelectorWrapper;
    
    BOOL _notificationReceived;
}

#pragma mark - Lifecycle
- (void)setUp
{
    context = mockery();
    _notificationReceived = NO;
    
    currentDateWrapper = [context protocolMock:@protocol(RHGCurrentDateWrapper)];
    performDelayedSelectorWrapper = [context mock:[RHGPerformDelayedSelectorWrapper class]];
    
    limiter = [[RHGRateLimiter alloc] initWithCurrentDateWrapper:currentDateWrapper performDelayedSelectorWrapper:performDelayedSelectorWrapper];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeIntervalSince1970:0.0]);
    }];
}

- (void)tearDown
{
    [limiter tearDown];
    limiter = nil;
}


#pragma mark - Tests
- (void)testThatRateLimitSetTo4
{
    assertThat(@( [limiter rateLimit] ), equalTo(@4));
    assertContextSatisfied(context);
}

- (void)testNoRequestsNotAboveLimit
{
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatRateLimitIgnoredForNotificationsWithNoObject
{
    // when
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
    
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatRateLimitIgnoredForNetworkingOperationsThatDontImplementRateLimitedProtocol
{
    // when
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:[[NSObject alloc] init]];
    
    
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatThreeRequestsNotAboveRateLimit
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeIntervalSince1970:0]);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:3];
    
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatOneFinishedRequestJustNowNotAboveRateLimit
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeIntervalSince1970:0]);
    }];
    
    id started = [self postStartNotification];
    [self postFinishNotificationForOperation:started];
    
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatFourRequestsAtRateLimit
{
    NSArray *started = [self postStartNotificationNTimes:4];
    
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatFiveRequestsAtRateLimit
{
    NSArray *started = [self postStartNotificationNTimes:5];
    
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatRateLimitPersistsForANonZeroTimeInterval
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeIntervalSince1970:0]);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:4];
    [self postFinishNotificationsForRequestOperations:started];
    
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatAnotherRequestCanBeMadeOneSecondAfterARequestFinishes
{
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:0.0];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(startDate);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:4];
    
    NSDate *finishDate = startDate;
    [self postFinishNotificationForOperation:[started lastObject]];
    
    // when
    NSDate *limitLiftedDate = [NSDate dateWithTimeInterval:1.0 sinceDate:finishDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(limitLiftedDate);
    }];
    
    // then
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatNoRequestAllowedAfterLessThanOneSecondAfterFinish
{
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:0.0];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(startDate);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:4];
    [self postFinishNotificationForOperation:[started lastObject]];
    
    // when
    NSDate *finishDate = [NSDate dateWithTimeInterval:.9 sinceDate:startDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(finishDate);
    }];
    
    // then
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatNoRequestAllowedLessThanOneSecondAfterFinishLongRequest
{
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:0.0];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(startDate);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:4];
    
    NSDate *finishDate = [NSDate dateWithTimeInterval:20.0 sinceDate:startDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(finishDate);
    }];
    
    [self postFinishNotificationForOperation:[started lastObject]];
    
    // when
    NSDate *checkDate = [NSDate dateWithTimeInterval:.9 sinceDate:finishDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(checkDate);
    }];
    
    // then
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatRequestAllowedOneSecondAfterFinishLongRequest
{
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:0.0];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(startDate);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:4];
    
    NSDate *finishDate = [NSDate dateWithTimeInterval:20.0 sinceDate:startDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(finishDate);
    }];
    
    [self postFinishNotificationForOperation:[started lastObject]];
    
    // when
    NSDate *checkDate = [NSDate dateWithTimeInterval:1.0 sinceDate:finishDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(checkDate);
    }];
    
    // then
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testAtRateLimitWhenRequestsOngoing
{
    NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:0.0];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(startDate);
    }];
    
    [self postStartNotificationNTimes:4];
    
    // when
    NSDate *checkDate = [NSDate dateWithTimeInterval:20.0 sinceDate:startDate];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(checkDate);
    }];

    // then
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatNotificationPostedWhenRateLimitLifted
{
    NSDate *startAndFinishDate = [NSDate dateWithTimeIntervalSince1970:0.0];
    
    SEL selector = @selector(markQPSLimitChanged); // tightly coupled to the implementation because we can't pass an anything() hamcrest matcher as the selector argument and have it work.
    __block id object;
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn(startAndFinishDate);
    
        [oneOf(performDelayedSelectorWrapper) performSelector:selector withObject:(id)anything() afterDelay:1 onTarget:limiter]; andThen(LRA_performBlock(^(NSInvocation *invocation) {
//            [invocation getArgument:&selector atIndex:2];
            [invocation getArgument:&object atIndex:3];
        }));
    }];
    NSArray *started = [self postStartNotificationNTimes:4];
    
    //
    // when
    //
    
    // the selector was scheduled
    [self postFinishNotificationForOperation:[started lastObject]];
    assertContextSatisfied(context);
    
    // the selector works
    [context expectNotificationNamed:RHGRateLimiterMightHaveLiftedRateLimitNotification fromObject:limiter userInfo:(id)anything()];
    
    // don't trigger a debugging assertion in the rate limiter (that we are, actually, no longer at the QPSLimit when we notify).
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeInterval:1.0 sinceDate:startAndFinishDate]);
    }];
    
    [limiter performSelector:selector withObject:object];
    assertContextSatisfied(context);
}

#pragma mark - Helpers
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    _notificationReceived = YES;
}

- (id)newRateLimitedOperation
{
    id mock = [context protocolMock:@protocol(RHGRateLimitedRequestOperation)];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(mock) obeysRateLimiter]; [builder will:returnBool(YES)];
    }];
    
    return mock;
}

- (id)postStartNotification
{
    id operation = [self newRateLimitedOperation];
    [[NSNotificationCenter defaultCenter] postNotificationName:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:operation];
    return operation;
}

- (NSArray *)postStartNotificationNTimes:(NSInteger)n
{
    NSMutableArray *startedOperations = [NSMutableArray arrayWithCapacity:n];
    for (NSInteger i = 0; i < n; i++) {
        [startedOperations addObject:[self postStartNotification]];
    }
    
    return [NSArray arrayWithArray:startedOperations];
}

- (void)postFinishNotificationsForRequestOperations:(NSArray *)operations
{
    for (id anOperation in operations) {
        [self postFinishNotificationForOperation:anOperation];
    }
}

- (void)postFinishNotificationForOperation:(id)operation
{
    [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingOperationDidFinishNotification object:operation];
}

@end
