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
#import "DDLog.h"

static int ddLogLevel = LOG_LEVEL_WARN;

@interface RHGRateLimiterRequestInfo : NSObject

- (id)initWithRequestOperation:(AFURLConnectionOperation *)aRequestOperation;

@property (nonatomic, strong) NSDate *finishDate;
@property AFURLConnectionOperation * requestOperation;

// don't care

@property BOOL isRunning;


// debug
@property NSDate *startDate;
@property NSSet *lastFourRequestsAtStart;
@property NSUInteger numberOfRunningConnectionsAtStart;

@end


@interface RHGRateLimiter ()

- (BOOL)atRateLimit;

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
        if (otherInfo.finishDate == nil) {
            // can't possibly be earlier.
        }else if (oldestInfo.finishDate == nil) {
            oldestInfo = otherInfo;
        }else if ([otherInfo.finishDate earlierDate:oldestInfo.finishDate] == otherInfo.finishDate) {
            oldestInfo = otherInfo;
        }
    }];
    
    NSParameterAssert(oldestInfo.finishDate);
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

- (void)registerWaitingConnectionForRequestOperation:(AFURLConnectionOperation *)aRequestOperation
{
    [self.lock lock];
    
    if (![self atRateLimit]) {
        [self runWaitingConnectionForRequestOperation:aRequestOperation];
    }else{
        [_waitingConnections addObject:aRequestOperation];
    }
    
    [self.lock unlock];
}

- (BOOL)responseWasOverRateLimit:(AFURLConnectionOperation *)aRequestOperation
{
    if (![aRequestOperation isKindOfClass:[AFJSONRequestOperation class]]) {
        return NO;
    }
    
    AFJSONRequestOperation *jsonOp = (AFJSONRequestOperation *)aRequestOperation;
    
    // response string: '{"error":true,"status":{"status_code":403,"message":"Over queries per second limit"}}'.
    NSString *message = [[jsonOp.responseJSON objectForKey:@"status"] objectForKey:@"message"];
    return (jsonOp.response.statusCode == 403 && [message isEqualToString:@"Over queries per second limit"]);
}

- (void)requestOperationConnectionDidFinish:(AFURLConnectionOperation *)aRequestOperation
{
    [self.lock lock];

    DDLogInfo(@"finished: %@.", [aRequestOperation request]);
    
    NSParameterAssert([self runningOperations] == [self runningOperationsFromLastFourRequestInfo]);
    
    RHGRateLimiterRequestInfo *info = [self infoForOperation:aRequestOperation];
    info.finishDate = [self.currentDateWrapper currentDate];
//    info.requestOperation = nil; // don't care about it anymore, break the retani cycle
    self.runningOperations--;
    
    NSParameterAssert([self runningOperations] == [self runningOperationsFromLastFourRequestInfo]);
    
    if ([self responseWasOverRateLimit:aRequestOperation]) {
        DDLogWarn(@"Request operation finished with an over rate limit error.");
        DDLogWarn(@"When started, there were:");
        DDLogWarn(@"%d running operations.", info.numberOfRunningConnectionsAtStart);
        DDLogWarn(@"last four requests: %@.", info.lastFourRequestsAtStart);
        DDLogWarn(@"----------------------------------------------------------");
    }
    
    if ([self atRateLimit]) {
        // this will change in 1 second.
        [self.performDelayedSelectorWrapper performSelector:@selector(runWaitingConnectionsUpToRateLimit) withObject:nil afterDelay:1.0 onTarget:self];
    }else{
        if (_waitingConnections.count) {
            // the operation that just finished has finished after (or equal to) 1 second has elapsed since the previous finished operation, but before runWaitingConnectionsUpToRateLimit has been called by performDelayedSelector.
            // this can happen if the run loop is busy, as the delay of 1.0 specified is a minimum, not a guarantee.
            DDLogInfo(@"%@ called one second after previous finish date, but before the performDelayedSelector call.", THIS_METHOD);
            DDLogInfo(@"Running waiting connections directly.");
        }
    
        // there may be none, but just run anyway.
        [self runWaitingConnectionsUpToRateLimit];
    }
    
    [self.lock unlock];
}

