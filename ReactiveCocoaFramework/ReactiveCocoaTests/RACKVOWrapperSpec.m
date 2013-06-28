//
//  RACKVOWrapperSpec.m
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2012-08-07.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACKVOWrapper.h"

#import "EXTKeyPathCoding.h"
#import "NSObject+RACDeallocating.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACKVOTrampoline.h"
#import "RACTestObject.h"

@interface RACTestOperation : NSOperation
@end

// The name of the examples.
static NSString * const RACKVOWrapperExamples = @"RACKVOWrapperExamples";

// A block that returns an object to observe in the examples.
static NSString * const RACKVOWrapperExamplesTargetBlock = @"RACKVOWrapperExamplesTargetBlock";

// The key path to observe in the examples.
//
// The key path must have at least one weak property in it.
static NSString * const RACKVOWrapperExamplesKeyPath = @"RACKVOWrapperExamplesKeyPath";

// A block that changes the value of a weak property in the observed key path.
// The block is passed the object the example is observing and the new value the
// weak property should be changed to.
static NSString * const RACKVOWrapperExamplesChangeBlock = @"RACKVOWrapperExamplesChangeBlock";

// A block that returns a valid value for the weak property changed by
// RACKVOWrapperExamplesChangeBlock. The value must deallocate
// normally.
static NSString * const RACKVOWrapperExamplesValueBlock = @"RACKVOWrapperExamplesValueBlock";

// Whether RACKVOWrapperExamplesChangeBlock changes the value
// of the last key path component in the key path directly.
static NSString * const RACKVOWrapperExamplesChangesValueDirectly = @"RACKVOWrapperExamplesChangesValueDirectly";

SharedExampleGroupsBegin(RACKVOWrapperExamples)

sharedExamplesFor(RACKVOWrapperExamples, ^(NSDictionary *data) {
	__block NSObject *target = nil;
	__block NSString *keyPath = nil;
	__block void (^changeBlock)(NSObject *, id) = nil;
	__block id (^valueBlock)(void) = nil;
	__block BOOL changesValueDirectly = NO;

	__block NSUInteger priorCallCount = 0;
	__block NSUInteger posteriorCallCount = 0;
	__block BOOL priorTriggeredByLastKeyPathComponent = NO;
	__block BOOL posteriorTriggeredByLastKeyPathComponent = NO;
	__block BOOL posteriorTriggeredByDeallocation = NO;
	__block void (^callbackBlock)(id, NSDictionary *) = nil;

	beforeEach(^{
		NSObject * (^targetBlock)(void) = data[RACKVOWrapperExamplesTargetBlock];
		target = targetBlock();
		keyPath = data[RACKVOWrapperExamplesKeyPath];
		changeBlock = data[RACKVOWrapperExamplesChangeBlock];
		valueBlock = data[RACKVOWrapperExamplesValueBlock];
		changesValueDirectly = [data[RACKVOWrapperExamplesChangesValueDirectly] boolValue];

		priorCallCount = 0;
		posteriorCallCount = 0;

		callbackBlock = [^(id value, NSDictionary *change) {
			if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
				priorTriggeredByLastKeyPathComponent = [change[RACKeyValueChangeLastPathComponent] boolValue];
				++priorCallCount;
				return;
			}
			posteriorTriggeredByLastKeyPathComponent = [change[RACKeyValueChangeLastPathComponent] boolValue];
			posteriorTriggeredByDeallocation = [change[RACKeyValueChangeDeallocation] boolValue];
			++posteriorCallCount;
		} copy];
	});

	afterEach(^{
		target = nil;
		keyPath = nil;
		changeBlock = nil;
		valueBlock = nil;
		changesValueDirectly = NO;

		callbackBlock = nil;
	});

	it(@"should not call the callback block on add", ^{
		[target rac_observeKeyPath:keyPath options:NSKeyValueObservingOptionPrior observer:nil block:callbackBlock];
		expect(priorCallCount).to.equal(0);
		expect(posteriorCallCount).to.equal(0);
	});

	it(@"should call the callback block twice per change, once prior and once posterior", ^{
		[target rac_observeKeyPath:keyPath options:NSKeyValueObservingOptionPrior observer:nil block:callbackBlock];
		priorCallCount = 0;
		posteriorCallCount = 0;

		id value1 = valueBlock();
		changeBlock(target, value1);
		expect(priorCallCount).to.equal(1);
		expect(posteriorCallCount).to.equal(1);
		expect(priorTriggeredByLastKeyPathComponent).to.equal(changesValueDirectly);
		expect(posteriorTriggeredByLastKeyPathComponent).to.equal(changesValueDirectly);
		expect(posteriorTriggeredByDeallocation).to.beFalsy();

		id value2 = valueBlock();
		changeBlock(target, value2);
		expect(priorCallCount).to.equal(2);
		expect(posteriorCallCount).to.equal(2);
		expect(priorTriggeredByLastKeyPathComponent).to.equal(changesValueDirectly);
		expect(posteriorTriggeredByLastKeyPathComponent).to.equal(changesValueDirectly);
		expect(posteriorTriggeredByDeallocation).to.beFalsy();
	});

	it(@"should call the callback block with NSKeyValueChangeNotificationIsPriorKey set before the value is changed, and not set after the value is changed", ^{
		__block BOOL priorCalled = NO;
		__block BOOL posteriorCalled = NO;
		__block id priorValue = nil;
		__block id posteriorValue = nil;

		id value1 = valueBlock();
		changeBlock(target, value1);
		[target rac_observeKeyPath:keyPath options:NSKeyValueObservingOptionPrior observer:nil block:^(id value, NSDictionary *change) {
			if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
				priorCalled = YES;
				priorValue = value;
				expect(posteriorCalled).to.beFalsy();
				return;
			}
			posteriorCalled = YES;
			posteriorValue = value;
			expect(priorCalled).to.beTruthy();
		}];

		id value2 = valueBlock();
		changeBlock(target, value2);
		expect(priorCalled).to.beTruthy();
		expect(priorValue).to.equal(value1);
		expect(posteriorCalled).to.beTruthy();
		expect(posteriorValue).to.equal(value2);
	});

	it(@"should not call the callback block after it's been disposed", ^{
		RACDisposable *disposable = [target rac_observeKeyPath:keyPath options:NSKeyValueObservingOptionPrior observer:nil block:callbackBlock];
		priorCallCount = 0;
		posteriorCallCount = 0;

		[disposable dispose];
		expect(priorCallCount).to.equal(0);
		expect(posteriorCallCount).to.equal(0);

		id value = valueBlock();
		changeBlock(target, value);
		expect(priorCallCount).to.equal(0);
		expect(posteriorCallCount).to.equal(0);
	});

	it(@"should call the callback block only once with NSKeyValueChangeNotificationIsPriorKey not set when the value is deallocated", ^{
		__block BOOL valueDidDealloc = NO;

		[target rac_observeKeyPath:keyPath options:NSKeyValueObservingOptionPrior observer:nil block:callbackBlock];

		@autoreleasepool {
			NSObject *value __attribute__((objc_precise_lifetime)) = valueBlock();
			[value.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
				valueDidDealloc = YES;
			}]];

			changeBlock(target, value);
			priorCallCount = 0;
			posteriorCallCount = 0;
		}

		expect(valueDidDealloc).to.beTruthy();
		expect(priorCallCount).to.equal(0);
		expect(posteriorCallCount).to.equal(1);
		expect(posteriorTriggeredByDeallocation).to.beTruthy();
	});
});

