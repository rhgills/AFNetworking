//
//  RHGRateLimiter.m
//  Phoenix
//
//  Created by Robert Gilliam on 5/22/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import "RHGRateLimiter.h"
#import "RHGHelperMacros.h"
#import "AFNetworking.h"
#import "RXCollection.h"

@interface RHGRateLimiterRequestInfo : NSObject

- (id)initWithRequestOperation:(AFHTTPRequestOperation*)aRequestOperation;

@property (nonatomic, strong) NSDate *finishDate;
@property id <RHGRateLimitedRequestOperation> requestOperation;

// don't care
@property NSTimeInterval startTimestamp;
@property BOOL isRunning;




@end


@interface RHGRateLimiter ()

- (BOOL)atRateLimit;


- (void)operationDidStart;
- (void)operationDidFinish;

- (void)connectionWillStartFromNotification:(NSNotification *)aNotification;
- (void)operationDidFinishFromNotification:(NSNotification *)aNotification;

@property (nonatomic, strong, readonly) id <RHGCurrentDateWrapper> currentDateWrapper;
@property (nonatomic, strong, readonly) RHGPerformDelayedSelectorWrapper *performDelayedSelectorWrapper;

@property NSUInteger runningOperations;
@property NSMutableSet *lastFourRequests;
@property (nonatomic, readonly) NSRecursiveLock *lock;

@end






@implementation RHGRateLimiter {
    
    NSMutableArray *_waitingConnections;
}

@synthesize currentDateWrapper = _currentDateWrapper;
@synthesize performDelayedSelectorWrapper = _performDelayedSelectorWrapper;

@synthesize lastFourRequests = _lastFourRequests;
@synthesize lock = _lock;


- (id)initWithCurrentDateWrapper:(id <RHGCurrentDateWrapper>)aCurrentDateWrapper performDelayedSelectorWrapper:(RHGPerformDelayedSelectorWrapper*)aPerformDelayedSelectorWrapper
{
    self = [super init];
    if (self) {
        NSParameterAssert(aCurrentDateWrapper);
        _currentDateWrapper = aCurrentDateWrapper;
        
        NSParameterAssert(aPerformDelayedSelectorWrapper);
        _performDelayedSelectorWrapper = aPerformDelayedSelectorWrapper;
    
        
        _runningOperations = 0;
        _lastFourRequests = [[NSMutableSet alloc] initWithCapacity:[self rateLimit]];
        
        _lock = [[NSRecursiveLock alloc] init];
        
        _waitingConnections = [[NSMutableArray alloc] initWithCapacity:0];
    }
    return self;
}



- (void)dealloc
{

}


- (void)insertOrReplaceOldestRequestInfoWithInfo:(RHGRateLimiterRequestInfo *)info
{
    if (self.lastFourRequests.count >= [self rateLimit]) {
        // replace
        NSParameterAssert(self.lastFourRequests.count == [self rateLimit]);
        RHGRateLimiterRequestInfo *oldestInfo = [self requestInfoForOldestFinishDate];
        [self.lastFourRequests removeObject:oldestInfo];
    }
    
    [self.lastFourRequests addObject:info];
}

- (RHGRateLimiterRequestInfo *)requestInfoForOldestFinishDate
{
    __block RHGRateLimiterRequestInfo *oldestInfo = [self.lastFourRequests anyObject];
    [self.lastFourRequests enumerateObjectsUsingBlock:^(RHGRateLimiterRequestInfo *otherInfo, BOOL *stop) {
        if ([otherInfo.finishDate earlierDate:oldestInfo.finishDate] == otherInfo.finishDate ) {
            oldestInfo = otherInfo;
        }
    }];
    
    return oldestInfo;
}

- (RHGRateLimiterRequestInfo *)infoForOperation:(id)operation
{
    return [[self.lastFourRequests objectsPassingTest:^BOOL(RHGRateLimiterRequestInfo *otherInfo, BOOL *stop) {
        BOOL matches = (otherInfo.requestOperation == operation);
        if (matches) {
            *stop = YES;
        }
        return matches;
    }] anyObject];
}

- (BOOL)atRateLimit
{
    [self.lock lock];
    
    BOOL atRateLimit = (self.runningOperations + [[self requestsFinishedWithinTheLastSecond] count] >= [self rateLimit]);
    
    [self.lock unlock];
    
    return atRateLimit;
}

