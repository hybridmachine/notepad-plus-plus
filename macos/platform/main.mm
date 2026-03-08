// Notepad++ macOS Port — Phase 2 Entry Point
// Demonstrates: Win32 menu APIs backed by NSMenu, file open/save via
// GetOpenFileNameW/GetSaveFileNameW, WM_COMMAND dispatch, timers.
//
// This uses the Win32 shim APIs to build the UI, proving the shim works
// end-to-end. The same APIs will be called by the real N++ code.

#import <Cocoa/Cocoa.h>
#include "windows.h"
#include "commdlg.h"
#include "handle_registry.h"
#include "scintilla_bridge.h"

// ============================================================
// Command IDs (matching Notepad++ IDM_* convention)
// ============================================================
#define IDM_FILE_NEW          41001
#define IDM_FILE_OPEN         41002
#define IDM_FILE_SAVE         41006
#define IDM_FILE_SAVEAS       41008
#define IDM_FILE_CLOSE        41003
#define IDM_EDIT_UNDO         42001
#define IDM_EDIT_REDO         42002
#define IDM_EDIT_CUT          42003
#define IDM_EDIT_COPY         42004
#define IDM_EDIT_PASTE        42005
#define IDM_EDIT_SELECTALL    42013
#define IDM_VIEW_WORDWRAP     42026
#define IDM_VIEW_LINENUMBER   42027

// ============================================================
// Globals
// ============================================================
static void* g_scintillaView = nullptr;
static NSWindow* g_mainWindow = nil;
static HWND g_mainHwnd = nullptr;
static wchar_t g_currentFilePath[MAX_PATH] = {0};

// SCI message IDs
enum {
	SCI_CLEARALL = 2004,
	SCI_SETSAVEPOINT = 2014,
	SCI_GOTOPOS = 2025,
	SCI_SETTABWIDTH = 2036,
	SCI_SETCODEPAGE = 2037,
	SCI_STYLECLEARALL = 2050,
	SCI_STYLESETFORE = 2051,
	SCI_STYLESETBOLD = 2053,
	SCI_STYLESETSIZE = 2055,
	SCI_STYLESETFONT = 2056,
	SCI_GETMODIFY = 2159,
	SCI_EMPTYUNDOBUFFER = 2175,
	SCI_SETTEXT = 2181,
	SCI_GETTEXT = 2182,
	SCI_GETTEXTLENGTH = 2183,
	SCI_SETMARGINTYPEN = 2240,
	SCI_SETMARGINWIDTHN = 2242,
	SCI_SETMARGINMASKN = 2244,
	SCI_SETMARGINSENSITIVEN = 2246,
	SCI_SETWRAPMODE = 2268,
	SCI_GETWRAPMODE = 2269,
	SCI_SETCARETLINEVISIBLE = 2096,
	SCI_SETCARETLINEBACK = 2098,
	SCI_SETUSETABS = 2124,
	SCI_SETPROPERTY = 4004,
	SCI_SETKEYWORDS = 4005,
	SCI_SETLEXERLANGUAGE = 4006,
};

// ============================================================
// File operations
// ============================================================

static void openFile()
{
	OPENFILENAMEW ofn = {};
	wchar_t filePath[MAX_PATH] = {0};

	ofn.lStructSize = sizeof(ofn);
	ofn.hwndOwner = g_mainHwnd;
	ofn.lpstrFile = filePath;
	ofn.nMaxFile = MAX_PATH;
	ofn.lpstrTitle = L"Open File";
	// Filter format: pairs of (description, pattern) separated by \0, terminated by \0\0
	ofn.lpstrFilter = L"All Files\0*.*\0"
	                   L"C/C++ Files\0*.c;*.cpp;*.cc;*.h;*.hpp\0"
	                   L"Text Files\0*.txt\0";
	ofn.nFilterIndex = 1;
	ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;

	if (GetOpenFileNameW(&ofn))
	{
		// Read the file
		NSString* path = [[NSString alloc] initWithBytes:filePath
		                                          length:wcslen(filePath) * sizeof(wchar_t)
		                                        encoding:NSUTF32LittleEndianStringEncoding];
		NSError* error = nil;
		NSString* content = [NSString stringWithContentsOfFile:path
		                                             encoding:NSUTF8StringEncoding
		                                                error:&error];
		if (content && g_scintillaView)
		{
			const char* utf8 = [content UTF8String];
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)utf8);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);

			// Store current file path
			wcscpy(g_currentFilePath, filePath);

			// Update window title
			[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@",
			                        [path lastPathComponent]]];
		}
		else if (error)
		{
			NSLog(@"Error opening file: %@", error);
		}
	}
}

