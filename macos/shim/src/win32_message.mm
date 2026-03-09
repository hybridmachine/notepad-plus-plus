// Win32 Shim: Message dispatch for macOS
// Phase 1: Real WndProc dispatch via HandleRegistry.
// Scintilla messages are forwarded to ScintillaView via the bridge.

#import <Cocoa/Cocoa.h>
#include "windows.h"
#include "commctrl.h"
#include "handle_registry.h"
#include "win32_controls_impl.h"
#include "scintilla_bridge.h"

#include <unordered_map>
#include <string>

// Scintilla messages start at SCI_START (2000)
#define SCI_START 2000

// ============================================================
// SendMessage / PostMessage
// ============================================================

LRESULT SendMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	if (!hWnd)
		return 0;

	auto* info = HandleRegistry::getWindowInfo(hWnd);
	if (!info)
		return 0;

	// Scintilla messages: forward to ScintillaView via bridge
	if (info->isScintilla && info->nativeView && Msg >= SCI_START)
	{
		return static_cast<LRESULT>(
			ScintillaBridge_sendMessage(info->nativeView, Msg,
			                           static_cast<uintptr_t>(wParam),
			                           static_cast<intptr_t>(lParam)));
	}

	// Common control messages: route to control handler
	if (info->controlType != ControlType::None)
	{
		intptr_t controlResult = 0;
		if (Win32Controls_HandleMessage(reinterpret_cast<void*>(hWnd), info->controlType,
		                                 Msg, static_cast<uintptr_t>(wParam),
		                                 static_cast<intptr_t>(lParam), controlResult))
		{
			return static_cast<LRESULT>(controlResult);
		}
	}

	// Regular Win32 messages: dispatch to WndProc
	if (info->wndProc)
		return info->wndProc(hWnd, Msg, wParam, lParam);

	return DefWindowProcW(hWnd, Msg, wParam, lParam);
}

BOOL PostMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	// Post asynchronously on the main thread
	dispatch_async(dispatch_get_main_queue(), ^{
		SendMessageW(hWnd, Msg, wParam, lParam);
	});
	return TRUE;
}

LRESULT DefWindowProcW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	return 0;
}

LRESULT CallWindowProcW(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	if (lpPrevWndFunc)
		return lpPrevWndFunc(hWnd, Msg, wParam, lParam);
	return DefWindowProcW(hWnd, Msg, wParam, lParam);
}

// ============================================================
// Message loop
// ============================================================

BOOL PeekMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg)
{
	return FALSE;
}

BOOL GetMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax)
{
	// On macOS, the message loop is run by [NSApp run].
	// This function should not be called directly.
	return FALSE;
}

BOOL TranslateMessage(const MSG* lpMsg)
{
	return FALSE;
}

LRESULT DispatchMessageW(const MSG* lpMsg)
{
	return 0;
}

void PostQuitMessage(int nExitCode)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSApp terminate:nil];
	});
}

BOOL IsDialogMessageW(HWND hDlg, LPMSG lpMsg)
{
	return FALSE;
}

// ============================================================
// Dialog functions
// ============================================================

// Dialog result storage (per-dialog HWND)
static std::unordered_map<uintptr_t, INT_PTR> s_dialogResults;
static std::unordered_map<uintptr_t, bool> s_dialogEnded;

