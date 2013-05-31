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
    
    // dependencies
    id <RHGCurrentDateWrapper> currentDateWrapper;
    NSDate *_currentDate;
    id performDelayedSelectorWrapper;
    
    // collaborators
    id <RHGRateLimitedRequestOperation> rateLimitedRequestOperation;
    
    // helpers
    NSMutableArray *_otherRunningRequestOperations;
}

#pragma mark - Lifecycle
- (void)setUp
{
    context = mockery();
    
    currentDateWrapper = [context protocolMock:@protocol(RHGCurrentDateWrapper)];
    performDelayedSelectorWrapper = [context mock:[RHGPerformDelayedSelectorWrapper class]];
    limiter = [[RHGRateLimiter alloc] initWithCurrentDateWrapper:currentDateWrapper
                                   performDelayedSelectorWrapper:performDelayedSelectorWrapper];
    
    rateLimitedRequestOperation = [context protocolMock:@protocol(RHGRateLimitedRequestOperation)];
    
    [self setCurrentTimestampSince1970To:0.0];
}

- (void)tearDown
{
    limiter = nil;
}

#pragma mark - Tests
- (void)testThatNotStartedConnectionDoesNotCountTowardsRateLimit
{
    [context checking:^(LRExpectationBuilder *builder) {
        [oneOf(rateLimitedRequestOperation) rateLimiterRequestsConnectionStart:limiter];
    }];
    
    // testThatUnderRateLimitConnectionsImmediatelyCallsBack, in a case where we would be at the rate limit (and not) if the not started connection counted.
    [self startNOperations:[limiter rateLimit] - 1];
    // start the op that will decline opportunity to start.
    id cancelledOperation = [context protocolMock:@protocol(RHGRateLimitedRequestOperation)];
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(cancelledOperation) rateLimiterRequestsConnectionStart:limiter]; [builder will:returnBool(NO)];
    }];
    [limiter registerWaitingConnectionForRequestOperation:cancelledOperation];
    
    // when
    [limiter registerWaitingConnectionForRequestOperation:rateLimitedRequestOperation];
    
    // then
    assertContextSatisfied(context);
}

- (void)testThatNoConnectionsImmediatelyCallsBack
{
    // given
    [context checking:^(LRExpectationBuilder *builder) {
        [oneOf(rateLimitedRequestOperation) rateLimiterRequestsConnectionStart:limiter];
    }];
    
    // when
    [limiter registerWaitingConnectionForRequestOperation:rateLimitedRequestOperation];
    
    // then
    assertContextSatisfied(context);
}

- (void)testThatUnderRateLimitConnectionsImmediatelyCallsBack
{
    // given
    [context checking:^(LRExpectationBuilder *builder) {
        [oneOf(rateLimitedRequestOperation) rateLimiterRequestsConnectionStart:limiter];
    }];
    
    [self startNOperations:[limiter rateLimit] - 1];
    
    // when
    [limiter registerWaitingConnectionForRequestOperation:rateLimitedRequestOperation];
    
    // then
    assertContextSatisfied(context);
}

- (void)testThatAtRateLimitSchedulesRunningOneSecondAfterARequestFinishesAtRateLimit
{
    // given
    [context checking:^(LRExpectationBuilder *builder) {        
        [oneOf(performDelayedSelectorWrapper) performSelector:@selector(runWaitingConnectionsUpToRateLimit) withObject:nil afterDelay:1.0 onTarget:limiter]; // ideally, we should capture the SEL and call it without knowing what it is - and we should use a ImmedatePerformDelayedselectorWrapper to just call immediately, and then ask it to assert that the delay is == 1.0. and make sure it doesn't have a chain of performDelayedSelectorCalls.
    }];
    
    [self givenTheRequestOperationWaitsAtTheRateLimitForOtherOperations];
    [self whenAStartedRequestOperationFinishes];

    assertContextSatisfied(context);
}