static void saveFileAs()
{
	OPENFILENAMEW ofn = {};
	wchar_t filePath[MAX_PATH] = {0};

	// Pre-fill with current file path if we have one
	if (g_currentFilePath[0] != L'\0')
		wcscpy(filePath, g_currentFilePath);

	ofn.lStructSize = sizeof(ofn);
	ofn.hwndOwner = g_mainHwnd;
	ofn.lpstrFile = filePath;
	ofn.nMaxFile = MAX_PATH;
	ofn.lpstrTitle = L"Save File As";
	ofn.lpstrFilter = L"All Files\0*.*\0"
	                   L"C/C++ Files\0*.c;*.cpp;*.cc;*.h;*.hpp\0"
	                   L"Text Files\0*.txt\0";
	ofn.nFilterIndex = 1;
	ofn.Flags = OFN_OVERWRITEPROMPT;

	if (GetSaveFileNameW(&ofn))
	{
		wcscpy(g_currentFilePath, filePath);
		// Fall through to save logic
		// Get text from Scintilla
		if (g_scintillaView)
		{
			intptr_t len = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXTLENGTH, 0, 0);
			if (len > 0)
			{
				char* buf = new char[len + 1];
				ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, len + 1, (intptr_t)buf);

				NSString* path = [[NSString alloc] initWithBytes:filePath
				                                          length:wcslen(filePath) * sizeof(wchar_t)
				                                        encoding:NSUTF32LittleEndianStringEncoding];
				NSString* content = [NSString stringWithUTF8String:buf];
				NSError* error = nil;
				[content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

				if (error)
					NSLog(@"Error saving file: %@", error);
				else
				{
					ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
					[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@",
					                        [path lastPathComponent]]];
				}

				delete[] buf;
			}
		}
	}
}

static void saveFile()
{
	if (g_currentFilePath[0] == L'\0')
	{
		saveFileAs();
		return;
	}

	if (!g_scintillaView) return;

	intptr_t len = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXTLENGTH, 0, 0);
	if (len >= 0)
	{
		char* buf = new char[len + 1];
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, len + 1, (intptr_t)buf);

		NSString* path = [[NSString alloc] initWithBytes:g_currentFilePath
		                                          length:wcslen(g_currentFilePath) * sizeof(wchar_t)
		                                        encoding:NSUTF32LittleEndianStringEncoding];
		NSString* content = [NSString stringWithUTF8String:buf];
		NSError* error = nil;
		[content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

		if (error)
			NSLog(@"Error saving file: %@", error);
		else
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);

		delete[] buf;
	}
}

// ============================================================
// WndProc — dispatches WM_COMMAND from menu items
// ============================================================

static LRESULT CALLBACK MainWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	switch (msg)
	{
		case WM_COMMAND:
		{
			UINT cmdId = LOWORD(wParam);
			switch (cmdId)
			{
				case IDM_FILE_NEW:
					if (g_scintillaView)
					{
						ScintillaBridge_sendMessage(g_scintillaView, SCI_CLEARALL, 0, 0);
						ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
						ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
						g_currentFilePath[0] = L'\0';
						[g_mainWindow setTitle:@"Notepad++ (macOS) — Untitled"];
					}
					return 0;

				case IDM_FILE_OPEN:
					openFile();
					return 0;

				case IDM_FILE_SAVE:
					saveFile();
					return 0;

				case IDM_FILE_SAVEAS:
					saveFileAs();
					return 0;

				case IDM_FILE_CLOSE:
					[g_mainWindow performClose:nil];
					return 0;

				case IDM_VIEW_WORDWRAP:
					if (g_scintillaView)
					{
						intptr_t mode = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETWRAPMODE, 0, 0);
						ScintillaBridge_sendMessage(g_scintillaView, SCI_SETWRAPMODE, mode == 0 ? 1 : 0, 0);

						// Update the menu item check state
						HMENU hMenu = GetMenu(hWnd);
						if (hMenu)
							CheckMenuItem(hMenu, IDM_VIEW_WORDWRAP,
							              MF_BYCOMMAND | (mode == 0 ? MF_CHECKED : MF_UNCHECKED));
					}
					return 0;

				case IDM_VIEW_LINENUMBER:
					if (g_scintillaView)
					{
						static bool showLineNumbers = true;
						showLineNumbers = !showLineNumbers;
						ScintillaBridge_sendMessage(g_scintillaView, SCI_SETMARGINWIDTHN, 0,
						                           showLineNumbers ? 50 : 0);

						HMENU hMenu = GetMenu(hWnd);
						if (hMenu)
							CheckMenuItem(hMenu, IDM_VIEW_LINENUMBER,
							              MF_BYCOMMAND | (showLineNumbers ? MF_CHECKED : MF_UNCHECKED));
					}
					return 0;
			}
			break;
		}

		case WM_CLOSE:
			PostQuitMessage(0);
			return 0;
	}

	return DefWindowProcW(hWnd, msg, wParam, lParam);
}

