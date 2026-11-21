#import "DARPhotoDate.h"
#import <ImageIO/ImageIO.h>
static NSDictionary *DARPhotoExif(NSData *data) {
    if(!data.length)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    if(!source)return nil;
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    CFRelease(source);
    id exif=properties[(__bridge NSString *)kCGImagePropertyExifDictionary];
    return [exif isKindOfClass:NSDictionary.class]?exif:nil;
}
static BOOL DARDateMatches(NSString *value,NSString *pattern) {
    if(![value isKindOfClass:NSString.class])return NO;
    NSRange match=[value rangeOfString:pattern options:NSRegularExpressionSearch];
    return match.location==0 && match.length==value.length;
}
static NSDate *DARDateFromExif(NSDictionary *exif) {
    NSString *original=exif[(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal];
    if(!DARDateMatches(original,@"^[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$") || [original hasPrefix:@"0000"])return nil;
    // EXIF without an offset records local wall-clock time. Do not guess a
    // location or substitute publication, edit or download timestamps.
    NSTimeZone *zone=NSTimeZone.localTimeZone;
    NSString *offset=exif[(__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal];
    if(offset) {
        if(!DARDateMatches(offset,@"^[+-][0-9]{2}:[0-9]{2}$"))return nil;
        NSInteger hours=[[offset substringWithRange:NSMakeRange(1,2)] integerValue];
        NSInteger minutes=[[offset substringFromIndex:4] integerValue];
        if(hours>14 || minutes>59 || (hours==14 && minutes))return nil;
        NSInteger seconds=(hours*60+minutes)*60*([offset hasPrefix:@"-"]?-1:1);
        zone=[NSTimeZone timeZoneForSecondsFromGMT:seconds];
    }
    NSDateFormatter *formatter=[NSDateFormatter new];
    formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.timeZone=zone;formatter.dateFormat=@"yyyy:MM:dd HH:mm:ss";formatter.lenient=NO;
    NSDate *date=[formatter dateFromString:original];
    if(!date || ![[formatter stringFromDate:date] isEqual:original])return nil;
    NSString *subsecond=exif[(__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal];
    if(DARDateMatches(subsecond,@"^[0-9]{1,9}$"))date=[date dateByAddingTimeInterval:[[@"0." stringByAppendingString:subsecond] doubleValue]];
    return date;
}
static NSDictionary *DARExifFromISODate(NSString *value) {
    if(![value isKindOfClass:NSString.class])return nil;
    if(DARDateMatches(value,@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))value=[value stringByAppendingString:@"T00:00:00"];
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.]([0-9]{1,9}))?(Z|[+-][0-9]{2}:?[0-9]{2})?$" options:0 error:NULL];
    NSTextCheckingResult *match=[regex firstMatchInString:value options:0 range:NSMakeRange(0,value.length)];
    if(!match || match.range.length!=value.length)return nil;
    NSMutableArray *parts=[NSMutableArray new];for(NSUInteger i=1;i<=6;i++)[parts addObject:[value substringWithRange:[match rangeAtIndex:i]]];
    NSMutableDictionary *fields=[NSMutableDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@:%@:%@ %@:%@:%@",parts[0],parts[1],parts[2],parts[3],parts[4],parts[5]] forKey:(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal];
    NSRange sub=[match rangeAtIndex:7];if(sub.location!=NSNotFound)fields[(__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal]=[value substringWithRange:sub];
    NSRange zone=[match rangeAtIndex:8];
    if(zone.location!=NSNotFound) {
        NSString *offset=[value substringWithRange:zone];
        if([offset isEqual:@"Z"])offset=@"+00:00";
        else if(offset.length==5)offset=[NSString stringWithFormat:@"%@:%@",[offset substringToIndex:3],[offset substringFromIndex:3]];
        fields[(__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal]=offset;
    }
    return DARDateFromExif(fields)?fields:nil;
}
NSDictionary *DARPhotoCaptureFields(NSData *data) {
    NSDictionary *exif=DARPhotoExif(data);
    NSString *dateKey=(__bridge NSString *)kCGImagePropertyExifDateTimeOriginal;
    NSString *zoneKey=(__bridge NSString *)kCGImagePropertyExifOffsetTimeOriginal;
    BOOL hasExifDate=DARDateFromExif(exif)!=nil;
    // Image I/O can synthesize XMP from EXIF. Do not let that derivative
    // silently normalize an explicitly invalid original date or timezone.
    if(exif[dateKey] && !hasExifDate)return nil;
    if(hasExifDate && exif[zoneKey])return exif;
    if(!data.length)return nil;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);if(!source)return nil;
    CGImageMetadataRef metadata=CGImageSourceCopyMetadataAtIndex(source,0,NULL);
    NSDictionary *fields;
    if(metadata) {
        for(NSString *path in @[@"exif:DateTimeOriginal",@"photoshop:DateCreated"]) {
            NSString *value=CFBridgingRelease(CGImageMetadataCopyStringValueWithPath(metadata,NULL,(__bridge CFStringRef)path));
            fields=DARExifFromISODate(value);if(fields)break;
        }
        CFRelease(metadata);
    }
    if(hasExifDate) {
        if([fields[dateKey] isEqual:exif[dateKey]]) {
            NSMutableDictionary *enriched=[exif mutableCopy];
            for(NSString *key in @[zoneKey,(__bridge NSString *)kCGImagePropertyExifSubsecTimeOriginal])
                if(!enriched[key] && fields[key])enriched[key]=fields[key];
            fields=enriched;
        } else fields=exif;
    }
    if(!fields) {
        NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
        id iptc=properties[(__bridge NSString *)kCGImagePropertyIPTCDictionary];
        if([iptc isKindOfClass:NSDictionary.class]) {
            id day=iptc[(__bridge NSString *)kCGImagePropertyIPTCDateCreated];
            id time=iptc[(__bridge NSString *)kCGImagePropertyIPTCTimeCreated];
            if([day isKindOfClass:NSString.class]) {
                day=[[day stringByReplacingOccurrencesOfString:@"-" withString:@""] stringByReplacingOccurrencesOfString:@":" withString:@""];
                NSString *clock=!time?@"000000":([time isKindOfClass:NSString.class]?[time stringByReplacingOccurrencesOfString:@":" withString:@""]:nil);
                if(DARDateMatches(day,@"^[0-9]{8}$") && DARDateMatches(clock,@"^[0-9]{6}([+-][0-9]{4})?$")) {
                    NSString *iso=[NSString stringWithFormat:@"%@-%@-%@T%@:%@:%@%@",[day substringToIndex:4],[day substringWithRange:NSMakeRange(4,2)],[day substringFromIndex:6],[clock substringToIndex:2],[clock substringWithRange:NSMakeRange(2,2)],[clock substringWithRange:NSMakeRange(4,2)],[clock substringFromIndex:6]];
                    fields=DARExifFromISODate(iso);
                }
            }
        }
    }
    CFRelease(source);return fields;
}
NSDate *DARPhotoCaptureDate(NSData *data) { return DARDateFromExif(DARPhotoCaptureFields(data)); }
