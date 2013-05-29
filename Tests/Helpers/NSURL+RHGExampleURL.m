//
//  NSURL+RHGExampleURL.m
//  Phoenix
//
//  Created by Robert Gilliam on 5/25/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import "NSURL+RHGExampleURL.h"

@implementation NSURL (RHGExampleURL)

+ (id)rhg_exampleURL
{
    return [self URLWithString:@"http://www.example.com"];
}

@end
