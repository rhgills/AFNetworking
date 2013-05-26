//
//  RHGPerformDelayedSelectorWrapper.h
//  
//
//  Created by Robert Gilliam on 5/26/13.
//
//

#import <Foundation/Foundation.h>

@interface RHGPerformDelayedSelectorWrapper : NSObject

- (void)performSelector:(SEL)selector withObject:(id)object afterDelay:(NSTimeInterval)delay onTarget:(id)target;

@end
