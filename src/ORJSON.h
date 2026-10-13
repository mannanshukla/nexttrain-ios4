#import <Foundation/Foundation.h>
// Minimal JSON parser/serializer for iOS 4 (no NSJSONSerialization before iOS 5).
@interface ORJSON : NSObject
+ (id)parse:(NSString *)text;              // returns NSDictionary/NSArray/NSString/NSNumber/NSNull, or nil on error
+ (NSString *)stringify:(id)obj;           // NSDictionary/NSArray/NSString/NSNumber/NSNull
+ (NSString *)escape:(NSString *)s;
@end
