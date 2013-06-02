//
//  RHGRateLimitedURLConnectionOperationTestCase.m
//  Phoenix
//
//  Created by Robert Gilliam on 5/24/13.
//  Copyright (c) 2013 Robert Gilliam. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>

#import <AFURLConnectionOperation.h>

#define LRMOCKY_SUGAR
#define LRMOCKY_SHORTHAND
#import <LRMocky.h>

#import "Helpers/NSURL+RHGExampleURL.h"
#import "Helpers/NSURLRequest+RHGExampleRequest.h"

#define HC_SHORTHAND
#import <OCHamcrest.h>

#import <OHHTTPStubs/OHHTTPStubs.h>

@interface AFURLConnectionOperationTests : SenTestCase

@end




@implementation AFURLConnectionOperationTests {
    AFURLConnectionOperation *connectionOperation;
    
    id rateLimiter;
    
    LRMockery *context;
    
    NSOperationQueue *operationQueue;
    
    BOOL _connectionWillStartNotificationReceived;
    id _connectionWillStartNotificationObject;
}

- (void)setUp
{
    context = mockery();
    
    // the latest specification is used, so this blanket can and will be overriden by tests.
    [self givenNetworkRequestsRespondWithA500];
    
    connectionOperation = [[AFURLConnectionOperation alloc] initWithRequest:[NSURLRequest rhg_exampleRequest]];
    rateLimiter = [context mock:[RHGRateLimiter class]];
    
    operationQueue = [[NSOperationQueue alloc] init];
    
    _connectionWillStartNotificationReceived = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionWillStartNotification:) name:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification object:nil];
}

- (void)connectionWillStartNotification:(NSNotification *)aNotification
{
    _connectionWillStartNotificationReceived = YES;
    _connectionWillStartNotificationObject = aNotification.object;
}

- (void)tearDown
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [connectionOperation cancel];
    
    [OHHTTPStubs removeAllRequestHandlers];
}

#pragma mark - Tests

#pragma mark - Without Rate Limiter
- (void)testStartsConnectionDirectly
{
    [connectionOperation setRateLimiter:nil];
    [self givenNetworkRequestsRespondWithA404];
    
    [context expectNotificationNamed:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification fromObject:connectionOperation userInfo:(id)anything()];
    
    
    [operationQueue addOperations:@[connectionOperation] waitUntilFinished:YES];
    
    
    assertContextSatisfied(context);
}

- (void)testIndicatesConnectionNotStartedWhenOperationNotStarted
{
    [connectionOperation setRateLimiter:nil];
    
    
    STAssertFalse([connectionOperation rateLimiterRequestsConnectionStart:rateLimiter], nil);
    
    
    assertContextSatisfied(context);
}

#pragma mark - With Rate Limiter
- (void)testAsksForRateLimiterCallback
{
    [connectionOperation setRateLimiter:rateLimiter];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [oneOf(rateLimiter) registerWaitingConnectionForRequestOperation:connectionOperation];
    }];
    
    
    [self startConnectionAndWaitUntilRegisteredAsWaitingWithRateLimiter];

    assertContextSatisfied(context);
}


- (void)testIndicatesConnectionNotStartedWhenOperationCancelledWhileWaiting
{
    [connectionOperation setRateLimiter:rateLimiter];
    
    [self startConnectionAndWaitUntilRegisteredAsWaitingWithRateLimiter];
    
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(rateLimiter) requestOperationConnectionDidFinish:connectionOperation];
    }];
    [connectionOperation cancel];
    
    
    BOOL started = [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
    assertThatBool(started, equalToBool(NO));
    
    assertContextSatisfied(context);
}