SharedExampleGroupsEnd

SpecBegin(RACKVOWrapper)

describe(@"-rac_observeKeyPath:options:observer:block:", ^{
	describe(@"on simple keys", ^{
		NSObject * (^targetBlock)(void) = ^{
			return [[RACTestObject alloc] init];
		};

		void (^changeBlock)(RACTestObject *, id) = ^(RACTestObject *target, id value) {
			target.weakTestObjectValue = value;
		};

		id (^valueBlock)(void) = ^{
			return [[RACTestObject alloc] init];
		};

		itShouldBehaveLike(RACKVOWrapperExamples, @{
											 RACKVOWrapperExamplesTargetBlock: targetBlock,
											 RACKVOWrapperExamplesKeyPath: @keypath(RACTestObject.new, weakTestObjectValue),
											 RACKVOWrapperExamplesChangeBlock: changeBlock,
											 RACKVOWrapperExamplesValueBlock: valueBlock,
											 RACKVOWrapperExamplesChangesValueDirectly: @YES
											 });
	});

	describe(@"on composite key paths'", ^{
		describe(@"last key path components", ^{
			NSObject *(^targetBlock)(void) = ^{
				RACTestObject *object = [[RACTestObject alloc] init];
				object.strongTestObjectValue = [[RACTestObject alloc] init];
				return object;
			};

			void (^changeBlock)(RACTestObject *, id) = ^(RACTestObject *target, id value) {
				target.strongTestObjectValue.weakTestObjectValue = value;
			};

			id (^valueBlock)(void) = ^{
				return [[RACTestObject alloc] init];
			};

			itShouldBehaveLike(RACKVOWrapperExamples, @{
												 RACKVOWrapperExamplesTargetBlock: targetBlock,
												 RACKVOWrapperExamplesKeyPath: @keypath(RACTestObject.new, strongTestObjectValue.weakTestObjectValue),
												 RACKVOWrapperExamplesChangeBlock: changeBlock,
												 RACKVOWrapperExamplesValueBlock: valueBlock,
												 RACKVOWrapperExamplesChangesValueDirectly: @YES
												 });
		});

		describe(@"intermediate key path components", ^{
			NSObject *(^targetBlock)(void) = ^{
				return [[RACTestObject alloc] init];
			};

			void (^changeBlock)(RACTestObject *, id) = ^(RACTestObject *target, id value) {
				target.weakTestObjectValue = value;
			};

			id (^valueBlock)(void) = ^{
				RACTestObject *object = [[RACTestObject alloc] init];
				object.strongTestObjectValue = [[RACTestObject alloc] init];
				return object;
			};

			itShouldBehaveLike(RACKVOWrapperExamples, @{
												 RACKVOWrapperExamplesTargetBlock: targetBlock,
												 RACKVOWrapperExamplesKeyPath: @keypath([[RACTestObject alloc] init], weakTestObjectValue.strongTestObjectValue),
												 RACKVOWrapperExamplesChangeBlock: changeBlock,
												 RACKVOWrapperExamplesValueBlock: valueBlock,
												 RACKVOWrapperExamplesChangesValueDirectly: @NO
												 });
		});
	});
	
	it(@"should add and remove an observer", ^{
		NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{}];
		expect(operation).notTo.beNil();

		__block BOOL notified = NO;
		RACDisposable *disposable = [operation rac_observeKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew observer:self block:^(id value, NSDictionary *change) {
			expect([change objectForKey:NSKeyValueChangeNewKey]).to.equal(@YES);

			expect(notified).to.beFalsy();
			notified = YES;
		}];

		expect(disposable).notTo.beNil();

		[operation start];
		[operation waitUntilFinished];

		expect(notified).will.beTruthy();
	});

	it(@"should accept a nil observer", ^{
		NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{}];
		RACDisposable *disposable = [operation rac_observeKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew observer:nil block:^(id value, NSDictionary *change) {}];

		expect(disposable).notTo.beNil();
	});

	it(@"automatically stops KVO on subclasses when the target deallocates", ^{
		void (^testKVOOnSubclass)(Class targetClass, id observer) = ^(Class targetClass, id observer) {
			__weak id weakTarget = nil;
			__weak id identifier = nil;

			@autoreleasepool {
				// Create an observable target that we control the memory management of.
				CFTypeRef target = CFBridgingRetain([[targetClass alloc] init]);
				expect(target).notTo.beNil();

				weakTarget = (__bridge id)target;
				expect(weakTarget).notTo.beNil();

				identifier = [(__bridge id)target rac_observeKeyPath:@"isFinished" options:0 observer:observer block:^(id value, NSDictionary *change) {}];
				expect(identifier).notTo.beNil();

				CFRelease(target);
			}

			expect(weakTarget).to.beNil();
			expect(identifier).to.beNil();
		};

		it (@"stops KVO on NSObject subclasses", ^{
			testKVOOnSubclass(NSOperation.class, self);
		});

		it(@"stops KVO on subclasses of already-swizzled classes", ^{
			testKVOOnSubclass(RACTestOperation.class, self);
		});

		it (@"stops KVO on NSObject subclasses even with a nil observer", ^{
			testKVOOnSubclass(NSOperation.class, nil);
		});

		it(@"stops KVO on subclasses of already-swizzled classes even with a nil observer", ^{
			testKVOOnSubclass(RACTestOperation.class, nil);
		});
	});

	it(@"should automatically stop KVO when the observer deallocates", ^{
		__weak id weakObserver = nil;
		__weak id identifier = nil;

		NSOperation *operation = [[NSOperation alloc] init];

		@autoreleasepool {
			// Create an observer that we control the memory management of.
			CFTypeRef observer = CFBridgingRetain([[NSOperation alloc] init]);
			expect(observer).notTo.beNil();

			weakObserver = (__bridge id)observer;
			expect(weakObserver).notTo.beNil();

			identifier = [operation rac_observeKeyPath:@"isFinished" options:0 observer:(__bridge id)observer block:^(id value, NSDictionary *change) {}];
			expect(identifier).notTo.beNil();

			CFRelease(observer);
		}

		expect(weakObserver).to.beNil();
		expect(identifier).to.beNil();
	});

	it(@"should stop KVO when the observer is disposed", ^{
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		__block NSString *name = nil;

		RACDisposable *disposable = [queue rac_observeKeyPath:@"name" options:0 observer:self block:^(id value, NSDictionary *change) {
			name = queue.name;
		}];

		queue.name = @"1";
		expect(name).to.equal(@"1");
		[disposable dispose];
		queue.name = @"2";
		expect(name).to.equal(@"1");
	});

	it(@"should distinguish between observers being disposed", ^{
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		__block NSString *name1 = nil;
		__block NSString *name2 = nil;

		RACDisposable *disposable = [queue rac_observeKeyPath:@"name" options:0 observer:self block:^(id value, NSDictionary *change) {
			name1 = queue.name;
		}];
		[queue rac_observeKeyPath:@"name" options:0 observer:self block:^(id value, NSDictionary *change) {
			name2 = queue.name;
		}];

		queue.name = @"1";
		expect(name1).to.equal(@"1");
		expect(name2).to.equal(@"1");
		[disposable dispose];
		queue.name = @"2";
		expect(name1).to.equal(@"1");
		expect(name2).to.equal(@"2");
	});
});

SpecEnd

@implementation RACTestOperation
@end
