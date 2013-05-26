//
//  RHGRateLimiter.h
//  Phoenix
//
//  Created by Robert Gilliam on 5/22/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RHGCurrentDateWrapper.h"

@interface RHGRateLimiter : NSObject <NSLocking>

// - (instancetype)initWithQPSLimit:(NSInteger)qpsLimit; // hardcoded to 4.
- (instancetype)initWithCurrentDateWrapper:(id <RHGCurrentDateWrapper>)currentDateWrapper;

- (BOOL)atRateLimit;
- (NSUInteger)rateLimit;

- (void)tearDown; // workaround for memory management issues causing it to continue to observe notifications after we nil out the reference in the test case.

@end



@protocol RHGQPSLimitedRequestOperation <NSObject>

@required
@property (weak) RHGRateLimiter *rateLimiter; // rateLimiter will retain us.
- (BOOL)obeysRateLimiter;

@end
