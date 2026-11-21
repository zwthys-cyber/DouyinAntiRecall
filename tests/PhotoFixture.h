#import <Foundation/Foundation.h>
// Embed a standard JPEG APP1 XMP packet directly. Image I/O's metadata writer
// may omit mapped XMP tags, so tests must verify bytes that actually carry XMP.
static NSData *DARTestXMPJPEG(NSData *jpeg,NSString *path,NSString *value) {
    if(jpeg.length<2)return nil;
    NSArray *parts=[path componentsSeparatedByString:@":"];if(parts.count!=2)return nil;
    NSString *prefix=parts[0],*name=parts[1];
    NSString *space=@{@"exif":@"http://ns.adobe.com/exif/1.0/",@"photoshop":@"http://ns.adobe.com/photoshop/1.0/",@"xmp":@"http://ns.adobe.com/xap/1.0/"}[prefix];
    if(!space)return nil;
    NSString *xml=[NSString stringWithFormat:@"<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:%@=\"%@\" %@:%@=\"%@\"/></rdf:RDF></x:xmpmeta>",prefix,space,prefix,name,value];
    const char identifier[]="http://ns.adobe.com/xap/1.0/";
    NSMutableData *packet=[NSMutableData dataWithBytes:identifier length:sizeof(identifier)];
    [packet appendData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    NSUInteger length=packet.length+2;if(length>65535)return nil;
    unsigned char marker[4]={0xff,0xe1,(unsigned char)(length>>8),(unsigned char)(length&0xff)};
    NSMutableData *result=[NSMutableData dataWithData:[jpeg subdataWithRange:NSMakeRange(0,2)]];
    [result appendBytes:marker length:4];[result appendData:packet];
    [result appendData:[jpeg subdataWithRange:NSMakeRange(2,jpeg.length-2)]];return result;
}
