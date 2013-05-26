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
@property id <RHGQPSLimitedRequestOperation> requestOperation;

// don't care
@property NSTimeInterval startTimestamp;
@property BOOL isRunning;




@end


@interface RHGRateLimiter ()

- (void)operationDidStart;
- (void)operationDidFinish;

- (void)connectionWillStartFromNotification:(NSNotification *)aNotification;
- (void)operationDidFinishFromNotification:(NSNotification *)aNotification;

@property (nonatomic, strong) id <RHGCurrentDateWrapper> currentDateWrapper;
@property NSUInteger runningOperations;

@property NSMutableSet *lastFourRequests;

@property (readonly) NSRecursiveLock *qpsLock;

@end


@implementation RHGRateLimiter

@synthesize currentDateWrapper = _currentDateWrapper;
@synthesize lastFourRequests = _lastFourRequests;


- (id)initWithCurrentDateWrapper:(id<RHGCurrentDateWrapper>)currentDateWrapper
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionWillStartFromNotification:) name:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(operationDidFinishFromNotification:) name:AFNetworkingOperationDidFinishNotification object:nil];
        
        _runningOperations = 0;
        _lastFourRequests = [[NSMutableSet alloc] initWithCapacity:[self rateLimit]];
        
        NSParameterAssert(currentDateWrapper);
        _currentDateWrapper = currentDateWrapper;
        
        _qpsLock = [[NSRecursiveLock alloc] init];
    }
    return self;
}



- (void)dealloc
{
    [self tearDown];
}

- (void)tearDown
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)connectionWillStartFromNotification:(NSNotification *)aNotification
{
    [self connectionWillStart:aNotification.object];
}

- (void)operationDidFinishFromNotification:(NSNotification *)aNotification
{
    [self operationDidFinish:aNotification.object];
}

- (BOOL)operationIsSubjectToRateLimiting:(id)operation
{
    if ([operation respondsToSelector:@selector(obeysRateLimiter)]) {
        return [operation performSelector:@selector(obeysRateLimiter)]; // workaround for LRMocky bug.
    }
    
    return NO;
}

- (void)connectionWillStart:(id)operation
{
    // This must only be called by callers under QPS lock?
    
    if (![self operationIsSubjectToRateLimiting:operation]) {
        return;
    }
    
    
    
//    NSParameterAssert([self atQPSLimit] == NO);
    if ([self atRateLimit]) {
        NSLog(@"connectionWillStart called in %@ when already at rate limit.", self);
    }
    
    [self willChangeValueForKey:PROPERTY(atRateLimit)];
    
    RHGRateLimiterRequestInfo *qpsInfo = [[RHGRateLimiterRequestInfo alloc] initWithRequestOperation:operation];
    [self insertOrReplaceOldestRequestInfoWithInfo:qpsInfo];
    
    self.runningOperations++;
    
    NSLog(@"Will start an operation. Triggering KVO change notification.");
    [self didChangeValueForKey:PROPERTY(atRateLimit)];
    NSLog(@"KVO change notification triggered.");
    
//    NSLog(@"Operation started. at rate limit? %@ is ready? %@ running operations %d last four %@", [self atQPSLimit] ? @"YES" : @"NO", [operation isReady] ? @"YES" : @"NO", self.runningOperations, self.lastFourRequests);
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

- (void)operationDidFinish:(AFHTTPRequestOperation *)operation
{
    if (![self operationIsSubjectToRateLimiting:operation]) {
        return;
    }
    
    RHGRateLimiterRequestInfo *info = [self infoForOperation:operation];
    info.finishDate = [self.currentDateWrapper currentDate];
    info.requestOperation = nil; // don't care about it anymore, break the retani cycle
    self.runningOperations--;
    
    [self lock]; // prevent rate limited reqeusts from starting, and changing [self atQPSLimit]
    
    NSLog(@"Operation finished. at rate limit? %@ running operations %d last four %@", [self atRateLimit] ? @"YES" : @"NO", self.runningOperations, self.lastFourRequests);
    
    if ([self atRateLimit]) {
        // this will change in 1 second.
        [self performSelector:@selector(markQPSLimitChanged) withObject:nil afterDelay:1.0];
    }
    
    [self unlock];
}

- (void)markQPSLimitChanged
{
    [self willChangeValueForKey:PROPERTY(atRateLimit)]; // this will make the before value wrong! but it can't be relied on anyway
                                                       // calling it one second before means no KVO notification is posted. clearly, not intended.
    [self didChangeValueForKey:PROPERTY(atRateLimit)];
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
    return (self.runningOperations + [[self requestsFinishedWithinTheLastSecond] count] >= [self rateLimit]);
}

- (NSSet *)requestsFinishedWithinTheLastSecond
{
    NSDate *currentDate = [self.currentDateWrapper currentDate];
    
    return [self.lastFourRequests rx_filterWithBlock:^BOOL(RHGRateLimiterRequestInfo *each) {
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


#pragma mark - NSLocking
- (void)lock
{
    [self.qpsLock lock];
}

- (void)unlock
{
    [self.qpsLock unlock];
}

@end




@implementation RHGRateLimiterRequestInfo

- (id)initWithRequestOperation:(id <RHGQPSLimitedRequestOperation>)aRequestOperation
{
    self = [super init];
    if (self) {
        NSParameterAssert(aRequestOperation);
        _requestOperation = aRequestOperation;
    }
    return self;
}



@end
