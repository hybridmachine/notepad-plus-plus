// macOS File Monitoring via FSEvents
// Replacement for ReadDirectoryChanges/ on Windows.

#import <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>
#include <mutex>
#include <queue>
#include <string>
#include <vector>

#include "file_monitor_mac.h"

struct FileChangeEvent
{
	uint32_t action;
	std::string path;
};

struct MonitoredDir
{
	std::string path;
	bool watchSubtree;
	FSEventStreamRef stream;
};

struct FileMonitorMac::Impl
{
	std::vector<MonitoredDir> directories;
	std::queue<FileChangeEvent> eventQueue;
	mutable std::mutex mutex;
	FileMonitorMac::ChangeCallback callback;
	bool initialized = false;

	static void fsEventsCallback(ConstFSEventStreamRef streamRef,
	                              void* clientCallBackInfo,
	                              size_t numEvents,
	                              void* eventPaths,
	                              const FSEventStreamEventFlags eventFlags[],
	                              const FSEventStreamEventId eventIds[])
	{
		auto* impl = static_cast<FileMonitorMac::Impl*>(clientCallBackInfo);
		char** paths = static_cast<char**>(eventPaths);

		for (size_t i = 0; i < numEvents; ++i)
		{
			FileChangeEvent event;
			event.path = paths[i];

			FSEventStreamEventFlags flags = eventFlags[i];

			if (flags & kFSEventStreamEventFlagItemCreated)
				event.action = FILE_ACTION_ADDED;
			else if (flags & kFSEventStreamEventFlagItemRemoved)
				event.action = FILE_ACTION_REMOVED;
			else if (flags & kFSEventStreamEventFlagItemRenamed)
				event.action = FILE_ACTION_RENAMED_NEW_NAME;
			else if (flags & kFSEventStreamEventFlagItemModified)
				event.action = FILE_ACTION_MODIFIED;
			else if (flags & kFSEventStreamEventFlagItemInodeMetaMod)
				event.action = FILE_ACTION_MODIFIED;
			else
				event.action = FILE_ACTION_MODIFIED; // Default to modified

			{
				std::lock_guard<std::mutex> lock(impl->mutex);
				impl->eventQueue.push(event);
			}

			if (impl->callback)
				impl->callback(event.action, event.path);
		}
	}
};

FileMonitorMac::FileMonitorMac()
	: _impl(new Impl)
{
}

FileMonitorMac::~FileMonitorMac()
{
	terminate();
	delete _impl;
}

bool FileMonitorMac::init()
{
	_impl->initialized = true;
	return true;
}

bool FileMonitorMac::addDirectory(const std::string& path, bool watchSubtree)
{
	if (!_impl->initialized)
		return false;

	@autoreleasepool {
		NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
		CFStringRef cfPath = (__bridge CFStringRef)nsPath;
		CFArrayRef pathsToWatch = CFArrayCreate(nullptr, (const void**)&cfPath, 1, &kCFTypeArrayCallBacks);

		FSEventStreamContext context = {};
		context.info = _impl;

		// Latency of 0.5 seconds provides a good balance between responsiveness and batching
		CFAbsoluteTime latency = 0.5;

		FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagFileEvents |
		                                  kFSEventStreamCreateFlagUseCFTypes;
		if (!watchSubtree)
			flags |= kFSEventStreamCreateFlagNoDefer;

		FSEventStreamRef stream = FSEventStreamCreate(
			nullptr,
			&Impl::fsEventsCallback,
			&context,
			pathsToWatch,
			kFSEventStreamEventIdSinceNow,
			latency,
			flags
		);

		CFRelease(pathsToWatch);

		if (!stream)
			return false;

		// Schedule on main run loop
		FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
		FSEventStreamStart(stream);

		MonitoredDir dir;
		dir.path = path;
		dir.watchSubtree = watchSubtree;
		dir.stream = stream;

		std::lock_guard<std::mutex> lock(_impl->mutex);
		_impl->directories.push_back(dir);
	}

	return true;
}

void FileMonitorMac::removeDirectory(const std::string& path)
{
	std::lock_guard<std::mutex> lock(_impl->mutex);
	for (auto it = _impl->directories.begin(); it != _impl->directories.end(); ++it)
	{
		if (it->path == path)
		{
			FSEventStreamStop(it->stream);
			FSEventStreamInvalidate(it->stream);
			FSEventStreamRelease(it->stream);
			_impl->directories.erase(it);
			return;
		}
	}
}

void FileMonitorMac::removeAll()
{
	std::lock_guard<std::mutex> lock(_impl->mutex);
	for (auto& dir : _impl->directories)
	{
		FSEventStreamStop(dir.stream);
		FSEventStreamInvalidate(dir.stream);
		FSEventStreamRelease(dir.stream);
	}
	_impl->directories.clear();
}

bool FileMonitorMac::pop(uint32_t& action, std::string& filePath)
{
	std::lock_guard<std::mutex> lock(_impl->mutex);
	if (_impl->eventQueue.empty())
		return false;

	auto& event = _impl->eventQueue.front();
	action = event.action;
	filePath = event.path;
	_impl->eventQueue.pop();
	return true;
}

bool FileMonitorMac::hasPending() const
{
	std::lock_guard<std::mutex> lock(_impl->mutex);
	return !_impl->eventQueue.empty();
}

void FileMonitorMac::terminate()
{
	removeAll();
	_impl->initialized = false;

	// Clear pending events
	std::lock_guard<std::mutex> lock(_impl->mutex);
	while (!_impl->eventQueue.empty())
		_impl->eventQueue.pop();
}

void FileMonitorMac::setCallback(ChangeCallback cb)
{
	_impl->callback = cb;
}
