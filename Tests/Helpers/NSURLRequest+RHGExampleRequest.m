//
//  NSURLRequest+RHGExampleRequest.m
//  Phoenix
//
//  Created by Robert Gilliam on 5/25/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import "NSURLRequest+RHGExampleRequest.h"

@implementation NSURLRequest (RHGExampleRequest)

+ (id)rhg_exampleRequest
{
    return [self requestWithURL:[NSURL rhg_exampleURL]];
}

@end