// Helper: Create a dialog window (NSPanel) with the given properties
static HWND createDialogWindow(HWND hWndParent, DLGPROC dlgProc, LPARAM initParam,
                                HINSTANCE hInstance, int width, int height,
                                const wchar_t* title, bool isModal)
{
	if (width <= 0) width = 400;
	if (height <= 0) height = 300;

	// Create NSPanel for dialog
	NSUInteger styleMask = NSWindowStyleMaskTitled |
	                       NSWindowStyleMaskClosable;

	NSRect contentRect = NSMakeRect(0, 0, width, height);
	NSPanel* panel = [[NSPanel alloc] initWithContentRect:contentRect
	                                    styleMask:styleMask
	                                    backing:NSBackingStoreBuffered
	                                    defer:NO];
	[panel setReleasedWhenClosed:NO];
	if (title)
	{
		size_t len = wcslen(title);
		NSString* nsTitle = [[NSString alloc] initWithBytes:title
		                                            length:len * sizeof(wchar_t)
		                                          encoding:NSUTF32LittleEndianStringEncoding];
		[panel setTitle:nsTitle ?: @"Dialog"];
	}

	// Center relative to parent
	if (hWndParent)
	{
		auto* parentInfo = HandleRegistry::getWindowInfo(hWndParent);
		if (parentInfo && parentInfo->nativeWindow)
		{
			NSWindow* parentWindow = (__bridge NSWindow*)parentInfo->nativeWindow;
			NSRect parentFrame = parentWindow.frame;
			CGFloat x = parentFrame.origin.x + (parentFrame.size.width - width) / 2;
			CGFloat y = parentFrame.origin.y + (parentFrame.size.height - height) / 2;
			[panel setFrameOrigin:NSMakePoint(x, y)];
		}
	}
	else
	{
		[panel center];
	}

	HandleRegistry::WindowInfo info;
	info.className = L"#32770"; // Standard dialog class
	info.windowName = title ? title : L"";
	info.style = WS_POPUP | WS_CAPTION | DS_MODALFRAME;
	info.exStyle = WS_EX_DLGMODALFRAME;
	info.hInst = hInstance;
	info.parent = hWndParent;
	info.nativeWindow = (__bridge void*)panel;
	info.nativeView = (__bridge void*)[panel contentView];
	info.wndProc = reinterpret_cast<WNDPROC>(dlgProc);

	HWND dlgHwnd = HandleRegistry::createWindow(info);

	// Send WM_INITDIALOG
	if (dlgProc)
		dlgProc(dlgHwnd, WM_INITDIALOG, 0, initParam);

	return dlgHwnd;
}

HWND CreateDialogParamW(HINSTANCE hInstance, LPCWSTR lpTemplateName,
                        HWND hWndParent, DLGPROC lpDialogFunc, LPARAM dwInitParam)
{
	// lpTemplateName is typically a resource ID — we don't have Windows resources
	// Create a default-sized dialog
	HWND dlgHwnd = createDialogWindow(hWndParent, lpDialogFunc, dwInitParam,
	                                   hInstance, 400, 300, L"Dialog", false);
	if (dlgHwnd)
	{
		auto* info = HandleRegistry::getWindowInfo(dlgHwnd);
		if (info && info->nativeWindow)
		{
			NSPanel* panel = (__bridge NSPanel*)info->nativeWindow;
			[panel makeKeyAndOrderFront:nil];
		}
	}
	return dlgHwnd;
}

HWND CreateDialogIndirectParamW(HINSTANCE hInstance, const void* lpTemplate,
                                HWND hWndParent, DLGPROC lpDialogFunc, LPARAM dwInitParam)
{
	// Parse DLGTEMPLATEEX if provided
	int width = 400, height = 300;
	const wchar_t* title = L"Dialog";

	if (lpTemplate)
	{
		// Check if it's DLGTEMPLATEEX (starts with version=1, signature=0xFFFF)
		const uint16_t* words = static_cast<const uint16_t*>(lpTemplate);
		if (words[0] == 1 && words[1] == 0xFFFF)
		{
			// DLGTEMPLATEEX
			const uint8_t* p = static_cast<const uint8_t*>(lpTemplate);
			uint16_t cDlgItems = *reinterpret_cast<const uint16_t*>(p + 16);
			int16_t cx = *reinterpret_cast<const int16_t*>(p + 22);
			int16_t cy = *reinterpret_cast<const int16_t*>(p + 24);
			// DLU to pixels (approximate)
			width = static_cast<int>(cx * 1.75);
			height = static_cast<int>(cy * 1.75);
			if (width < 100) width = 400;
			if (height < 50) height = 300;
		}
		else
		{
			// Standard DLGTEMPLATE
			const uint8_t* p = static_cast<const uint8_t*>(lpTemplate);
			int16_t cx = *reinterpret_cast<const int16_t*>(p + 14);
			int16_t cy = *reinterpret_cast<const int16_t*>(p + 16);
			width = static_cast<int>(cx * 1.75);
			height = static_cast<int>(cy * 1.75);
			if (width < 100) width = 400;
			if (height < 50) height = 300;
		}
	}

	HWND dlgHwnd = createDialogWindow(hWndParent, lpDialogFunc, dwInitParam,
	                                   hInstance, width, height, title, false);
	if (dlgHwnd)
	{
		auto* info = HandleRegistry::getWindowInfo(dlgHwnd);
		if (info && info->nativeWindow)
		{
			NSPanel* panel = (__bridge NSPanel*)info->nativeWindow;
			[panel makeKeyAndOrderFront:nil];
		}
	}
	return dlgHwnd;
}

