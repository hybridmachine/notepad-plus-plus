// HandleRegistry implementation
// Maps HWND (opaque pointers) to WindowInfo structs containing
// native NSView*/NSWindow* pointers and per-window Win32 state.

#import <Cocoa/Cocoa.h>
#include "windows.h"
#include "handle_registry.h"

#include <unordered_map>
#include <mutex>

namespace HandleRegistry {

// HWND allocation: start at 0x10000 to avoid null/low-value confusion
static uintptr_t s_nextHwnd = 0x10000;

// Maps: HWND → WindowInfo
static std::unordered_map<uintptr_t, WindowInfo> s_windows;

// Maps: class name → ClassInfo
static std::unordered_map<std::wstring, ClassInfo> s_classes;

// Main window (first top-level window created)
static HWND s_mainWindow = nullptr;

// Recursive mutex: needed because getChildren() holds the lock while calling
// callbacks that may call getWindowInfo() (e.g. GetDlgItem).
static std::recursive_mutex s_mutex;

// ============================================================
// Class registration
// ============================================================

bool registerClass(const std::wstring& name, WNDPROC wndProc, HINSTANCE hInst,
                   int cbWndExtra, DWORD style)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	ClassInfo info;
	info.className = name;
	info.wndProc = wndProc;
	info.hInstance = hInst;
	info.cbWndExtra = cbWndExtra;
	info.style = style;

	s_classes[name] = info;
	return true;
}

const ClassInfo* findClass(const std::wstring& name)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	auto it = s_classes.find(name);
	if (it != s_classes.end())
		return &it->second;
	return nullptr;
}

// ============================================================
// Window handle management
// ============================================================

HWND createWindow(WindowInfo info)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	// Retain native objects so ARC doesn't release them while HandleRegistry holds the void* pointers.
	// The matching CFRelease calls are in destroyWindow().
	if (info.nativeWindow)
		CFRetain(info.nativeWindow);
	if (info.nativeView)
		CFRetain(info.nativeView);

	HWND hwnd = reinterpret_cast<HWND>(s_nextHwnd++);
	s_windows[reinterpret_cast<uintptr_t>(hwnd)] = std::move(info);

	// Track first top-level window as main window
	if (!s_mainWindow && info.nativeWindow != nullptr)
		s_mainWindow = hwnd;

	return hwnd;
}

WindowInfo* getWindowInfo(HWND hwnd)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	auto it = s_windows.find(reinterpret_cast<uintptr_t>(hwnd));
	if (it != s_windows.end())
		return &it->second;
	return nullptr;
}

void destroyWindow(HWND hwnd)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	auto it = s_windows.find(reinterpret_cast<uintptr_t>(hwnd));
	if (it != s_windows.end())
	{
		// Remove native view from superview
		if (it->second.nativeView)
		{
			NSView* view = (__bridge NSView*)it->second.nativeView;
			[view removeFromSuperview];
		}

		// Close native window
		if (it->second.nativeWindow)
		{
			NSWindow* window = (__bridge NSWindow*)it->second.nativeWindow;
			[window close];
		}

		// Release the CFRetain from createWindow() — must happen after close/removeFromSuperview
		if (it->second.nativeView)
			CFRelease(it->second.nativeView);
		if (it->second.nativeWindow)
			CFRelease(it->second.nativeWindow);

		if (s_mainWindow == hwnd)
			s_mainWindow = nullptr;

		s_windows.erase(it);
	}
}

HWND findByNativeView(void* nativeView)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	for (auto& [key, info] : s_windows)
	{
		if (info.nativeView == nativeView)
			return reinterpret_cast<HWND>(key);
	}
	return nullptr;
}

HWND findByNativeWindow(void* nativeWindow)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	for (auto& [key, info] : s_windows)
	{
		if (info.nativeWindow == nativeWindow)
			return reinterpret_cast<HWND>(key);
	}
	return nullptr;
}

void getChildren(HWND parent, void (*callback)(HWND child, void* context), void* context)
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);

	for (auto& [key, info] : s_windows)
	{
		if (info.parent == parent)
		{
			callback(reinterpret_cast<HWND>(key), context);
		}
	}
}

HWND getMainWindow()
{
	std::lock_guard<std::recursive_mutex> lock(s_mutex);
	return s_mainWindow;
}

} // namespace HandleRegistry
