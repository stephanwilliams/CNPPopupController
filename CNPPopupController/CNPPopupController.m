//
//  CNPPopupController.m
//  CNPPopupController
//
//  Created by Carson Perrotti on 2014-09-28.
//  Copyright (c) 2014 Carson Perrotti. All rights reserved.
//  Modifications copyright (c) 2016 Stephan Williams.
//

#import "CNPPopupController.h"

#define CNP_SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define CNP_IS_IPAD   (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)

static inline UIViewAnimationOptions UIViewAnimationCurveToAnimationOptions(UIViewAnimationCurve curve)
{
    return curve << 16;
}

@interface CNPPopupView : UIView

@property CGFloat contentVerticalPadding;
@property UIEdgeInsets popupContentInsets;

- (CGSize)calculateContentSizeThatFits:(CGSize)size andUpdateLayout:(BOOL)update;

@end

@implementation CNPPopupView

@synthesize contentVerticalPadding, popupContentInsets;

- (CGSize)calculateContentSizeThatFits:(CGSize)size andUpdateLayout:(BOOL)update
{
    UIEdgeInsets inset = self.popupContentInsets;
    size.width -= (inset.left + inset.right);
    size.height -= (inset.top + inset.bottom);
    
    CGSize result = CGSizeMake(0, inset.top);
    for (UIView *view in self.subviews)
    {
        view.autoresizingMask = UIViewAutoresizingNone;
        if (!view.hidden)
        {
            CGSize _size = view.frame.size;
            if (CGSizeEqualToSize(_size, CGSizeZero))
            {
                _size = [view sizeThatFits:size];
                _size.width = size.width;
                if (update) view.frame = CGRectMake(inset.left, result.height, _size.width, _size.height);
            }
            else {
                if (update) {
                    view.frame = CGRectMake(0, result.height, _size.width, _size.height);
                }
            }
            result.height += _size.height + self.contentVerticalPadding;
            result.width = MAX(result.width, _size.width);
        }
    }

    result.height -= self.contentVerticalPadding;
    result.width += inset.left + inset.right;
    result.height = MIN(INFINITY, MAX(0.0f, result.height + inset.bottom));

    if (update) {
        for (UIView *view in self.subviews) {
            view.frame = CGRectMake((result.width - view.frame.size.width) * 0.5, view.frame.origin.y, view.frame.size.width, view.frame.size.height);
        }

        self.frame = CGRectMake(0, 0, result.width, result.height);
    }
    
    NSLog(@"NEW SIZE: %@", NSStringFromCGSize(result));

    return result;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    NSLog(@"size that fits");
    return [self calculateContentSizeThatFits:size andUpdateLayout:NO];
}

- (void)layoutSubviews {
    NSLog(@"layout subviews");
    [super layoutSubviews];
    [self calculateContentSizeThatFits:self.frame.size andUpdateLayout:YES];
}

@end

@interface CNPPopupController () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIWindow *applicationWindow;
@property (nonatomic, strong) UIView *maskView;
@property (nonatomic, strong) UITapGestureRecognizer *backgroundTapRecognizer;
//@property (nonatomic, strong) CNPPopupView *popupView;
@property (nonatomic, strong) NSArray *views;
@property (nonatomic) BOOL dismissAnimated;

@end

@implementation CNPPopupController

- (instancetype)initWithContents:(NSArray *)contents {
    self = [super init];
    if (self) {
        
        self.views = contents;
        
        self.view = [[CNPPopupView alloc] initWithFrame:CGRectZero];
        self.view.backgroundColor = [UIColor whiteColor];
        self.view.clipsToBounds = YES;
        
        self.maskView = [[UIView alloc] initWithFrame:self.applicationWindow.bounds];
        self.maskView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
        self.backgroundTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundTapGesture:)];
        self.backgroundTapRecognizer.delegate = self;
        [self.maskView addGestureRecognizer:self.backgroundTapRecognizer];
        [self.maskView addSubview:self.view];
        
        self.theme = [CNPPopupTheme defaultTheme];

        [self addPopupContents];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
        
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationWillChange)
                                                     name:UIApplicationWillChangeStatusBarOrientationNotification
                                                   object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationChanged)
                                                     name:UIApplicationDidChangeStatusBarOrientationNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)orientationWillChange {
    
    [UIView animateWithDuration:0.3 animations:^{
        self.maskView.frame = self.applicationWindow.bounds;
        self.view.center = [self endingPoint];
    }];
}

