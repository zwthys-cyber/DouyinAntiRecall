#import <Foundation/Foundation.h>
typedef void (^DARPhotoFetch)(NSURL *url, void (^completion)(NSData *data, NSError *error));
typedef void (^DARPhotoWrite)(NSData *data, NSDate *date, void (^completion)(BOOL success, NSError *error));
FOUNDATION_EXPORT NSArray<NSURL *> *DAROriginalImageURLs(id model);
FOUNDATION_EXPORT NSData *DARReadPhotoDownload(NSURL *file, NSURLResponse *response, NSError *networkError, NSError **error);
// Nil fetch/writer use NSURLSession and Photos. Completion always runs on main.
FOUNDATION_EXPORT void DARSavePhotoCandidates(NSArray<NSArray<NSURL *> *> *candidates, DARPhotoFetch fetch, DARPhotoWrite writer,
    void (^completion)(NSUInteger saved, NSUInteger recognized, NSUInteger dated, NSError *error));