INT_PTR DialogBoxParamW(HINSTANCE hInstance, LPCWSTR lpTemplateName,
                        HWND hWndParent, DLGPROC lpDialogFunc, LPARAM dwInitParam)
{
	HWND dlgHwnd = createDialogWindow(hWndParent, lpDialogFunc, dwInitParam,
	                                   hInstance, 400, 300, L"Dialog", true);
	if (!dlgHwnd) return -1;

	auto* info = HandleRegistry::getWindowInfo(dlgHwnd);
	if (!info || !info->nativeWindow)
	{
		HandleRegistry::destroyWindow(dlgHwnd);
		return -1;
	}

	uintptr_t key = reinterpret_cast<uintptr_t>(dlgHwnd);
	s_dialogEnded[key] = false;
	s_dialogResults[key] = 0;

	NSPanel* panel = (__bridge NSPanel*)info->nativeWindow;
	[panel makeKeyAndOrderFront:nil];

	// Run modal
	NSModalSession session = [NSApp beginModalSessionForWindow:panel];
	while (!s_dialogEnded[key])
	{
		if ([NSApp runModalSession:session] != NSModalResponseContinue)
			break;
	}
	[NSApp endModalSession:session];

	INT_PTR result = s_dialogResults[key];
	s_dialogEnded.erase(key);
	s_dialogResults.erase(key);

	// Destroy the dialog
	[panel orderOut:nil];
	HandleRegistry::destroyWindow(dlgHwnd);

	return result;
}

INT_PTR DialogBoxIndirectParamW(HINSTANCE hInstance, const void* hDialogTemplate,
                                HWND hWndParent, DLGPROC lpDialogFunc, LPARAM dwInitParam)
{
	return DialogBoxParamW(hInstance, nullptr, hWndParent, lpDialogFunc, dwInitParam);
}

BOOL EndDialog(HWND hDlg, INT_PTR nResult)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hDlg);

	// Check if modal
	auto it = s_dialogEnded.find(key);
	if (it != s_dialogEnded.end())
	{
		s_dialogResults[key] = nResult;
		s_dialogEnded[key] = true;
		[NSApp stopModal];
	}
	else
	{
		// Modeless dialog: just close it
		auto* info = HandleRegistry::getWindowInfo(hDlg);
		if (info && info->nativeWindow)
		{
			NSWindow* window = (__bridge NSWindow*)info->nativeWindow;
			[window orderOut:nil];
		}
	}
	return TRUE;
}

// ============================================================
// Dialog item functions
// ============================================================

BOOL SetDlgItemTextW(HWND hDlg, int nIDDlgItem, LPCWSTR lpString)
{
	HWND hCtrl = GetDlgItem(hDlg, nIDDlgItem);
	if (hCtrl)
		return SetWindowTextW(hCtrl, lpString);
	return FALSE;
}

BOOL SetDlgItemTextA(HWND hDlg, int nIDDlgItem, LPCSTR lpString)
{
	if (!lpString) return SetDlgItemTextW(hDlg, nIDDlgItem, nullptr);

	// Convert ASCII to wide
	std::wstring wide;
	for (const char* p = lpString; *p; ++p)
		wide += static_cast<wchar_t>(static_cast<unsigned char>(*p));
	return SetDlgItemTextW(hDlg, nIDDlgItem, wide.c_str());
}

UINT GetDlgItemTextW(HWND hDlg, int nIDDlgItem, LPWSTR lpString, int cchMax)
{
	if (lpString && cchMax > 0) lpString[0] = L'\0';

	HWND hCtrl = GetDlgItem(hDlg, nIDDlgItem);
	if (hCtrl)
		return static_cast<UINT>(GetWindowTextW(hCtrl, lpString, cchMax));
	return 0;
}