- (void)orientationChanged {
    
    UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
    CGFloat angle = CNP_UIInterfaceOrientationAngleOfOrientation(statusBarOrientation);
    CGAffineTransform transform = CGAffineTransformMakeRotation(angle);
    
    [UIView animateWithDuration:0.3 animations:^{
        self.maskView.frame = self.applicationWindow.bounds;
        self.view.center = [self endingPoint];
        if (CNP_SYSTEM_VERSION_LESS_THAN(@"8.0")) {
            self.view.transform = transform;
        }
    }];
}

CGFloat CNP_UIInterfaceOrientationAngleOfOrientation(UIInterfaceOrientation orientation)
{
    CGFloat angle;
    
    switch (orientation)
    {
        case UIInterfaceOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            angle = -M_PI_2;
            break;
        case UIInterfaceOrientationLandscapeRight:
            angle = M_PI_2;
            break;
        default:
            angle = 0.0;
            break;
    }
    
    return angle;
}


#pragma mark - Theming

- (void)applyTheme {
    if (self.theme.popupStyle == CNPPopupStyleFullscreen) {
        self.theme.presentationStyle = CNPPopupPresentationStyleFadeIn;
    }
    if (self.theme.popupStyle == CNPPopupStyleActionSheet) {
        self.theme.presentationStyle = CNPPopupPresentationStyleSlideInFromBottom;
    }
    self.view.layer.cornerRadius = self.theme.popupStyle == CNPPopupStyleCentered?self.theme.cornerRadius:0;
    self.view.backgroundColor = self.theme.backgroundColor;
    ((CNPPopupView *)self.view).contentVerticalPadding = self.theme.contentVerticalPadding;
    ((CNPPopupView *)self.view).popupContentInsets = self.theme.popupContentInsets;
    UIColor *maskBackgroundColor;
    if (self.theme.popupStyle == CNPPopupStyleFullscreen) {
        maskBackgroundColor = self.view.backgroundColor;
    }
    else {
        maskBackgroundColor = self.theme.maskType == CNPPopupMaskTypeClear?[UIColor clearColor] : [UIColor colorWithWhite:0.0 alpha:0.7];
    }
    self.maskView.backgroundColor = maskBackgroundColor;
}

#pragma mark - Popup Building

- (void)addPopupContents {
    for (UIView *view in self.views)
    {
        [self.view addSubview:view];
    }
}

#pragma mark - Keyboard 

