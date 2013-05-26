//
//  RHGRateLimiter.h
//  Phoenix
//
//  Created by Robert Gilliam on 5/22/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RHGCurrentDateWrapper.h"
#import "RHGPerformDelayedSelectorWrapper.h"

@interface RHGRateLimiter : NSObject <NSLocking>

- (instancetype)initWithCurrentDateWrapper:(id <RHGCurrentDateWrapper>)aCurrentDateWrapper performDelayedSelectorWrapper:(RHGPerformDelayedSelectorWrapper *)aPerformDelayedSelectorWrapper;


- (BOOL)atRateLimit;
- (NSUInteger)rateLimit;

- (void)tearDown; // workaround for memory management issues causing it to continue to observe notifications after we nil out the reference in the test case.

@end



@protocol RHGRateLimitedRequestOperation <NSObject>

@required
@property (weak) RHGRateLimiter *rateLimiter; // rateLimiter will retain us.
- (BOOL)obeysRateLimiter;

@end


extern NSString * const RHGRateLimiterDidLiftRateLimitNotification;
