#import "DARPhotoDate.h"
#import "PhotoFixture.h"
#include <stdio.h>
#include <stdlib.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
static NSData *Fixture(NSString *path,NSString *value) {
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,8,6,8,0,color,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);CGContextSetRGBFillColor(context,1,0,0,1);CGContextFillRect(context,CGRectMake(0,0,8,6));
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);
    NSMutableData *data=[NSMutableData new];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    CGImageDestinationAddImage(destination,image,NULL);
    BOOL saved=CGImageDestinationFinalize(destination);CFRelease(destination);CGImageRelease(image);
    if(!saved)exit(1);return DARTestXMPJPEG(data,path,value);
}
int main(void) {
    @autoreleasepool {
        for(NSString *path in @[@"exif:DateTimeOriginal",@"photoshop:DateCreated"]) {
            NSData *data=Fixture(path,@"2022-03-04T12:13:14.125+08:00");
            CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
            NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
            CGImageMetadataRef metadata=CGImageSourceCopyMetadataAtIndex(source,0,NULL);
            NSString *actualTag=metadata?CFBridgingRelease(CGImageMetadataCopyStringValueWithPath(metadata,NULL,(__bridge CFStringRef)path)):nil;
            if(metadata)CFRelease(metadata);CFRelease(source);
            NSDate *date=DARPhotoCaptureDate(data);
            NSLog(@"fixture %@ properties=%@ tag=%@ parsed=%@",path,properties,actualTag,date);
            NSISO8601DateFormatter *formatter=[NSISO8601DateFormatter new];formatter.formatOptions=NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds;
            NSDate *expected=[formatter dateFromString:@"2022-03-04T04:13:14.125Z"];
            if(!date || fabs([date timeIntervalSinceDate:expected])>0.001){NSLog(@"FAIL: XMP capture date %@",path);return 1;}
        }
        puts("PASS: Image IO capture date extraction");
    }
    return 0;
}
