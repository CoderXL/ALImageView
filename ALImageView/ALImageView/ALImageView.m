//
//  ALImageView.m
//  ALImageView
//
//  Created by SpringOx on 12-8-2.
//  Copyright (c) 2012年 SpringOx. All rights reserved.
//

#import "ALImageView.h"

const NSString * LOCAL_CAHCE_DIRECTORY_DEFAULT = @"com.springox.ALImageView";

@implementation ALImageCache

+ (ALImageCache *)sharedInstance
{
    static ALImageCache *_imageCache = nil;
    static dispatch_once_t _oncePredicate;
    dispatch_once(&_oncePredicate, ^{
        @autoreleasepool {
            _imageCache = [[ALImageCache alloc] init];
            _imageCache.memoryCache = [[[NSCache alloc] init] autorelease];
            
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *cachesPath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
            if (0 < [cachesPath length]) {
                _imageCache.localCacheDirectory = [cachesPath stringByAppendingPathComponent:(NSString *)LOCAL_CAHCE_DIRECTORY_DEFAULT];
            }
        }
    });
    return _imageCache;
}

- (void)dealloc
{
    self.memoryCache = nil;
    self.localCacheDirectory = nil;
    [super dealloc];
}

#pragma mark ALImageCache (public)

- (void)setLocalCacheDirectory:(NSString *)localCacheDirectory
{
    if (_localCacheDirectory != localCacheDirectory) {
        if (nil != _localCacheDirectory) {
            [_localCacheDirectory release];
            _localCacheDirectory = nil;
        }
        
        if (nil != localCacheDirectory) {
            _localCacheDirectory = [localCacheDirectory retain];
        }
    }
    
    if (0 < [_localCacheDirectory length]) {
        BOOL isDirectory = YES;
        if (![[NSFileManager defaultManager] fileExistsAtPath:_localCacheDirectory isDirectory:&isDirectory] && !isDirectory) {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:_localCacheDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        }
    }
}

- (UIImage *)cachedImageForImageURL:(NSString *)url fromLocal:(BOOL)localEnabled
{
    UIImage *img = [self cachedImageForKey:url];
    if (nil == img && localEnabled) {
        NSString *localCachePath = [self.localCacheDirectory stringByAppendingPathComponent:[url lastPathComponent]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:localCachePath]) {
            img = [UIImage imageWithContentsOfFile:localCachePath];
            [self cacheImage:img forKey:url];
            NSLog(@"cached image localCachePath:%@", localCachePath);
        }
    }
	return img;
}

- (UIImage *)cacheImageWithData:(NSData *)data forImageURL:(NSString *)url toLocal:(BOOL)localEnabled
{
    UIImage *img = [UIImage imageWithData:data];
    [self cacheImage:img forKey:url];
    if (localEnabled) {
        NSString *localCachePath = [self.localCacheDirectory stringByAppendingPathComponent:[url lastPathComponent]];
        NSError *error = nil;
        [data writeToFile:localCachePath options:NSDataWritingFileProtectionComplete error:&error];
        NSLog(@"cache image localCachePath:%@ error:%@", localCachePath, error);
    }
    return img;
}

- (BOOL)clearCache
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    NSArray *contents = [fm contentsOfDirectoryAtPath:_localCacheDirectory error:&error];
    for(NSString *itemName in contents){
        NSString *fullPathName = [_localCacheDirectory stringByAppendingPathComponent:itemName];
        error = nil;
        [fm removeItemAtPath:fullPathName error:&error];
    }
    if (nil == error) {
        [self.memoryCache removeAllObjects];
        return YES;
    } else {
        return NO;
    }
}

#pragma mark ALImageCache (private)

- (UIImage *)cachedImageForKey:(NSString *)key
{
	return [self.memoryCache objectForKey:key];
}

- (void)cacheImage:(UIImage *)image forKey:(NSString *)key
{
    if (image && key) {
        [self.memoryCache setObject:image forKey:key];
    }
}


@end

#pragma mark -

const NSTimeInterval REQUEST_TIME_OUT_INTERVAL = 30.f;

