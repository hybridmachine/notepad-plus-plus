#pragma once
// Internal header: Declares control management functions used by
// win32_window.mm and win32_message.mm to route creation and messages
// to the common control implementations in win32_controls.mm.

#ifdef __APPLE__

#include "handle_registry.h"

// Check if a class name is a known common control
bool Win32Controls_IsControlClass(const wchar_t* className);

// Create native backing view for a common control.
// Returns the native view (void* to NSView*), or nullptr if not a control.
void* Win32Controls_CreateControl(HWND hWnd, const wchar_t* className,
                                   void* parentView, int x, int y, int w, int h,
                                   DWORD style);

// Route a message to the appropriate control handler.
// Returns true if the message was handled (result stored in *pResult).
bool Win32Controls_HandleMessage(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam, LRESULT* pResult);

// Clean up control data when a window is destroyed.
void Win32Controls_DestroyControl(HWND hWnd);

// Map class name to ControlType.
HandleRegistry::ControlType Win32Controls_GetControlType(const wchar_t* className);

#endif // __APPLE__