- (void)requestOperationConnectionWillStart:(AFURLConnectionOperation *)aRequestOperation
{
    [_waitingConnections removeLastObject];
}

- (NSUInteger)runningOperationsFromLastFourRequestInfo
{
    NSSet *runningOperations = [_lastFourRequests rx_filterWithBlock:^BOOL(RHGRateLimiterRequestInfo *each) {
        return (each.finishDate == nil);
    }];
    
    return [runningOperations count];
}

- (void)addDebuggingInfo:(RHGRateLimiterRequestInfo *)qpsInfo
{
    qpsInfo.numberOfRunningConnectionsAtStart = self.runningOperations;
    qpsInfo.startDate = [self.currentDateWrapper currentDate];
    
    // deep copy
    NSMutableSet *lastFourAtStart = [NSMutableSet setWithCapacity:_lastFourRequests.count];
    for (id obj in _lastFourRequests) {
        [lastFourAtStart addObject:[obj copy]];
    }
    qpsInfo.lastFourRequestsAtStart = lastFourAtStart;
}

- (void)requestOperationConnectionDidStart:(AFURLConnectionOperation *)aRequestOperation
{
    [self.lock lock];
    
    RHGRateLimiterRequestInfo *qpsInfo = [[RHGRateLimiterRequestInfo alloc] initWithRequestOperation:aRequestOperation];
    [self addDebuggingInfo:qpsInfo];
    
    NSParameterAssert([self runningOperations] == [self runningOperationsFromLastFourRequestInfo]);
    
    [self insertOrReplaceOldestRequestInfoWithInfo:qpsInfo];
    self.runningOperations++;
    
    NSParameterAssert([self runningOperations] == [self runningOperationsFromLastFourRequestInfo]);
    
    [self.lock unlock];
}

- (void)requestOperationConnectionDidDeclineToStart:(AFURLConnectionOperation *)aRequestOperation
{
    
}

- (void)runWaitingConnectionsUpToRateLimit
{
    [self.lock lock];
    
    DDLogVerbose(@"%@ called with %d waiting connections.", THIS_METHOD, _waitingConnections.count);
    
    AFURLConnectionOperation * aWaitingRequestOperation = nil;
    while (![self atRateLimit] && (aWaitingRequestOperation = [_waitingConnections lastObject]) ) {
        [self runWaitingConnectionForRequestOperation:aWaitingRequestOperation];
    }
    
    [self.lock unlock];
}

- (void)runWaitingConnectionForRequestOperation:(AFURLConnectionOperation *)aRequestOperation
{
    [self.lock lock];
    
    AFURLConnectionOperation *httpOperation = (id)aRequestOperation;
    DDLogInfo(@"running waiting request for: %@.", [httpOperation request]);
    
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

- (id)initWithRequestOperation:(AFURLConnectionOperation *)aRequestOperation
{
    self = [super init];
    if (self) {
        NSParameterAssert(aRequestOperation);
        _requestOperation = aRequestOperation;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@:%p finishDate: %@>", [self class], self, [self finishDate]];
}

- (id)copyWithZone:(NSZone *)zone
{
    RHGRateLimiterRequestInfo *copy = [[RHGRateLimiterRequestInfo alloc] initWithRequestOperation:self.requestOperation];
    copy.finishDate = self.finishDate;
    
    // deep copy
//    NSMutableSet *lastFourAtStart = [NSMutableSet setWithCapacity:self.lastFourRequestsAtStart.count];
//    for (id obj in self.lastFourRequestsAtStart) {
//        [lastFourAtStart addObject:[obj copy]];
//    }
//    copy.lastFourRequestsAtStart = lastFourAtStart;
    
    copy.startDate = [self startDate];
    copy.numberOfRunningConnectionsAtStart = self.numberOfRunningConnectionsAtStart;
    
    return copy;
}

@end