- (NSSet *)requestsFinishedWithinTheLastSecond
{
    NSDate *currentDate = [self.currentDateWrapper currentDate];
    
    return [self.lastFourRequests rx_filterWithBlock:^BOOL(RHGRateLimiterRequestInfo *each) {
        if (!each.finishDate) return NO;
        return [currentDate timeIntervalSinceDate:each.finishDate] < 1.0;
    }];
}

- (NSDate *)oldestFinishDate
{
    return [[self requestInfoForOldestFinishDate] finishDate];
}

- (NSUInteger)rateLimit
{
    return 4;
}

- (void)registerWaitingConnectionForRequestOperation:(id<RHGRateLimitedRequestOperation>)aRequestOperation
{
    [self.lock lock];
    
    if (![self atRateLimit]) {
        [self runWaitingConnectionForRequestOperation:aRequestOperation];
    }else{
        [_waitingConnections addObject:aRequestOperation];
    }
    
    [self.lock unlock];
}

- (void)requestOperationConnectionDidFinish:(id<RHGRateLimitedRequestOperation>)aRequestOperation
{
    [self.lock lock];
    
    RHGRateLimiterRequestInfo *info = [self infoForOperation:aRequestOperation];
    info.finishDate = [self.currentDateWrapper currentDate];
    info.requestOperation = nil; // don't care about it anymore, break the retani cycle
    self.runningOperations--;
    
    if ([self atRateLimit]) {
        // this will change in 1 second.
        [self.performDelayedSelectorWrapper performSelector:@selector(runWaitingConnectionsUpToRateLimit) withObject:nil afterDelay:1.0 onTarget:self];
    }
    
    [self.lock unlock];
}

- (void)requestOperationConnectionWillStart:(id <RHGRateLimitedRequestOperation>)aRequestOperation
{
    RHGRateLimiterRequestInfo *qpsInfo = [[RHGRateLimiterRequestInfo alloc] initWithRequestOperation:aRequestOperation];
    [self insertOrReplaceOldestRequestInfoWithInfo:qpsInfo];
    self.runningOperations++;
}

- (void)requestOperationConnectionDidStart:(id <RHGRateLimitedRequestOperation>)aRequestOperation
{
    [self.lock lock];
    
    [_waitingConnections removeLastObject];
    
    [self.lock unlock];
}

- (void)requestOperationConnectionDidDeclineToStart:(id <RHGRateLimitedRequestOperation>)aRequestOperation
{
        [self.lock lock];
    
    [_waitingConnections removeLastObject];
    
    RHGRateLimiterRequestInfo *info = [self infoForOperation:aRequestOperation];
    info.requestOperation = nil; // don't care about it anymore, break the retani cycle
    self.runningOperations--;
    
    if ([self atRateLimit]) {
        // this will change in 1 second.
        [self.performDelayedSelectorWrapper performSelector:@selector(runWaitingConnectionsUpToRateLimit) withObject:nil afterDelay:1.0 onTarget:self];
    }

        [self.lock unlock];
}

- (void)runWaitingConnectionsUpToRateLimit
{
    [self.lock lock];
    
    id <RHGRateLimitedRequestOperation> aWaitingRequestOperation = nil;
    while (![self atRateLimit] && (aWaitingRequestOperation = [_waitingConnections lastObject]) ) {
        [self runWaitingConnectionForRequestOperation:aWaitingRequestOperation];
    }
    
    [self.lock unlock];
}

- (void)runWaitingConnectionForRequestOperation:(id <RHGRateLimitedRequestOperation>)aRequestOperation
{
    [self.lock lock];
    
    [self requestOperationConnectionWillStart:aRequestOperation];
    BOOL started = [aRequestOperation rateLimiterRequestsConnectionStart:self];
    
    if (!started) {
        [self requestOperationConnectionDidDeclineToStart:aRequestOperation];
    }else{
        [self requestOperationConnectionDidStart:aRequestOperation];
    }
    
    [self.lock unlock];
}

@end




@implementation RHGRateLimiterRequestInfo

- (id)initWithRequestOperation:(id <RHGRateLimitedRequestOperation>)aRequestOperation
{
    self = [super init];
    if (self) {
        NSParameterAssert(aRequestOperation);
        _requestOperation = aRequestOperation;
    }
    return self;
}



@end
