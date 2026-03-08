#pragma once
// macOS File Monitoring via FSEvents
// Replacement for ReadDirectoryChanges/ on Windows.
// Monitors directories for file changes and provides a queue-based
// interface compatible with CReadDirectoryChanges usage patterns.

#ifdef __APPLE__

#include <string>
#include <vector>
#include <functional>

// File change action codes (matching Windows FILE_ACTION_* values)
#define FILE_ACTION_ADDED            0x00000001
#define FILE_ACTION_REMOVED          0x00000002
#define FILE_ACTION_MODIFIED         0x00000003
#define FILE_ACTION_RENAMED_OLD_NAME 0x00000004
#define FILE_ACTION_RENAMED_NEW_NAME 0x00000005

class FileMonitorMac
{
public:
	FileMonitorMac();
	~FileMonitorMac();

	// Initialize the monitor (start background processing)
	bool init();

	// Add a directory to monitor
	// path: UTF-8 encoded directory path
	// watchSubtree: monitor subdirectories recursively
	bool addDirectory(const std::string& path, bool watchSubtree);

	// Remove a previously added directory
	void removeDirectory(const std::string& path);

	// Remove all monitored directories
	void removeAll();

	// Pop the next file change event from the queue
	// Returns true if an event was available
	bool pop(uint32_t& action, std::string& filePath);

	// Check if there are pending events
	bool hasPending() const;

	// Terminate monitoring and clean up
	void terminate();

	// Callback type for real-time notifications
	using ChangeCallback = std::function<void(uint32_t action, const std::string& path)>;

	// Set optional callback for immediate notification (in addition to queue)
	void setCallback(ChangeCallback cb);

private:
	struct Impl;
	Impl* _impl;
};

#endif // __APPLE__