- (void)testIndicatesConnectionNotStartedWhenOperationFinished
{
    [connectionOperation setRateLimiter:rateLimiter];
    [self givenNetworkRequestsRespondWithA404];
    
    [self startUnderRateLimiterAndWaitUntilFinished];

    BOOL started = [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
    assertThatBool(started, equalToBool(NO));
    
    assertContextSatisfied(context);
}


- (void)testIndicatesConnectionNotStartedWhenConnectionAlreadyStartedAndOngoing
{
    [self givenNetworkRequestsDoNotComplete];
    [connectionOperation setRateLimiter:rateLimiter];
    
    [self startConnectionAndWaitUntilRegisteredAsWaitingWithRateLimiter];
    [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
    [self waitUntilConnectionWillStart];
    
    BOOL started = [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
    assertThatBool(started, equalToBool(NO));
}

- (void)testStartsConnectionWhenExpectingRateLimiterCallback
{
    [connectionOperation setRateLimiter:rateLimiter];
    [self givenNetworkRequestsRespondWithA404];
    
//    [context expectNotificationNamed:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification fromObject:connectionOperation userInfo:(id)anything()];
    [self startConnectionAndWaitUntilRegisteredAsWaitingWithRateLimiter];
    
    BOOL started = [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
    // wait until the connection notification is posted, or we time out
    waitUntil(^BOOL{
        return _connectionWillStartNotificationReceived;
    }); // might be inconsistent with a possible failure of the context expected notification, because of this being called first and returning before the 2nd one is called. not theoretical: this was observed!
//    [context waitUntilNotificationReceived:RHGRateLimitedURLConnectionOperationConnectionWillStartNotification fromObject:connectionOperation];
    
    assertThatBool(_connectionWillStartNotificationReceived, equalToBool(YES));
    assertThatBool(started, equalToBool(YES));
    assertContextSatisfied(context);
}

- (void)testThatItNotifiesTheRateLimiterWhenItSucceeds
{
    [connectionOperation setRateLimiter:rateLimiter];
    [self givenNetworkRequestsSucceed];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(rateLimiter) registerWaitingConnectionForRequestOperation:connectionOperation]; andThen(LRA_performBlock(^(NSInvocation *invocation) {
            [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
        }));
        
        [oneOf(rateLimiter) requestOperationConnectionDidFinish:connectionOperation];
    }];
    
    [operationQueue addOperations:@[connectionOperation] waitUntilFinished:YES];
    
    assertContextSatisfied(context);
}

// implemetation calls common -[finish] method.
//- (void)testThatItNotifiesTheRateLimiterWhenItFails
//{
//    
//}
//
//- (void)ThatItNotifiesTheRateLimiterWhenItIsCancelled
//{
//    
//}

#pragma mark - Helpers
- (void)givenNetworkRequestsSucceed
{
    [OHHTTPStubs addRequestHandler:^OHHTTPStubsResponse *(NSURLRequest *request, BOOL onlyCheck) {
        return [OHHTTPStubsResponse responseWithData:nil statusCode:200 responseTime:0.5 headers:nil];
    }];
}

- (void)waitUntilConnectionWillStart
{
    waitUntil(^BOOL{
        return _connectionWillStartNotificationReceived;
    });
    
    //    NSParameterAssert(_connectionWillStartNotificationReceived);
}

typedef BOOL(^WaitUntilBlock)();
void waitUntilWithTimeout(NSTimeInterval timeoutInterval, WaitUntilBlock block) {
    BOOL timedOut = NO;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    while (!block() && !timedOut) {
        [[NSRunLoop currentRunLoop] runMode:NSRunLoopCommonModes beforeDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        timedOut = (CFAbsoluteTimeGetCurrent() - start) > timeoutInterval;
    }
    
    if (timedOut) {
        [NSException raise:NSInternalInconsistencyException format:@"Wait until timed out."];
    }
}

void waitUntil(WaitUntilBlock block) {
    waitUntilWithTimeout(5.0, block);
}

- (void)startConnectionAndWaitUntilRegisteredAsWaitingWithRateLimiter
{
    __block BOOL operationWaiting = NO;
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(rateLimiter) registerWaitingConnectionForRequestOperation:connectionOperation]; andThen(LRA_performBlock(^(NSInvocation *invocation) {
            operationWaiting = YES;
        }));
    }];
    
    [connectionOperation start];
    waitUntil(^BOOL{
        return operationWaiting;
    });
    
//    STAssertTrue(receivedRequest, nil); // raiss an exception to stop the test, not a failure.
//    NSParameterAssert(operationWaiting);
}

- (void)givenNetworkRequestsRespondWithA404
{
    [OHHTTPStubs addRequestHandler:^OHHTTPStubsResponse *(NSURLRequest *request, BOOL onlyCheck) {
        return [OHHTTPStubsResponse responseWithError:[NSError errorWithDomain:NSURLErrorDomain code:404 userInfo:nil]];
    }];
}

- (void)givenNetworkRequestsRespondWithA500
{
    [OHHTTPStubs addRequestHandler:^OHHTTPStubsResponse *(NSURLRequest *request, BOOL onlyCheck) {
        return [OHHTTPStubsResponse responseWithError:[NSError errorWithDomain:NSURLErrorDomain code:500 userInfo:nil]];
    }];
}

- (void)startUnderRateLimiterAndWaitUntilFinished
{
    [connectionOperation setRateLimiter:rateLimiter];
    [self givenNetworkRequestsRespondWithA404];
    
    [context checking:^(LRExpectationBuilder *builder) {
        [allowing(rateLimiter) requestOperationConnectionDidFinish:connectionOperation];
    }];
    
    [self startConnectionAndWaitUntilRegisteredAsWaitingWithRateLimiter];
    [connectionOperation rateLimiterRequestsConnectionStart:rateLimiter];
    
    waitUntil(^BOOL{
        return connectionOperation.isFinished;
    });
    STAssertTrue(connectionOperation.isFinished, nil);
}

- (void)givenNetworkRequestsDoNotComplete
{
    [OHHTTPStubs addRequestHandler:^OHHTTPStubsResponse *(NSURLRequest *request, BOOL onlyCheck) {
        return [OHHTTPStubsResponse responseWithData:nil statusCode:404 responseTime:20.0 headers:nil]; // problem w/ leakage?
    }];
}


@end