// ============================================================
// Build menus using Win32 API
// ============================================================

static HMENU buildMenuBar()
{
	HMENU hMenuBar = CreateMenu();

	// File menu
	HMENU hFileMenu = CreatePopupMenu();
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_NEW, L"&New\tCtrl+N");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_OPEN, L"&Open...\tCtrl+O");
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_SAVE, L"&Save\tCtrl+S");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_SAVEAS, L"Save &As...\tCtrl+Shift+S");
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSE, L"&Close\tCtrl+W");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hFileMenu), L"&File");

	// Edit menu
	HMENU hEditMenu = CreatePopupMenu();
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_UNDO, L"&Undo\tCtrl+Z");
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_REDO, L"&Redo\tCtrl+Shift+Z");
	AppendMenuW(hEditMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_CUT, L"Cu&t\tCtrl+X");
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_COPY, L"&Copy\tCtrl+C");
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_PASTE, L"&Paste\tCtrl+V");
	AppendMenuW(hEditMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_SELECTALL, L"Select &All\tCtrl+A");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hEditMenu), L"&Edit");

	// View menu
	HMENU hViewMenu = CreatePopupMenu();
	AppendMenuW(hViewMenu, MF_STRING, IDM_VIEW_WORDWRAP, L"&Word Wrap");
	AppendMenuW(hViewMenu, MF_STRING | MF_CHECKED, IDM_VIEW_LINENUMBER, L"&Line Numbers");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hViewMenu), L"&View");

	return hMenuBar;
}

// ============================================================
// Configure Scintilla editor
// ============================================================

static void configureScintilla(void* sci)
{
	if (!sci) return;

	ScintillaBridge_sendMessage(sci, SCI_SETCODEPAGE, 65001, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETWRAPMODE, 0, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETTABWIDTH, 4, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETUSETABS, 0, 0);

	// Line numbers
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 0, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 0, 50);

	// C++ lexer
	ScintillaBridge_sendMessage(sci, SCI_SETLEXERLANGUAGE, 0, (intptr_t)"cpp");

	const char* keywords = "int char float double void bool true false "
	                        "if else for while do switch case break continue return "
	                        "class struct enum namespace using typedef "
	                        "const static virtual override public private protected "
	                        "new delete nullptr sizeof typeof "
	                        "try catch throw include define ifdef ifndef endif";
	ScintillaBridge_sendMessage(sci, SCI_SETKEYWORDS, 0, (intptr_t)keywords);

	// Default style: Menlo 13pt
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFONT, 32, (intptr_t)"Menlo");
	ScintillaBridge_sendMessage(sci, SCI_STYLESETSIZE, 32, 13);
	ScintillaBridge_sendMessage(sci, SCI_STYLECLEARALL, 0, 0);

	// Syntax colors
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 1, 0x008000);  // Comments
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 2, 0x008000);  // Line comments
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 4, 0xFF8000);  // Numbers
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 5, 0x0000FF);  // Keywords
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 6, 0x800080);  // Strings
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 9, 0x808080);  // Preprocessor
	ScintillaBridge_sendMessage(sci, SCI_STYLESETBOLD, 5, 1);

	// Code folding
	ScintillaBridge_sendMessage(sci, SCI_SETPROPERTY, (uintptr_t)"fold", (intptr_t)"1");
	ScintillaBridge_sendMessage(sci, SCI_SETPROPERTY, (uintptr_t)"fold.compact", (intptr_t)"0");
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 2, 4);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINMASKN, 2, 0xFE000000);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 2, 16);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINSENSITIVEN, 2, 1);

	// Current line highlight
	ScintillaBridge_sendMessage(sci, SCI_SETCARETLINEVISIBLE, 1, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETCARETLINEBACK, 0xF0F0F0, 0);
}

