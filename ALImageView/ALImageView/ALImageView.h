//
//  ALImageView.h
//  ALImageView
//
//  Created by SpringOx on 12-8-2.
//  Copyright (c) 2012年 SpringOx. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#define ALImageViewQueuePriorityLow    1
#define ALImageViewQueuePriorityNormal  2
#define ALImageViewQueuePriorityHigh  3


@class ALImageView;
@protocol ALImageViewDelegate <NSObject>

@optional
- (void)imageView:(ALImageView *)imgView didAsynchronousLoadImage:(UIImage *)img;

@end

@interface ALImageView : UIImageView

@property (nonatomic, retain) UIImage *placeholderImage;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, retain) NSString *remotePath;
@property (nonatomic, assign) BOOL asyncLoadImageFinished;
@property (nonatomic, assign) NSInteger queuePriority;
@property (nonatomic, assign) BOOL isCorner;

@property (nonatomic, assign) id<NSObject, ALImageViewDelegate> delegate;

+ (NSString *)cacheDirectory;

- (void)asyncLoadImageWithURL:(NSURL *)url;

- (void)addTarget:(id)target action:(SEL)action;

@end
