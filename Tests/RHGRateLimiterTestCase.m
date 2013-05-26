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

@interface RHGRateLimiterTestCase : SenTestCase

@end




@implementation RHGRateLimiterTestCase {
    LRMockery *context;
    
    RHGRateLimiter *limiter;
    id <RHGCurrentDateWrapper> currentDateWrapper;
    
    BOOL _notificationReceived;
}

#pragma mark - Lifecycle
- (void)setUp
{
    context = mockery();
    _notificationReceived = NO;
    
    currentDateWrapper = [context protocolMock:@protocol(RHGCurrentDateWrapper)];
    
    limiter = [[RHGRateLimiter alloc] initWithCurrentDateWrapper:currentDateWrapper];
    
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
- (void)testThatQPSLimitSetTo4
{
    assertThat(@( [limiter rateLimit] ), equalTo(@4));
    assertContextSatisfied(context);
}

- (void)testNoRequestsNotAboveLimit
{
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatQPSLimitIgnoredForNotificationsWithNoObject
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

- (void)testThatQPSLimitIgnoredForNetworkingOperationsThatDontImplementQPSLimitedProtocol
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

- (void)testThatThreeRequestsNotAboveQPSLimit
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeIntervalSince1970:0]);
    }];
    
    NSArray *started = [self postStartNotificationNTimes:3];
    
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatOneFinishedRequestJustNowNotAboveQPSLimit
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(currentDateWrapper) currentDate]; andReturn([NSDate dateWithTimeIntervalSince1970:0]);
    }];
    
    id started = [self postStartNotification];
    [self postFinishNotificationForOperation:started];
    
    assertThatBool([limiter atRateLimit], equalToBool(NO));
    assertContextSatisfied(context);
}

- (void)testThatFourRequestsAtQPSLimit
{
    NSArray *started = [self postStartNotificationNTimes:4];
    
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatFiveRequestsAtQPSLimit
{
    NSArray *started = [self postStartNotificationNTimes:5];
    
    assertThatBool([limiter atRateLimit], equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatQPSLimitPersistsForANonZeroTimeInterval
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

- (void)testAtQPSLimitWhenRequestsOngoing
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

#pragma mark - Helpers
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    _notificationReceived = YES;
}

- (id)newQPSLimitedOperation
{
    id mock = [context protocolMock:@protocol(RHGRateLimitedRequestOperation)];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(mock) obeysRateLimiter]; [builder will:returnBool(YES)];
    }];
    
    return mock;
}

- (id)postStartNotification
{
    id operation = [self newQPSLimitedOperation];
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
