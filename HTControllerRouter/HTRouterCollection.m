//
//  HTRouterCollection.m
//  HTUIDemo
//
//  Created by zp on 15/8/28.
//  Copyright (c) 2015年 HT. All rights reserved.
//

#import "HTRouterCollection.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import <mach-o/dyld.h>
#import <mach-o/getsect.h>

NSString *extractClassName(NSString *methodName)
{
    // Parse class and method
    NSArray *parts = [[methodName substringWithRange:NSMakeRange(2, methodName.length - 3)] componentsSeparatedByString:@" "];
    if (parts.count > 0)
        return parts[0];
    
    return nil;
}

NSArray *HTExportedMethodsByModuleID(void)
{
    static NSMutableArray *classes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!classes){
            classes = [NSMutableArray new];
        }
        
#ifdef __LP64__
        typedef uint64_t HTExportValue;
        typedef struct section_64 HTExportSection;
#define HTGetSectByNameFromHeader getsectbynamefromheader_64
#else
        typedef uint32_t HTExportValue;
        typedef struct section HTExportSection;
#define HTGetSectByNameFromHeader getsectbynamefromheader
#endif
        HTExportValue executable_base = NULL;
        NSString *appName =  [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString *)kCFBundleExecutableKey];
        uint32_t c = _dyld_image_count();
        for (uint32_t i = 0; i < c; i++) {
            const struct mach_header *cur_header = _dyld_get_image_header(i);
            intptr_t cur_slide = _dyld_get_image_vmaddr_slide(i);
            
            Dl_info info;
            if (dladdr(cur_header, &info) == 0) {
                continue;
            }
            if (strcmp(basename(info.dli_fname), [appName UTF8String]) == 0) {
                executable_base = (HTExportValue)info.dli_fbase;;
                break;
            }
        }
        if (executable_base == NULL) {
            return;
        }
        
        const HTExportSection *section = HTGetSectByNameFromHeader((void *)executable_base, "__DATA", "HTExport");
        
        if (section == NULL) {
            return;
        }
        
        int addrOffset = sizeof(const char **);
        /**
         *  防止address sanitizer报global-buffer-overflow错误
         *  https://github.com/google/sanitizers/issues/355
         *  因为address sanitizer填充了符号地址，使用正确的地址偏移
         */
#if defined(__has_feature)
#  if __has_feature(address_sanitizer)
        addrOffset = 64;
#  endif
#endif
        
        for (HTExportValue addr = section->offset;
             addr < section->offset + section->size;
             addr += addrOffset) {
            
            // Get data entry
            const char **entries = (const char **)(mach_header + addr);
            
            char * str = *entries;
            if (str == NULL) {
                continue;
            }
            NSString *className = extractClassName(@(str));
            Class class = className ? NSClassFromString(className) : nil;
            if (class){
                [classes addObject:class];
            }
        }
    });
    
    return classes;
}
