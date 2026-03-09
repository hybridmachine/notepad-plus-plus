#pragma once
// File Monitor for macOS — FSEvents-based replacement for ReadDirectoryChanges
// Watches directories for file changes and provides a queue-based interface.

#ifdef __APPLE__

#include <string>
#include <functional>

// Callback type: receives action (added/removed/modified/renamed) and file path
enum class FileMonitorAction
{
	Added,
	Removed,
	Modified,
	RenamedOld,
	RenamedNew
};

using FileMonitorCallback = std::function<void(FileMonitorAction action, const std::wstring& path)>;

class FileMonitorMac
{
public:
	FileMonitorMac();
	~FileMonitorMac();

	// Start watching a directory. Multiple directories can be watched.
	bool addDirectory(const std::wstring& path);

	// Stop watching a directory.
	void removeDirectory(const std::wstring& path);

	// Set callback for immediate notification (called on the main thread).
	void setCallback(FileMonitorCallback callback);

	// Pop the next event from the queue (thread-safe). Returns false if empty.
	bool pop(FileMonitorAction& action, std::wstring& path);

	// Stop all monitoring and clean up.
	void terminate();

	// Public so the FSEvents C callback can access it
	struct Impl;
	Impl* m_impl;
};

#endif // __APPLE__