const int REQUEST_RETRY_COUNT = 2;

@interface ALImageView ()
{
    UIImage *_placeholderImage;
    UIActivityIndicatorView *_activityView;
    id _target;
    SEL _action;
    NSInteger _taskCount;      // Add the count to reload a picture when the object is complex,
                               // the old block, in effect, equivalent cancel
}

@end

@implementation ALImageView

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        
        [self commonInit];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    self.backgroundColor = [UIColor whiteColor];
    
    _contentEdgeInsets = UIEdgeInsetsZero;
    _index = -UINT_MAX;
    _queuePriority = ALImageQueuePriorityNormal;
    _localCacheEnabled = YES;
    _indicatorEnabled = YES;
}

- (void)dealloc
{
    self.imageURL = nil;
    if (nil != _activityView) {
        [_activityView stopAnimating];
        [_activityView release];
        _activityView = nil;
    }
    [super dealloc];
}

#pragma mark ALImageView (public)

/*
 // Only override drawRect: if you perform custom drawing.
 // An empty implementation adversely affects performance during animation.
 - (void)drawRect:(CGRect)rect
 {
 // Drawing code
 }
 */

- (void)setPlaceholderImage:(UIImage *)placeholderImage
{
    if (_placeholderImage != placeholderImage) {
        if (nil != _placeholderImage) {
            [_placeholderImage release];
            _placeholderImage = nil;
        }
        
        if (nil != placeholderImage) {
            _placeholderImage = [placeholderImage retain];
        }
    }
    
    self.image = _placeholderImage;
}