UINT GetDlgItemTextA(HWND hDlg, int nIDDlgItem, LPSTR lpString, int cchMax)
{
	if (lpString && cchMax > 0) lpString[0] = '\0';

	wchar_t wBuf[4096];
	UINT len = GetDlgItemTextW(hDlg, nIDDlgItem, wBuf, 4096);
	if (len > 0 && lpString && cchMax > 0)
	{
		int i = 0;
		for (; i < static_cast<int>(len) && i < cchMax - 1; ++i)
			lpString[i] = static_cast<char>(wBuf[i] & 0x7F);
		lpString[i] = '\0';
		return static_cast<UINT>(i);
	}
	return 0;
}

BOOL SetDlgItemInt(HWND hDlg, int nIDDlgItem, UINT uValue, BOOL bSigned)
{
	wchar_t buf[32];
	if (bSigned)
		swprintf(buf, 32, L"%d", static_cast<int>(uValue));
	else
		swprintf(buf, 32, L"%u", uValue);
	return SetDlgItemTextW(hDlg, nIDDlgItem, buf);
}

UINT GetDlgItemInt(HWND hDlg, int nIDDlgItem, BOOL* lpTranslated, BOOL bSigned)
{
	wchar_t buf[32];
	if (GetDlgItemTextW(hDlg, nIDDlgItem, buf, 32) == 0)
	{
		if (lpTranslated) *lpTranslated = FALSE;
		return 0;
	}

	wchar_t* endPtr = nullptr;
	long val = wcstol(buf, &endPtr, 10);
	if (endPtr == buf || *endPtr != L'\0')
	{
		if (lpTranslated) *lpTranslated = FALSE;
		return 0;
	}

	if (lpTranslated) *lpTranslated = TRUE;
	return static_cast<UINT>(val);
}

LRESULT SendDlgItemMessageW(HWND hDlg, int nIDDlgItem, UINT Msg, WPARAM wParam, LPARAM lParam)
{
	HWND hCtrl = GetDlgItem(hDlg, nIDDlgItem);
	if (hCtrl)
		return SendMessageW(hCtrl, Msg, wParam, lParam);
	return 0;
}

BOOL CheckDlgButton(HWND hDlg, int nIDButton, UINT uCheck)
{
	HWND hCtrl = GetDlgItem(hDlg, nIDButton);
	if (hCtrl)
	{
		SendMessageW(hCtrl, BM_SETCHECK, uCheck, 0);
		return TRUE;
	}
	return FALSE;
}

UINT IsDlgButtonChecked(HWND hDlg, int nIDButton)
{
	HWND hCtrl = GetDlgItem(hDlg, nIDButton);
	if (hCtrl)
		return static_cast<UINT>(SendMessageW(hCtrl, BM_GETCHECK, 0, 0));
	return BST_UNCHECKED;
}

BOOL CheckRadioButton(HWND hDlg, int nIDFirstButton, int nIDLastButton, int nIDCheckButton)
{
	for (int id = nIDFirstButton; id <= nIDLastButton; ++id)
	{
		HWND hCtrl = GetDlgItem(hDlg, id);
		if (hCtrl)
			SendMessageW(hCtrl, BM_SETCHECK, (id == nIDCheckButton) ? BST_CHECKED : BST_UNCHECKED, 0);
	}
	return TRUE;
}

HWND GetNextDlgTabItem(HWND hDlg, HWND hCtl, BOOL bPrevious) { return nullptr; }

BOOL MapDialogRect(HWND hDlg, LPRECT lpRect)
{
	if (lpRect)
	{
		// Approximate DLU to pixel conversion
		lpRect->left = static_cast<LONG>(lpRect->left * 1.75);
		lpRect->top = static_cast<LONG>(lpRect->top * 1.75);
		lpRect->right = static_cast<LONG>(lpRect->right * 1.75);
		lpRect->bottom = static_cast<LONG>(lpRect->bottom * 1.75);
	}
	return TRUE;
}
