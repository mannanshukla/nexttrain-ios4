#import "ORJSON.h"

@interface ORJSONParser : NSObject {
    NSString *src; NSUInteger pos; NSUInteger len; BOOL failed;
}
- (id)initWithString:(NSString *)s;
- (id)parseValue;
@end

@implementation ORJSONParser
- (id)initWithString:(NSString *)s { if ((self = [super init])) { src = [s retain]; len = [s length]; pos = 0; } return self; }
- (void)dealloc { [src release]; [super dealloc]; }
- (unichar)peek { return pos < len ? [src characterAtIndex:pos] : 0; }
- (void)skipWS { while (pos < len) { unichar c = [src characterAtIndex:pos]; if (c==' '||c=='\n'||c=='\r'||c=='\t') pos++; else break; } }
- (BOOL)consume:(NSString *)lit {
    if (pos + [lit length] <= len && [[src substringWithRange:NSMakeRange(pos, [lit length])] isEqualToString:lit]) { pos += [lit length]; return YES; }
    return NO;
}
- (NSString *)parseString {
    if ([self peek] != '"') { failed = YES; return nil; }
    pos++;
    NSMutableString *out = [NSMutableString string];
    while (pos < len) {
        unichar c = [src characterAtIndex:pos++];
        if (c == '"') return out;
        if (c == '\\') {
            if (pos >= len) break;
            unichar e = [src characterAtIndex:pos++];
            switch (e) {
                case '"': [out appendString:@"\""]; break;
                case '\\': [out appendString:@"\\"]; break;
                case '/': [out appendString:@"/"]; break;
                case 'b': [out appendString:@"\b"]; break;
                case 'f': [out appendString:@"\f"]; break;
                case 'n': [out appendString:@"\n"]; break;
                case 'r': [out appendString:@"\r"]; break;
                case 't': [out appendString:@"\t"]; break;
                case 'u': {
                    if (pos + 4 > len) { failed = YES; return nil; }
                    unsigned v = 0; [[NSScanner scannerWithString:[src substringWithRange:NSMakeRange(pos,4)]] scanHexInt:&v]; pos += 4;
                    unichar u = (unichar)v;
                    // surrogate pair
                    if (u >= 0xD800 && u <= 0xDBFF && pos + 6 <= len && [src characterAtIndex:pos]=='\\' && [src characterAtIndex:pos+1]=='u') {
                        unsigned lo = 0; [[NSScanner scannerWithString:[src substringWithRange:NSMakeRange(pos+2,4)]] scanHexInt:&lo]; pos += 6;
                        unichar pair[2] = { u, (unichar)lo }; [out appendString:[NSString stringWithCharacters:pair length:2]];
                    } else { [out appendString:[NSString stringWithCharacters:&u length:1]]; }
                    break;
                }
                default: failed = YES; return nil;
            }
        } else {
            [out appendString:[NSString stringWithCharacters:&c length:1]];
        }
    }
    failed = YES; return nil;
}
- (id)parseNumber {
    NSUInteger start = pos;
    while (pos < len) { unichar c = [src characterAtIndex:pos]; if ((c>='0'&&c<='9')||c=='-'||c=='+'||c=='.'||c=='e'||c=='E') pos++; else break; }
    NSString *s = [src substringWithRange:NSMakeRange(start, pos-start)];
    if ([s rangeOfString:@"."].location != NSNotFound || [s rangeOfString:@"e"].location != NSNotFound || [s rangeOfString:@"E"].location != NSNotFound)
        return [NSNumber numberWithDouble:[s doubleValue]];
    return [NSNumber numberWithLongLong:[s longLongValue]];
}
- (id)parseValue {
    [self skipWS];
    if (failed || pos >= len) { failed = YES; return nil; }
    unichar c = [self peek];
    if (c == '{') {
        pos++; NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [self skipWS]; if ([self peek] == '}') { pos++; return d; }
        while (!failed) {
            [self skipWS]; NSString *k = [self parseString]; if (failed) return nil;
            [self skipWS]; if (![self consume:@":"]) { failed = YES; return nil; }
            id v = [self parseValue]; if (failed) return nil;
            [d setObject:v forKey:k];
            [self skipWS];
            if ([self consume:@","]) continue;
            if ([self consume:@"}"]) return d;
            failed = YES; return nil;
        }
        return nil;
    }
    if (c == '[') {
        pos++; NSMutableArray *a = [NSMutableArray array];
        [self skipWS]; if ([self peek] == ']') { pos++; return a; }
        while (!failed) {
            id v = [self parseValue]; if (failed) return nil;
            [a addObject:v];
            [self skipWS];
            if ([self consume:@","]) continue;
            if ([self consume:@"]"]) return a;
            failed = YES; return nil;
        }
        return nil;
    }
    if (c == '"') return [self parseString];
    if ([self consume:@"true"]) return [NSNumber numberWithBool:YES];
    if ([self consume:@"false"]) return [NSNumber numberWithBool:NO];
    if ([self consume:@"null"]) return [NSNull null];
    if (c == '-' || (c >= '0' && c <= '9')) return [self parseNumber];
    failed = YES; return nil;
}
- (BOOL)failed { return failed; }
@end

@implementation ORJSON
+ (id)parse:(NSString *)text {
    if (!text) return nil;
    ORJSONParser *p = [[ORJSONParser alloc] initWithString:text];
    id v = [p parseValue];
    BOOL bad = [p failed];
    [p release];
    return bad ? nil : v;
}
+ (NSString *)escape:(NSString *)s {
    NSMutableString *o = [NSMutableString stringWithCapacity:[s length]+8];
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '"': [o appendString:@"\\\""]; break;
            case '\\': [o appendString:@"\\\\"]; break;
            case '\n': [o appendString:@"\\n"]; break;
            case '\r': [o appendString:@"\\r"]; break;
            case '\t': [o appendString:@"\\t"]; break;
            default:
                if (c < 0x20) [o appendFormat:@"\\u%04x", c];
                else [o appendString:[NSString stringWithCharacters:&c length:1]];
        }
    }
    return o;
}
+ (NSString *)stringify:(id)obj {
    if ([obj isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", [self escape:obj]];
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (strcmp([obj objCType], @encode(BOOL)) == 0 || strcmp([obj objCType], @encode(char)) == 0) return [obj boolValue] ? @"true" : @"false";
        return [obj stringValue];
    }
    if (obj == nil || [obj isKindOfClass:[NSNull class]]) return @"null";
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id v in obj) [parts addObject:[self stringify:v]];
        return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *k in obj) [parts addObject:[NSString stringWithFormat:@"\"%@\":%@", [self escape:k], [self stringify:[obj objectForKey:k]]]];
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@","]];
    }
    return [NSString stringWithFormat:@"\"%@\"", [self escape:[obj description]]];
}
@end
