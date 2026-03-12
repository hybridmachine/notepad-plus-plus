// File Monitor for macOS — FSEvents implementation
// Watches directories for file changes using Apple's FSEvents API.

#import <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>
#include "file_monitor_mac.h"

#include <mutex>
#include <queue>
#include <vector>
#include <string>

// Helper: wchar_t (UTF-32) → NSString → std::string (UTF-8)
static std::string WideToUTF8(const std::wstring& ws)
{
	if (ws.empty()) return "";
	NSString* ns = [[NSString alloc] initWithBytes:ws.data()
	                                        length:ws.size() * sizeof(wchar_t)
	                                      encoding:NSUTF32LittleEndianStringEncoding];
	return ns ? std::string([ns UTF8String]) : "";
}

// Helper: UTF-8 → wchar_t (UTF-32)
static std::wstring UTF8ToWide(const char* utf8)
{
	if (!utf8) return L"";
	NSString* ns = [NSString stringWithUTF8String:utf8];
	if (!ns) return L"";
	NSData* data = [ns dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
	if (!data) return L"";
	std::wstring result(reinterpret_cast<const wchar_t*>(data.bytes),
	                     data.length / sizeof(wchar_t));
	return result;
}

struct FileMonitorMac::Impl
{
	std::mutex mutex;
	std::queue<std::pair<FileMonitorAction, std::wstring>> eventQueue;
	FileMonitorCallback callback;
	std::vector<FSEventStreamRef> streams;
	std::vector<std::wstring> watchedPaths;
	bool terminated = false;
};

// FSEvents callback
// Note: kFSEventStreamCreateFlagUseCFTypes means eventPaths is a CFArrayRef of CFStringRef.
static void fseventsCallback(ConstFSEventStreamRef streamRef,
                              void* clientCallBackInfo,
                              size_t numEvents,
                              void* eventPaths,
                              const FSEventStreamEventFlags eventFlags[],
                              const FSEventStreamEventId eventIds[])
{
	auto* impl = static_cast<FileMonitorMac::Impl*>(clientCallBackInfo);
	CFArrayRef pathArray = static_cast<CFArrayRef>(eventPaths);

	for (size_t i = 0; i < numEvents; ++i)
	{
		FileMonitorAction action;
		FSEventStreamEventFlags flags = eventFlags[i];

		if (flags & kFSEventStreamEventFlagItemCreated)
			action = FileMonitorAction::Added;
		else if (flags & kFSEventStreamEventFlagItemRemoved)
			action = FileMonitorAction::Removed;
		else if (flags & kFSEventStreamEventFlagItemRenamed)
			action = FileMonitorAction::RenamedNew;
		else if (flags & kFSEventStreamEventFlagItemModified)
			action = FileMonitorAction::Modified;
		else
			action = FileMonitorAction::Modified; // default

		CFStringRef cfPath = static_cast<CFStringRef>(CFArrayGetValueAtIndex(pathArray, i));
		NSString* nsPath = (__bridge NSString*)cfPath;
		std::wstring widePath = UTF8ToWide([nsPath UTF8String]);

		{
			std::lock_guard<std::mutex> lock(impl->mutex);
			impl->eventQueue.push({action, widePath});
		}

		if (impl->callback)
			impl->callback(action, widePath);
	}
}

FileMonitorMac::FileMonitorMac()
	: m_impl(new Impl)
{
}

FileMonitorMac::~FileMonitorMac()
{
	terminate();
	delete m_impl;
}

bool FileMonitorMac::addDirectory(const std::wstring& path)
{
	std::lock_guard<std::mutex> lock(m_impl->mutex);
	if (m_impl->terminated) return false;

	std::string utf8Path = WideToUTF8(path);
	if (utf8Path.empty()) return false;

	NSString* nsPath = [NSString stringWithUTF8String:utf8Path.c_str()];
	CFStringRef cfPath = (__bridge CFStringRef)nsPath;
	CFArrayRef pathsToWatch = CFArrayCreate(nullptr, (const void**)&cfPath, 1, &kCFTypeArrayCallBacks);

	FSEventStreamContext context = {};
	context.info = m_impl;

	FSEventStreamRef stream = FSEventStreamCreate(
		nullptr,
		&fseventsCallback,
		&context,
		pathsToWatch,
		kFSEventStreamEventIdSinceNow,
		0.5, // latency in seconds
		kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
	);

	CFRelease(pathsToWatch);

	if (!stream) return false;

	FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
	FSEventStreamStart(stream);

	m_impl->streams.push_back(stream);
	m_impl->watchedPaths.push_back(path);

	return true;
}

void FileMonitorMac::removeDirectory(const std::wstring& path)
{
	std::lock_guard<std::mutex> lock(m_impl->mutex);

	for (size_t i = 0; i < m_impl->watchedPaths.size(); ++i)
	{
		if (m_impl->watchedPaths[i] == path)
		{
			FSEventStreamStop(m_impl->streams[i]);
			FSEventStreamInvalidate(m_impl->streams[i]);
			FSEventStreamRelease(m_impl->streams[i]);

			m_impl->streams.erase(m_impl->streams.begin() + i);
			m_impl->watchedPaths.erase(m_impl->watchedPaths.begin() + i);
			break;
		}
	}
}

void FileMonitorMac::setCallback(FileMonitorCallback callback)
{
	std::lock_guard<std::mutex> lock(m_impl->mutex);
	m_impl->callback = std::move(callback);
}

bool FileMonitorMac::pop(FileMonitorAction& action, std::wstring& path)
{
	std::lock_guard<std::mutex> lock(m_impl->mutex);
	if (m_impl->eventQueue.empty()) return false;

	auto& front = m_impl->eventQueue.front();
	action = front.first;
	path = front.second;
	m_impl->eventQueue.pop();
	return true;
}

void FileMonitorMac::terminate()
{
	// Copy streams under lock, then stop them without holding the mutex.
	// FSEventStreamStop can block waiting for in-flight callbacks that
	// also acquire the mutex, so holding it here would deadlock.
	std::vector<FSEventStreamRef> streamsToStop;
	{
		std::lock_guard<std::mutex> lock(m_impl->mutex);
		if (m_impl->terminated) return;
		m_impl->terminated = true;

		streamsToStop = std::move(m_impl->streams);
		m_impl->streams.clear();
		m_impl->watchedPaths.clear();
	}

	for (auto stream : streamsToStop)
	{
		FSEventStreamStop(stream);
		FSEventStreamInvalidate(stream);
		FSEventStreamRelease(stream);
	}
}