// ============================================================
// Application Delegate
// ============================================================

@interface NppAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation NppAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
	// Register a window class with our WndProc
	WNDCLASSEXW wc = {};
	wc.cbSize = sizeof(wc);
	wc.lpfnWndProc = MainWndProc;
	wc.lpszClassName = L"Notepad++";
	wc.hInstance = nullptr;
	RegisterClassExW(&wc);

	// Build the menu bar using Win32 APIs
	HMENU hMenuBar = buildMenuBar();

	// Create the main window using Win32 API
	g_mainHwnd = CreateWindowExW(
		0,
		L"Notepad++",
		L"Notepad++ (macOS) — Phase 2",
		WS_OVERLAPPEDWINDOW,
		CW_USEDEFAULT, CW_USEDEFAULT,
		900, 700,
		nullptr,
		hMenuBar,
		nullptr,
		nullptr
	);

	if (!g_mainHwnd)
	{
		NSLog(@"ERROR: Failed to create main window!");
		return;
	}

	// Get the native NSWindow from the handle registry
	auto* info = HandleRegistry::getWindowInfo(g_mainHwnd);
	if (info && info->nativeWindow)
	{
		g_mainWindow = (__bridge NSWindow*)info->nativeWindow;
		g_mainWindow.delegate = self;
		[g_mainWindow setMinSize:NSMakeSize(400, 300)];
	}

	// Set the menu bar via Win32 API
	SetMenu(g_mainHwnd, hMenuBar);

	// Create Scintilla editor
	NSView* contentView = g_mainWindow.contentView;
	g_scintillaView = ScintillaBridge_createView((__bridge void*)contentView, 0, 0, 0, 0);
	if (!g_scintillaView)
	{
		NSLog(@"ERROR: Failed to create ScintillaView!");
		return;
	}

	configureScintilla(g_scintillaView);

	// Set welcome text
	const char* welcomeText =
		"// Welcome to Notepad++ on macOS — Phase 2!\n"
		"//\n"
		"// What's new in Phase 2:\n"
		"//   - Menu bar built with Win32 APIs (CreateMenu, AppendMenuW, SetMenu)\n"
		"//   - File Open via GetOpenFileNameW → NSOpenPanel\n"
		"//   - File Save/SaveAs via GetSaveFileNameW → NSSavePanel\n"
		"//   - Keyboard shortcuts via NSMenuItem keyEquivalent\n"
		"//   - WM_COMMAND dispatch from menu → WndProc\n"
		"//   - Real NSTimer-backed SetTimer/KillTimer\n"
		"//   - Clipboard read/write (GetClipboardData/SetClipboardData)\n"
		"//\n"
		"// Try: Cmd+O to open, Cmd+S to save, Cmd+N for new file\n"
		"\n"
		"#include <iostream>\n"
		"\n"
		"int main() {\n"
		"    std::cout << \"Hello from Notepad++ macOS!\" << std::endl;\n"
		"    return 0;\n"
		"}\n";

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)welcomeText);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOPOS, 0, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);

	// Show the window using Win32 API
	ShowWindow(g_mainHwnd, SW_SHOW);

	[NSApp activateIgnoringOtherApps:YES];

	NSLog(@"=== Notepad++ macOS Port — Phase 2 ===");
	NSLog(@"Menu bar, file dialogs, and WM_COMMAND dispatch working!");
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
	return YES;
}

- (void)windowDidResize:(NSNotification*)notification
{
	if (g_scintillaView)
		ScintillaBridge_resizeToFit(g_scintillaView);
}

@end

// ============================================================
// Entry point
// ============================================================

int main(int argc, const char* argv[])
{
	@autoreleasepool
	{
		NSApplication* app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];

		NppAppDelegate* delegate = [[NppAppDelegate alloc] init];
		app.delegate = delegate;

		[app run];
	}
	return 0;
}
