#pragma once
// Win32 Controls Implementation Interface
// Routes control creation and messages for known control classes:
//   SysTabControl32, msctls_statusbar32, ToolbarWindow32, ReBarWindow32, tooltips_class32
//
// This header is included by win32_window.mm and win32_message.mm to
// intercept CreateWindowEx and SendMessage for control class names.

#ifdef __APPLE__

#include <string>

// Control type enum stored in HandleRegistry::WindowInfo
enum class ControlType
{
	None = 0,
	TabControl,
	StatusBar,
	Toolbar,
	ReBar,
	Tooltip,
	ListView,
	TreeView
};

// Check if className is a known common control class
bool Win32Controls_IsControlClass(const std::wstring& className);

// Determine control type from class name
ControlType Win32Controls_GetControlType(const std::wstring& className);

// Create a control, returning the native NSView* (as void*) to store in WindowInfo.
// Called from CreateWindowExW when IsControlClass returns true.
void* Win32Controls_CreateControl(ControlType type, void* parentView,
                                   int x, int y, int width, int height,
                                   unsigned long style, unsigned long exStyle);

// Handle a control-specific message (TCM_*, SB_*, TB_*, RB_*, etc.)
// Returns true if the message was handled. result is set to the return value.
bool Win32Controls_HandleMessage(void* hwnd, ControlType type,
                                  unsigned int msg, uintptr_t wParam, intptr_t lParam,
                                  intptr_t& result);

// Destroy a control and clean up associated data.
void Win32Controls_DestroyControl(void* hwnd, ControlType type);

#endif // __APPLE__
