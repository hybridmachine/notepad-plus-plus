// Settings Manager for Notepad++ macOS Port
// Persists user settings to ~/.npp-macos/settings.json using NSJSONSerialization.

#import <Foundation/Foundation.h>
#include "settings_manager.h"

SettingsManager& SettingsManager::instance()
{
	static SettingsManager mgr;
	return mgr;
}

std::string SettingsManager::settingsDir() const
{
	NSString* home = NSHomeDirectory();
	NSString* dir = [home stringByAppendingPathComponent:@".npp-macos"];
	const char* fs = [dir fileSystemRepresentation];
	if (!fs) return "";
	return std::string(fs);
}

std::string SettingsManager::settingsPath() const
{
	return settingsDir() + "/settings.json";
}

bool SettingsManager::load()
{
	NSString* path = [NSString stringWithUTF8String:settingsPath().c_str()];
	NSData* data = [NSData dataWithContentsOfFile:path];
	if (!data) return false;

	NSError* error = nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:data
	                                            options:0
	                                              error:&error];
	if (!parsed || error) return false;
	if (![parsed isKindOfClass:[NSDictionary class]]) return false;
	NSDictionary* json = parsed;

	// Window geometry
	if ([json[@"windowX"] isKindOfClass:[NSNumber class]])      settings.windowX = [json[@"windowX"] doubleValue];
	if ([json[@"windowY"] isKindOfClass:[NSNumber class]])      settings.windowY = [json[@"windowY"] doubleValue];
	if ([json[@"windowWidth"] isKindOfClass:[NSNumber class]])  settings.windowWidth = [json[@"windowWidth"] doubleValue];
	if ([json[@"windowHeight"] isKindOfClass:[NSNumber class]]) settings.windowHeight = [json[@"windowHeight"] doubleValue];

	// Editor preferences
	if ([json[@"fontName"] isKindOfClass:[NSString class]])  settings.fontName = [json[@"fontName"] UTF8String];
	if ([json[@"fontSize"] isKindOfClass:[NSNumber class]])  settings.fontSize = [json[@"fontSize"] intValue];
	if ([json[@"tabWidth"] isKindOfClass:[NSNumber class]])  settings.tabWidth = [json[@"tabWidth"] intValue];

	// View state
	if ([json[@"wordWrap"] isKindOfClass:[NSNumber class]])        settings.wordWrap = [json[@"wordWrap"] boolValue];
	if ([json[@"showLineNumbers"] isKindOfClass:[NSNumber class]]) settings.showLineNumbers = [json[@"showLineNumbers"] boolValue];

	// Recent files
	settings.recentFiles.clear();
	NSArray* recent = json[@"recentFiles"];
	if ([recent isKindOfClass:[NSArray class]])
	{
		for (NSString* f in recent)
		{
			if ([f isKindOfClass:[NSString class]])
				settings.recentFiles.push_back([f UTF8String]);
		}
	}

	return true;
}

bool SettingsManager::save()
{
	// Ensure directory exists
	NSString* dir = [NSString stringWithUTF8String:settingsDir().c_str()];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir
	                          withIntermediateDirectories:YES
	                                          attributes:nil
	                                               error:nil];

	// Build JSON dictionary
	NSMutableArray* recentArr = [NSMutableArray array];
	for (const auto& f : settings.recentFiles)
		[recentArr addObject:[NSString stringWithUTF8String:f.c_str()]];

	NSDictionary* json = @{
		@"windowX":      @(settings.windowX),
		@"windowY":      @(settings.windowY),
		@"windowWidth":  @(settings.windowWidth),
		@"windowHeight": @(settings.windowHeight),
		@"fontName":     [NSString stringWithUTF8String:settings.fontName.c_str()],
		@"fontSize":     @(settings.fontSize),
		@"tabWidth":     @(settings.tabWidth),
		@"wordWrap":     @(settings.wordWrap),
		@"showLineNumbers": @(settings.showLineNumbers),
		@"recentFiles":  recentArr,
	};

	NSError* error = nil;
	NSData* data = [NSJSONSerialization dataWithJSONObject:json
	                                              options:NSJSONWritingPrettyPrinted
	                                                error:&error];
	if (!data || error) return false;

	NSString* path = [NSString stringWithUTF8String:settingsPath().c_str()];
	return [data writeToFile:path atomically:YES];
}
