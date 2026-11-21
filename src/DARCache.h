#import <Foundation/Foundation.h>

@interface DARCache : NSObject
+ (instancetype)shared;
- (instancetype)initWithURL:(NSURL *)url;
- (NSDictionary *)contentForKey:(NSString *)key;
- (void)storeContent:(NSDictionary *)content forKey:(NSString *)key;
- (void)flush;
@end