- (void)testThatRunningWaitingConnectionsRunsAConnectionWhenItIsAllowedToRunStates
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(performDelayedSelectorWrapper) performSelector:@selector(runWaitingConnectionsUpToRateLimit) withObject:nil afterDelay:1.0 onTarget:limiter];
        
        [oneOf(rateLimitedRequestOperation) rateLimiterRequestsConnectionStart:limiter];
    }];
    
    [self givenTheRequestOperationWaitsAtTheRateLimitForOtherOperations];
    [self whenAStartedRequestOperationFinishes];
    [self whenTimePasses:1.0];
    
    [limiter runWaitingConnectionsUpToRateLimit];
    
    assertContextSatisfied(context);
}


- (void)testThatRunningWaitingConnectionsDoesNotRunAConnectionThatFinishedLessThan1SecondAgo
{
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(performDelayedSelectorWrapper) performSelector:@selector(runWaitingConnectionsUpToRateLimit) withObject:nil afterDelay:1.0 onTarget:limiter];
        
        [never(rateLimitedRequestOperation) rateLimiterRequestsConnectionStart:limiter];
    }];
    
    [self givenTheRequestOperationWaitsAtTheRateLimitForOtherOperations];
    [self whenAStartedRequestOperationFinishes];
    [self whenTimePasses:.9];
    
    [limiter runWaitingConnectionsUpToRateLimit];

    assertContextSatisfied(context);
}

#pragma mark - Given/When/Then
- (NSArray *)givenTheRequestOperationWaitsAtTheRateLimitForOtherOperations
{
    NSArray *started = [self startOperationsUpToRateLimit];
    [self whenTheRateLimitedRequestOperationWantsToStart];
    
    _otherRunningRequestOperations = [started mutableCopy];
    return started;
}

- (void)whenTheRateLimitedRequestOperationWantsToStart
{
    [limiter registerWaitingConnectionForRequestOperation:rateLimitedRequestOperation];
}

- (void)whenAStartedRequestOperationFinishes
{
    id opToFinish = [_otherRunningRequestOperations lastObject];
    [limiter requestOperationConnectionDidFinish:opToFinish];
    [_otherRunningRequestOperations removeObject:opToFinish];
}

- (void)whenARequestOperationFinishes:(id)operation
{
    [limiter requestOperationConnectionDidFinish:operation];
}

- (void)whenTimePasses:(NSTimeInterval)delta
{
    [self incrementCurrentTimestampBy:delta];
}

#pragma mark - Helpers
- (id)newRateLimitedOperationExpectingStart
{
    id mock = [self newRateLimitedOperation];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(mock) rateLimiterRequestsConnectionStart:limiter]; [builder will:returnBool(YES)];
    }];
    
    return mock;
}

- (id)newRateLimitedOperation
{
    id mock = [context protocolMock:@protocol(RHGRateLimitedRequestOperation)];
    return mock;
}

- (NSArray *)startOperationsUpToRateLimit
{
    return [self registerNOperationsAndExpectImmediateStart:[limiter rateLimit]];
}

- (NSArray *)startNOperations:(NSInteger)numberOfOperationsToStart
{
    return [self registerNOperationsAndExpectImmediateStart:numberOfOperationsToStart];
}

- (NSArray *)registerNOperationsAndExpectImmediateStart:(NSInteger)n
{
    NSMutableArray *operations = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; i++) {
        id anOperation = [self newRateLimitedOperationExpectingStart];
        [limiter registerWaitingConnectionForRequestOperation:anOperation];
        [operations addObject:anOperation];
    }
    
    return [NSArray arrayWithArray:operations];
}

#pragma mark - Time
- (void)incrementCurrentTimestampBy:(NSTimeInterval)delta
{
    [self setCurrentDate:[NSDate dateWithTimeInterval:delta sinceDate:_currentDate]];
}
     
     - (void)setCurrentTimestampSince1970To:(NSTimeInterval)timestamp
    {
        [self setCurrentDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    }
     
     - (void)setCurrentDate:(NSDate *)date
    {
        [context checking:^(LRExpectationBuilder *builder) {
            _currentDate = date;
            [allowing(currentDateWrapper) currentDate]; andReturn(_currentDate);
        }];
    }

@end