- (void)keyboardWillShow:(NSNotification*)notification
{
    if (self.theme.movesAboveKeyboard) {
        CGRect frame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        frame = [self.view convertRect:frame fromView:nil];
        NSTimeInterval duration = [[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        UIViewAnimationCurve curve = [[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
        
        [self keyboardWithEndFrame:frame willShowAfterDuration:duration withOptions:UIViewAnimationCurveToAnimationOptions(curve)];
    }
}

- (void)keyboardWithEndFrame:(CGRect)keyboardFrame willShowAfterDuration:(NSTimeInterval)duration withOptions:(UIViewAnimationOptions)options
{
    CGRect popupViewIntersection = CGRectIntersection(self.view.frame, keyboardFrame);
    
    if (popupViewIntersection.size.height > 0) {
        CGRect maskViewIntersection = CGRectIntersection(self.maskView.frame, keyboardFrame);
        
        [UIView animateWithDuration:duration delay:0.0f options:options animations:^{
            self.view.center = CGPointMake(self.view.center.x, (CGRectGetHeight(self.maskView.frame) - maskViewIntersection.size.height) / 2);
        } completion:nil];
    }
}

- (void)keyboardWillHide:(NSNotification*)notification
{
    if (self.theme.movesAboveKeyboard) {
        CGRect frame = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
        frame = [self.view convertRect:frame fromView:nil];
        NSTimeInterval duration = [[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        UIViewAnimationCurve curve = [[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
        
        [self keyboardWithStartFrame:frame willHideAfterDuration:duration withOptions:UIViewAnimationCurveToAnimationOptions(curve)];
    }
}

- (void)keyboardWithStartFrame:(CGRect)keyboardFrame willHideAfterDuration:(NSTimeInterval)duration withOptions:(UIViewAnimationOptions)options
{
    [UIView animateWithDuration:duration delay:0.0f options:options animations:^{
        self.view.center = self.maskView.center;
    } completion:nil];
}

#pragma mark - Presentation

- (void)presentPopupControllerAnimated:(BOOL)flag {
    
    if ([self.delegate respondsToSelector:@selector(popupControllerWillPresent:)]) {
        [self.delegate popupControllerWillPresent:self];
    }
    
    // Keep a record of if the popup was presented with animation
    self.dismissAnimated = flag;
    
    [self applyTheme];
    [((CNPPopupView *)self.view) calculateContentSizeThatFits:CGSizeMake([self popupWidth], self.maskView.bounds.size.height) andUpdateLayout:YES];
    self.view.center = [self originPoint];
    [self.applicationWindow addSubview:self.maskView];
    self.maskView.alpha = 0;
    [UIView animateWithDuration:flag?0.3:0.0 animations:^{
        self.maskView.alpha = 1.0;
        self.view.center = [self endingPoint];;
    } completion:^(BOOL finished) {
        self.view.userInteractionEnabled = YES;
        if ([self.delegate respondsToSelector:@selector(popupControllerDidPresent:)]) {
            [self.delegate popupControllerDidPresent:self];
        }
    }];
}

- (void)dismissPopupControllerAnimated:(BOOL)flag {
    if ([self.delegate respondsToSelector:@selector(popupControllerWillDismiss:)]) {
        [self.delegate popupControllerWillDismiss:self];
    }
    [UIView animateWithDuration:flag?0.3:0.0 animations:^{
        self.maskView.alpha = 0.0;
        self.view.center = [self dismissedPoint];;
    } completion:^(BOOL finished) {
        [self.maskView removeFromSuperview];
        if ([self.delegate respondsToSelector:@selector(popupControllerDidDismiss:)]) {
            [self.delegate popupControllerDidDismiss:self];
        }
    }];
}

- (CGPoint)originPoint {
    CGPoint origin;
    switch (self.theme.presentationStyle) {
        case CNPPopupPresentationStyleFadeIn:
            origin = self.maskView.center;
            break;
        case CNPPopupPresentationStyleSlideInFromBottom:
            origin = CGPointMake(self.maskView.center.x, self.maskView.bounds.size.height + self.view.bounds.size.height);
            break;
        case CNPPopupPresentationStyleSlideInFromLeft:
            origin = CGPointMake(-self.view.bounds.size.width, self.maskView.center.y);
            break;
        case CNPPopupPresentationStyleSlideInFromRight:
            origin = CGPointMake(self.maskView.bounds.size.width+self.view.bounds.size.width, self.maskView.center.y);
            break;
        case CNPPopupPresentationStyleSlideInFromTop:
            origin = CGPointMake(self.maskView.center.x, -self.view.bounds.size.height);
            break;
        default:
            origin = self.maskView.center;
            break;
    }
    return origin;
}

- (CGPoint)endingPoint {
    CGPoint center;
    if (self.theme.popupStyle == CNPPopupStyleActionSheet) {
        center = CGPointMake(self.maskView.center.x, self.maskView.bounds.size.height-(self.view.bounds.size.height * 0.5));
    }
    else {
        center = self.maskView.center;
    }
    return center;
}

- (void)viewDidLayoutSubviews {
    [UIView animateWithDuration:0.3 animations:^{
        self.view.center = [self endingPoint];;
    } completion:^(BOOL finished) {}];
}

- (CGPoint)dismissedPoint {
    CGPoint dismissed;
    switch (self.theme.presentationStyle) {
        case CNPPopupPresentationStyleFadeIn:
            dismissed = self.maskView.center;
            break;
        case CNPPopupPresentationStyleSlideInFromBottom:
            dismissed = self.theme.dismissesOppositeDirection?CGPointMake(self.maskView.center.x, -self.view.bounds.size.height):CGPointMake(self.maskView.center.x, self.maskView.bounds.size.height + self.view.bounds.size.height);
            if (self.theme.popupStyle == CNPPopupStyleActionSheet) {
                dismissed = CGPointMake(self.maskView.center.x, self.maskView.bounds.size.height + self.view.bounds.size.height);
            }
            break;
        case CNPPopupPresentationStyleSlideInFromLeft:
            dismissed = self.theme.dismissesOppositeDirection?CGPointMake(self.maskView.bounds.size.width+self.view.bounds.size.width, self.maskView.center.y):CGPointMake(-self.view.bounds.size.width, self.maskView.center.y);
            break;
        case CNPPopupPresentationStyleSlideInFromRight:
            dismissed = self.theme.dismissesOppositeDirection?CGPointMake(-self.view.bounds.size.width, self.maskView.center.y):CGPointMake(self.maskView.bounds.size.width+self.view.bounds.size.width, self.maskView.center.y);
            break;
        case CNPPopupPresentationStyleSlideInFromTop:
            dismissed = self.theme.dismissesOppositeDirection?CGPointMake(self.maskView.center.x, self.maskView.bounds.size.height + self.view.bounds.size.height):CGPointMake(self.maskView.center.x, -self.view.bounds.size.height);
            break;
        default:
            dismissed = self.maskView.center;
            break;
    }
    return dismissed;
}

- (CGFloat)popupWidth {
    CGFloat width = self.theme.maxPopupWidth;
    if ((self.theme.popupStyle == CNPPopupStyleActionSheet && !CNP_IS_IPAD ) || self.theme.popupStyle == CNPPopupStyleFullscreen) {
        width = self.maskView.bounds.size.width;
    }
    return width;
}

#pragma mark - UIGestureRecognizerDelegate 

- (void)handleBackgroundTapGesture:(id)sender {
    if (self.theme.shouldDismissOnBackgroundTouch) {
        [self.view endEditing:YES];
        [self dismissPopupControllerAnimated:self.dismissAnimated];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([touch.view isDescendantOfView:self.view])
        return NO;
    return YES;
}

- (UIWindow *)applicationWindow {
    return [[UIApplication sharedApplication] keyWindow];
}

@end

#pragma mark - CNPPopupButton Methods

@implementation CNPPopupButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addTarget:self action:@selector(buttonTouched) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)buttonTouched {
    if (self.selectionHandler) {
        self.selectionHandler(self);
    }
}

@end

#pragma mark - CNPPopupTheme Methods

@implementation CNPPopupTheme

+ (CNPPopupTheme *)defaultTheme {
    CNPPopupTheme *defaultTheme = [[CNPPopupTheme alloc] init];
    defaultTheme.backgroundColor = [UIColor whiteColor];
    defaultTheme.cornerRadius = 4.0f;
    defaultTheme.popupContentInsets = UIEdgeInsetsMake(16.0f, 16.0f, 16.0f, 16.0f);
    defaultTheme.popupStyle = CNPPopupStyleCentered;
    defaultTheme.presentationStyle = CNPPopupPresentationStyleSlideInFromBottom;
    defaultTheme.dismissesOppositeDirection = NO;
    defaultTheme.maskType = CNPPopupMaskTypeDimmed;
    defaultTheme.shouldDismissOnBackgroundTouch = YES;
    defaultTheme.movesAboveKeyboard = YES;
    defaultTheme.contentVerticalPadding = 16.0f;
    defaultTheme.maxPopupWidth = 300.0f;
    return defaultTheme;
}

@end