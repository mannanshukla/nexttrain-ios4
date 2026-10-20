#import "ORJSON.h"

// Works on a plain unichar copy of the text: one object per JSON value, never one per character.
@interface ORJSONParser : NSObject {
    unichar *buf; NSUInteger pos; NSUInteger len; BOOL failed;
}
- (id)initWithString:(NSString *)s;
- (id)parseValue;
@end

static unsigned hex4(const unichar *p) {   // like scanHexInt over four characters: stops at the first non-hex one
    unsigned v = 0;
    for (int i = 0; i < 4; i++) { unichar h = p[i]; int d = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10 : h >= 'A' && h <= 'F' ? h - 'A' + 10 : -1; if (d < 0) break; v = v * 16 + d; }
    return v;
}

@implementation ORJSONParser
- (id)initWithString:(NSString *)s { if ((self = [super init])) { len = [s length]; buf = malloc(MAX(len, 1) * sizeof(unichar)); [s getCharacters:buf range:NSMakeRange(0, len)]; pos = 0; } return self; }
- (void)dealloc { free(buf); [super dealloc]; }
- (unichar)peek { return pos < len ? buf[pos] : 0; }
- (void)skipWS { while (pos < len) { unichar c = buf[pos]; if (c==' '||c=='\n'||c=='\r'||c=='\t') pos++; else break; } }
- (BOOL)consume:(NSString *)lit {
    NSUInteger n = [lit length]; if (pos + n > len) return NO;
    for (NSUInteger i = 0; i < n; i++) if (buf[pos + i] != [lit characterAtIndex:i]) return NO;
    pos += n; return YES;
}
- (NSString *)parseString {
    if ([self peek] != '"') { failed = YES; return nil; }
    NSUInteger start = ++pos;
    while (pos < len && buf[pos] != '"' && buf[pos] != '\\') pos++;
    if (pos < len && buf[pos] == '"') { pos++; return [NSString stringWithCharacters:buf + start length:pos - 1 - start]; }   // no escapes: the common case
    NSMutableString *out = [NSMutableString stringWithCharacters:buf + start length:pos - start];
    while (pos < len) {
        unichar c = buf[pos++];
        if (c == '"') return out;
        if (c == '\\') {
            if (pos >= len) break;
            unichar e = buf[pos++];
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
                    unichar u = (unichar)hex4(buf + pos); pos += 4;
                    // surrogate pair
                    if (u >= 0xD800 && u <= 0xDBFF && pos + 6 <= len && buf[pos]=='\\' && buf[pos+1]=='u') {
                        unichar pair[2] = { u, (unichar)hex4(buf + pos + 2) }; pos += 6;
                        CFStringAppendCharacters((CFMutableStringRef)out, pair, 2);
                    } else { CFStringAppendCharacters((CFMutableStringRef)out, &u, 1); }
                    break;
                }
                default: failed = YES; return nil;
            }
        } else {
            NSUInteger run = pos - 1;   // copy everything up to the next quote or backslash in one go
            while (pos < len && buf[pos] != '"' && buf[pos] != '\\') pos++;
            CFStringAppendCharacters((CFMutableStringRef)out, buf + run, pos - run);
        }
    }
    failed = YES; return nil;
}
- (id)parseNumber {
    NSUInteger start = pos; BOOL real = NO;
    while (pos < len) { unichar c = buf[pos]; if ((c>='0'&&c<='9')||c=='-'||c=='+') pos++; else if (c=='.'||c=='e'||c=='E') { real = YES; pos++; } else break; }
    NSString *s = [NSString stringWithCharacters:buf + start length:pos - start];
    if (real) return [NSNumber numberWithDouble:[s doubleValue]];
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
    static NSCharacterSet *special = nil;
    if (!special) { NSMutableCharacterSet *m = [NSMutableCharacterSet characterSetWithRange:NSMakeRange(0, 0x20)]; [m addCharactersInString:@"\"\\"]; special = [m copy]; }
    if ([s rangeOfCharacterFromSet:special].location == NSNotFound) return s;   // nothing to escape: ids, names, most text
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
                else CFStringAppendCharacters((CFMutableStringRef)o, &c, 1);
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
