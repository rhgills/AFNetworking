//
//  RHGRateLimiter.h
//  Phoenix
//
//  Created by Robert Gilliam on 5/22/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RGKit/RHGCurrentDateWrapper.h"
#import <RHGPerformDelayedSelectorWrapper.h>

@class AFURLConnectionOperation;
@class RHGRateLimiter;




@protocol RHGRateLimitedRequestOperation <NSObject>

@required
@property (weak) RHGRateLimiter *rateLimiter; // rateLimiter will retain 

// Returns YES if the connection was started, NO if the connection was not (and will never be)
// started. For example, return NO if the operation is already finished or cancelled.
- (BOOL)rateLimiterRequestsConnectionStart:(RHGRateLimiter *)theRateLimiter;

@end



// Listens for RHGRateLimitedURLConnectionOperationConnectionWillStartNotification and
// AFNetworkingOperationDidFinishNotification to update atRateLimit.
//
// Callers must -lock before checking rate limit, must only start a request if not atRateLimit, and must
// call -unlock afterwards.
@interface RHGRateLimiter : NSObject

- (instancetype)initWithCurrentDateWrapper:(id <RHGCurrentDateWrapper>)aCurrentDateWrapper performDelayedSelectorWrapper:(RHGPerformDelayedSelectorWrapper *)aPerformDelayedSelectorWrapper;
- (NSUInteger)rateLimit;

- (void)registerWaitingConnectionForRequestOperation:(AFURLConnectionOperation *)aRequestOperation;
- (void)requestOperationConnectionDidFinish:(AFURLConnectionOperation *)aRequestOperation;

// exposed to tests because LRMocky doesn't handle SEL params very well.
- (void)runWaitingConnectionsUpToRateLimit;

@end