- (void)setImageURL:(NSString *)imageURL
{
    if (_imageURL != imageURL) {
        if (nil != _imageURL) {
            if (nil != _placeholderImage) {
                self.image = _placeholderImage;
            } else {
                self.image = nil;
            }
            [_imageURL release];
            _imageURL = nil;
        }
        
        if (nil != imageURL) {
            _imageURL = [imageURL retain];
        }
    }
    
    if (0 < [_imageURL length]) {
        UIImage *img = [[ALImageCache sharedInstance] cachedImageForImageURL:_imageURL fromLocal:_localCacheEnabled];
        if (nil != img) {
            [self setImageWithPlaceholder:img];
            return;
        }
        [self asyncLoadImageWithURL:[NSURL URLWithString:[_imageURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
        NSLog(@"load image from remote server!");
    }
}

- (void)setIndicatorEnabled:(BOOL)indicatorEnabled
{
    _indicatorEnabled = indicatorEnabled;
    if (!_indicatorEnabled) {
        if (nil != _activityView) {
            [_activityView stopAnimating];
            [_activityView release];
            _activityView = nil;
        }
    }
}

- (void)setIsCorner:(BOOL)isCorner
{
    _isCorner = isCorner;
    if (_isCorner) {
        self.layer.cornerRadius = 10.0f;
        self.clipsToBounds = YES;
    } else {
        self.layer.cornerRadius = 0.0f;
        self.clipsToBounds = NO;
    }
}

- (void)loadImage:(NSString *)imageURL placeholderImage:(UIImage *)placeholderImage
{
    self.placeholderImage = placeholderImage;
    self.imageURL = imageURL;
}

- (void)addTarget:(id)target action:(SEL)action
{
    _target = target;
    _action = action;
    self.userInteractionEnabled = YES;
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapGestureRecognizer:)];
    [self addGestureRecognizer:gestureRecognizer];
    [gestureRecognizer release];
}

#pragma mark ALImageView (private)

- (UIImage *)insertBgImage:(UIImage *)bgImage toImage:(UIImage *)image
{
    if (_contentEdgeInsets.top || _contentEdgeInsets.left || _contentEdgeInsets.bottom || _contentEdgeInsets.right) {
        CGFloat s = [UIScreen mainScreen].scale;
        CGSize size = CGSizeMake(s*self.bounds.size.width, s*self.bounds.size.height);
        UIGraphicsBeginImageContext(size);
        [bgImage drawInRect:CGRectMake(0.f, 0.f, s*self.bounds.size.width, s*self.bounds.size.height)];
        [image drawInRect:CGRectMake(s*_contentEdgeInsets.left, s*_contentEdgeInsets.top, s*(self.bounds.size.width-_contentEdgeInsets.left-_contentEdgeInsets.right), s*(self.bounds.size.height-_contentEdgeInsets.top-_contentEdgeInsets.bottom))];
        UIImage *resultingImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return resultingImage;
    } else {
        return image;
    }
}

- (void)setImageWithPlaceholder:(UIImage *)img
{
    if (nil == img) {
        return;
    }
    
    if (nil != _placeholderImage) {
        self.image = [self insertBgImage:_placeholderImage toImage:img];
    } else {
        self.image = img;
    }
}

- (void)setImageWithAnimation:(UIImage *)img
{
    [self setImageWithPlaceholder:img];
    
    self.alpha = 0.3f;
    [UIView animateWithDuration:0.32f
                          delay:0.16f
                        options:UIViewAnimationOptionCurveLinear
                     animations:^{
                         self.alpha = 1.f;
                     }
                     completion:nil];
}

- (void)asyncLoadImageWithURL:(NSURL *)url
{
    if (_indicatorEnabled && nil == _activityView) {
        if (nil == _placeholderImage) {
            _activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        } else {
            _activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        }
        _activityView.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
        [self addSubview:_activityView];
    }
    [_activityView startAnimating];
    
    _asyncLoadImageFinished = NO;
    _taskCount++;
    
    NSInteger countStamp = _taskCount;
    dispatch_block_t loadImageBlock = ^(void) {
        
        NSData *data = nil;
        UIImage *img = nil;
        
        NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:REQUEST_TIME_OUT_INTERVAL];
        int retryCount = -1;
        while (REQUEST_RETRY_COUNT > retryCount && countStamp == _taskCount) {
            NSLog(@"async load image start url:%@ countStamp:%d _taskCount:%d", [request.URL.absoluteString lastPathComponent], countStamp, _taskCount);
            if (0 <= retryCount) {
                NSLog(@"async load image usleep url:%@ countStamp:%d _taskCount:%d", [request.URL.absoluteString lastPathComponent], countStamp, _taskCount);
                usleep(500*(retryCount+1));
            }
            
            NSURLResponse *response = nil;
            NSError *error = nil;
            data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            retryCount++;
            NSLog(@"async load image retry count:%d expected length:%lld", retryCount, response.expectedContentLength);
            
            if (nil == error &&
                0 < response.expectedContentLength &&
                response.expectedContentLength == [data length]) {  // Tested may return the length of the data is empty or less
                img = [[ALImageCache sharedInstance] cacheImageWithData:data forImageURL:[url absoluteString] toLocal:_localCacheEnabled];
                break;
            } else {
                data = nil;
            }
            NSLog(@"async load image end url:%@ countStamp:%d _taskCount:%d dataLength:%d", [self.imageURL lastPathComponent], countStamp, _taskCount, [data length]);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (nil != img) {
                if (countStamp == _taskCount) {   // Add the count to reload a picture when the object is complex,the old block, in effect, equivalent cancel
                    [self setImageWithAnimation:img];
                    _asyncLoadImageFinished = YES;
                    [_activityView stopAnimating];
                    NSLog(@"async load image finish!");
                }
            } else {
                _asyncLoadImageFinished = NO;
                [_activityView stopAnimating];
                NSLog(@"async load image finish without set image!");
            }
        });
    };
    
    if (ALImageQueuePriorityHigh == _queuePriority) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), loadImageBlock);
    } else if (ALImageQueuePriorityNormal == _queuePriority) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), loadImageBlock);
    } else {
        static dispatch_queue_t imageQueue = NULL;
        
        if (NULL == imageQueue) {
            imageQueue = dispatch_queue_create("asynchronous_load_image", nil);
        }
        dispatch_async(imageQueue, loadImageBlock);
    }
}

- (void)didTapGestureRecognizer:(id)sender
{
    if (nil == self.image || _activityView.isAnimating) {
        return;
    }
    [_target performSelector:_action withObject:self];
}

@end
