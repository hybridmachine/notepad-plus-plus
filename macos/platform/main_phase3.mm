// Notepad++ macOS Port — Phase 3 Entry Point
// Demonstrates: Tab control (TCM_* → NSSegmentedControl), status bar
// (SB_* → custom NSView), multi-document tabbed editing, WM_NOTIFY
// dispatch, and basic layout management.

#import <Cocoa/Cocoa.h>
#include <vector>
#include <string>
#include "windows.h"
#include "commctrl.h"
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
#define IDM_FILE_CLOSEALL     41004
#define IDM_EDIT_UNDO         42001
#define IDM_EDIT_REDO         42002
#define IDM_EDIT_CUT          42003
#define IDM_EDIT_COPY         42004
#define IDM_EDIT_PASTE        42005
#define IDM_EDIT_SELECTALL    42013
#define IDM_VIEW_WORDWRAP     42026
#define IDM_VIEW_LINENUMBER   42027
#define IDM_VIEW_STATUSBAR    42028

// Control IDs
#define IDC_TAB         100
#define IDC_STATUSBAR   101

// Status bar partitions
#define STATUSBAR_DOC_TYPE    0
#define STATUSBAR_DOC_SIZE    1
#define STATUSBAR_CUR_POS     2
#define STATUSBAR_EOF_FORMAT  3
#define STATUSBAR_ENCODING    4

// ============================================================
// Document data structure
// ============================================================
struct DocumentData
{
	std::wstring filePath;
	std::wstring title;
	std::string content;     // UTF-8 content stored when tab is inactive
	bool modified = false;
	intptr_t scrollPos = 0;  // Save/restore scroll position
	intptr_t cursorPos = 0;  // Save/restore cursor position
};

// ============================================================
// Globals
// ============================================================
static void* g_scintillaView = nullptr;
static NSWindow* g_mainWindow = nil;
static HWND g_mainHwnd = nullptr;
static HWND g_tabHwnd = nullptr;
static HWND g_statusBarHwnd = nullptr;
static std::vector<DocumentData> g_documents;
static int g_activeDoc = -1;
static int g_nextUntitledId = 1;

// SCI message IDs
enum {
	SCI_CLEARALL = 2004,
	SCI_SETSAVEPOINT = 2014,
	SCI_GETFIRSTVISIBLELINE = 2152,
	SCI_GOTOPOS = 2025,
	SCI_GETCURRENTPOS = 2008,
	SCI_GETANCHOR = 2009,
	SCI_SETSEL = 2160,
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
	SCI_GETLINE = 2153,
	SCI_GETLINECOUNT = 2154,
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
	SCI_LINEFROMPOSITION = 2166,
	SCI_GETCOLUMN = 2129,
	SCI_SETFIRSTVISIBLELINE = 2613,
	SCI_GETLENGTH = 2006,
};

// ============================================================
// Helper: Get text from Scintilla
// ============================================================
static std::string getScintillaText()
{
	if (!g_scintillaView)
		return "";
	intptr_t len = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXTLENGTH, 0, 0);
	if (len <= 0)
		return "";
	std::string buf(len + 1, '\0');
	ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, len + 1, (intptr_t)buf.data());
	buf.resize(len);
	return buf;
}

// ============================================================
// Save/Restore active document state
// ============================================================
static void saveActiveDocState()
{
	if (g_activeDoc < 0 || g_activeDoc >= static_cast<int>(g_documents.size()))
		return;
	if (!g_scintillaView)
		return;

	auto& doc = g_documents[g_activeDoc];
	doc.content = getScintillaText();
	doc.modified = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETMODIFY, 0, 0) != 0;
	doc.cursorPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	doc.scrollPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETFIRSTVISIBLELINE, 0, 0);
}

static void loadDocState(int index)
{
	if (index < 0 || index >= static_cast<int>(g_documents.size()))
		return;
	if (!g_scintillaView)
		return;

	auto& doc = g_documents[index];
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)doc.content.c_str());
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETFIRSTVISIBLELINE, doc.scrollPos, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOPOS, doc.cursorPos, 0);
	if (!doc.modified)
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
}

// ============================================================
// Status bar update
// ============================================================
static void updateStatusBar()
{
	if (!g_statusBarHwnd || !g_scintillaView)
		return;

	// Current position
	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t line = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, pos, 0);
	intptr_t col = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCOLUMN, pos, 0);

	wchar_t posText[64];
	swprintf(posText, 64, L"Ln : %ld    Col : %ld", (long)(line + 1), (long)(col + 1));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_CUR_POS, (LPARAM)posText);

	// Document size
	intptr_t length = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);
	intptr_t lines = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLINECOUNT, 0, 0);
	wchar_t sizeText[64];
	swprintf(sizeText, 64, L"length : %ld    lines : %ld", (long)length, (long)lines);
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_DOC_SIZE, (LPARAM)sizeText);

	// Document type
	if (g_activeDoc >= 0 && g_activeDoc < static_cast<int>(g_documents.size()))
	{
		auto& doc = g_documents[g_activeDoc];
		const wchar_t* type = L"Normal text file";
		if (!doc.filePath.empty())
		{
			std::wstring ext;
			auto dotPos = doc.filePath.rfind(L'.');
			if (dotPos != std::wstring::npos)
				ext = doc.filePath.substr(dotPos);
			if (ext == L".cpp" || ext == L".cc" || ext == L".cxx")
				type = L"C++ source file";
			else if (ext == L".h" || ext == L".hpp")
				type = L"C/C++ header file";
			else if (ext == L".c")
				type = L"C source file";
			else if (ext == L".py")
				type = L"Python file";
			else if (ext == L".js")
				type = L"JavaScript file";
			else if (ext == L".mm" || ext == L".m")
				type = L"Objective-C file";
		}
		SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_DOC_TYPE, (LPARAM)type);
	}

	// Encoding and EOL
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_ENCODING, (LPARAM)L"UTF-8");
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_EOF_FORMAT, (LPARAM)L"Unix (LF)");
}

// ============================================================
// Tab management
// ============================================================
static int addNewTab(const std::wstring& title, const std::wstring& filePath = L"")
{
	DocumentData doc;
	doc.title = title;
	doc.filePath = filePath;
	g_documents.push_back(doc);

	int index = static_cast<int>(g_documents.size()) - 1;

	TCITEMW item = {};
	item.mask = TCIF_TEXT | TCIF_PARAM;
	wchar_t titleBuf[256];
	wcsncpy(titleBuf, title.c_str(), 255);
	titleBuf[255] = L'\0';
	item.pszText = titleBuf;
	item.lParam = index;
	SendMessageW(g_tabHwnd, TCM_INSERTITEMW, index, (LPARAM)&item);

	return index;
}

static void switchToTab(int index)
{
	if (index < 0 || index >= static_cast<int>(g_documents.size()))
		return;
	if (index == g_activeDoc)
		return;

	// Save current doc state
	saveActiveDocState();

	// Switch
	g_activeDoc = index;
	SendMessageW(g_tabHwnd, TCM_SETCURSEL, index, 0);

	// Load new doc state
	loadDocState(index);

	// Update window title
	auto& doc = g_documents[index];
	NSString* title = [NSString stringWithFormat:@"Notepad++ (macOS) — %@",
	                   [[NSString alloc] initWithBytes:doc.title.c_str()
	                                           length:doc.title.size() * sizeof(wchar_t)
	                                         encoding:NSUTF32LittleEndianStringEncoding]];
	[g_mainWindow setTitle:title];

	updateStatusBar();
}

static void closeTab(int index)
{
	if (index < 0 || index >= static_cast<int>(g_documents.size()))
		return;

	// Don't close the last tab — create a new untitled instead
	if (g_documents.size() == 1)
	{
		g_documents[0].content.clear();
		g_documents[0].filePath.clear();
		g_documents[0].title = L"new 1";
		g_documents[0].modified = false;
		g_nextUntitledId = 2;

		// Update tab text
		TCITEMW item = {};
		item.mask = TCIF_TEXT;
		wchar_t titleBuf[64] = L"new 1";
		item.pszText = titleBuf;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, 0, (LPARAM)&item);

		if (g_scintillaView)
		{
			ScintillaBridge_sendMessage(g_scintillaView, SCI_CLEARALL, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
		}
		[g_mainWindow setTitle:@"Notepad++ (macOS) — new 1"];
		g_activeDoc = 0;
		updateStatusBar();
		return;
	}

	// Remove document and tab
	g_documents.erase(g_documents.begin() + index);
	SendMessageW(g_tabHwnd, TCM_DELETEITEM, index, 0);

	// Adjust active doc index
	if (g_activeDoc >= static_cast<int>(g_documents.size()))
		g_activeDoc = static_cast<int>(g_documents.size()) - 1;
	else if (g_activeDoc > index)
		--g_activeDoc;
	else if (g_activeDoc == index)
	{
		if (g_activeDoc >= static_cast<int>(g_documents.size()))
			g_activeDoc = static_cast<int>(g_documents.size()) - 1;
		// Force reload since active doc changed
		g_activeDoc = -1; // reset so switchToTab will work
	}

	int newActive = (g_activeDoc >= 0) ? g_activeDoc : 0;
	g_activeDoc = -1;
	switchToTab(newActive);
}

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
	ofn.lpstrFilter = L"All Files\0*.*\0"
	                   L"C/C++ Files\0*.c;*.cpp;*.cc;*.h;*.hpp;*.mm\0"
	                   L"Text Files\0*.txt\0";
	ofn.nFilterIndex = 1;
	ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;

	if (!GetOpenFileNameW(&ofn))
		return;

	// Check if file is already open
	for (int i = 0; i < static_cast<int>(g_documents.size()); ++i)
	{
		if (g_documents[i].filePath == filePath)
		{
			switchToTab(i);
			return;
		}
	}

	// Read file
	NSString* path = [[NSString alloc] initWithBytes:filePath
	                                          length:wcslen(filePath) * sizeof(wchar_t)
	                                        encoding:NSUTF32LittleEndianStringEncoding];
	NSError* error = nil;
	NSString* content = [NSString stringWithContentsOfFile:path
	                                             encoding:NSUTF8StringEncoding
	                                                error:&error];
	if (!content)
	{
		if (error)
			NSLog(@"Error opening file: %@", error);
		return;
	}

	// Extract filename for tab title
	NSString* filename = [path lastPathComponent];
	NSData* filenameData = [filename dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
	std::wstring wFilename;
	if (filenameData)
		wFilename.assign(reinterpret_cast<const wchar_t*>(filenameData.bytes),
		                 filenameData.length / sizeof(wchar_t));

	// Add tab
	int index = addNewTab(wFilename, filePath);

	// Store content
	g_documents[index].content = [content UTF8String];

	// Switch to new tab
	switchToTab(index);
}

static void saveFile()
{
	if (g_activeDoc < 0 || g_activeDoc >= static_cast<int>(g_documents.size()))
		return;

	auto& doc = g_documents[g_activeDoc];
	saveActiveDocState();

	if (doc.filePath.empty())
	{
		// Save As
		OPENFILENAMEW ofn = {};
		wchar_t filePath[MAX_PATH] = {0};

		ofn.lStructSize = sizeof(ofn);
		ofn.hwndOwner = g_mainHwnd;
		ofn.lpstrFile = filePath;
		ofn.nMaxFile = MAX_PATH;
		ofn.lpstrTitle = L"Save File As";
		ofn.lpstrFilter = L"All Files\0*.*\0";
		ofn.nFilterIndex = 1;
		ofn.Flags = OFN_OVERWRITEPROMPT;

		if (!GetSaveFileNameW(&ofn))
			return;

		doc.filePath = filePath;

		// Extract filename for tab title
		NSString* path = [[NSString alloc] initWithBytes:filePath
		                                          length:wcslen(filePath) * sizeof(wchar_t)
		                                        encoding:NSUTF32LittleEndianStringEncoding];
		NSData* filenameData = [[path lastPathComponent] dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
		if (filenameData)
			doc.title.assign(reinterpret_cast<const wchar_t*>(filenameData.bytes),
			                 filenameData.length / sizeof(wchar_t));

		// Update tab text
		TCITEMW item = {};
		item.mask = TCIF_TEXT;
		wchar_t titleBuf[256];
		wcsncpy(titleBuf, doc.title.c_str(), 255);
		titleBuf[255] = L'\0';
		item.pszText = titleBuf;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, g_activeDoc, (LPARAM)&item);
	}

	// Write file
	NSString* path = [[NSString alloc] initWithBytes:doc.filePath.c_str()
	                                          length:doc.filePath.size() * sizeof(wchar_t)
	                                        encoding:NSUTF32LittleEndianStringEncoding];
	NSString* content = [NSString stringWithUTF8String:doc.content.c_str()];
	NSError* error = nil;
	[content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

	if (error)
	{
		NSLog(@"Error saving file: %@", error);
		return;
	}

	doc.modified = false;
	if (g_scintillaView)
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);

	// Update window title
	NSString* title = [NSString stringWithFormat:@"Notepad++ (macOS) — %@",
	                   [[NSString alloc] initWithBytes:doc.title.c_str()
	                                           length:doc.title.size() * sizeof(wchar_t)
	                                         encoding:NSUTF32LittleEndianStringEncoding]];
	[g_mainWindow setTitle:title];
}

// ============================================================
// WndProc — dispatches WM_COMMAND and WM_NOTIFY
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
				{
					wchar_t title[64];
					swprintf(title, 64, L"new %d", g_nextUntitledId++);
					int index = addNewTab(title);
					switchToTab(index);
					return 0;
				}

				case IDM_FILE_OPEN:
					openFile();
					return 0;

				case IDM_FILE_SAVE:
					saveFile();
					return 0;

				case IDM_FILE_CLOSE:
					closeTab(g_activeDoc);
					return 0;

				case IDM_FILE_CLOSEALL:
				{
					while (g_documents.size() > 1)
						closeTab(static_cast<int>(g_documents.size()) - 1);
					closeTab(0);
					return 0;
				}

				case IDM_VIEW_WORDWRAP:
					if (g_scintillaView)
					{
						intptr_t mode = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETWRAPMODE, 0, 0);
						ScintillaBridge_sendMessage(g_scintillaView, SCI_SETWRAPMODE, mode == 0 ? 1 : 0, 0);
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

				case IDM_VIEW_STATUSBAR:
					if (g_statusBarHwnd)
					{
						BOOL visible = IsWindowVisible(g_statusBarHwnd);
						ShowWindow(g_statusBarHwnd, visible ? SW_HIDE : SW_SHOW);
						HMENU hMenu = GetMenu(hWnd);
						if (hMenu)
							CheckMenuItem(hMenu, IDM_VIEW_STATUSBAR,
							              MF_BYCOMMAND | (visible ? MF_UNCHECKED : MF_CHECKED));
					}
					return 0;
			}
			break;
		}

		case WM_NOTIFY:
		{
			NMHDR* pnmhdr = reinterpret_cast<NMHDR*>(lParam);
			if (!pnmhdr)
				break;

			// Tab control notifications
			if (pnmhdr->hwndFrom == g_tabHwnd)
			{
				int code = static_cast<int>(pnmhdr->code);
				if (code == TCN_SELCHANGE)
				{
					int newSel = static_cast<int>(SendMessageW(g_tabHwnd, TCM_GETCURSEL, 0, 0));
					switchToTab(newSel);
					return 0;
				}
				else if (code == TCN_SELCHANGING)
				{
					// Save current doc before switching
					saveActiveDocState();
					return FALSE; // Allow the change
				}
			}
			break;
		}

		case WM_SIZE:
		{
			// Relayout: tab bar (top), editor container (middle), status bar (bottom)
			// All coordinates are Cocoa (origin at bottom-left).
			RECT rc;
			GetClientRect(hWnd, &rc);
			int width = rc.right - rc.left;
			int height = rc.bottom - rc.top;

			int tabHeight = 28;
			int statusHeight = IsWindowVisible(g_statusBarHwnd) ? 22 : 0;
			int editorHeight = height - tabHeight - statusHeight;
			if (editorHeight < 0) editorHeight = 0;

			// Status bar at bottom (Cocoa y=0)
			if (g_statusBarHwnd)
			{
				auto* sbInfo2 = HandleRegistry::getWindowInfo(g_statusBarHwnd);
				if (sbInfo2 && sbInfo2->nativeView)
				{
					NSView* sbView = (__bridge NSView*)sbInfo2->nativeView;
					[sbView setFrame:NSMakeRect(0, 0, width, statusHeight)];
					[sbView setNeedsDisplay:YES];
				}
				int parts[] = {width / 5, 2 * width / 5, 3 * width / 5, 4 * width / 5, -1};
				SendMessageW(g_statusBarHwnd, SB_SETPARTS, 5, (LPARAM)parts);
			}

			// Scintilla editor in the middle
			if (g_scintillaView)
			{
				NSView* sciView = (__bridge NSView*)g_scintillaView;
				[sciView setFrame:NSMakeRect(0, statusHeight, width, editorHeight)];
			}

			// Tab bar at top (Cocoa y = statusHeight + editorHeight)
			if (g_tabHwnd)
			{
				auto* tabInfo2 = HandleRegistry::getWindowInfo(g_tabHwnd);
				if (tabInfo2 && tabInfo2->nativeView)
				{
					NSView* tabView = (__bridge NSView*)tabInfo2->nativeView;
					NSRect tabFrame = NSMakeRect(0, statusHeight + editorHeight, width, tabHeight);
					[tabView setFrame:tabFrame];
					[tabView setNeedsDisplay:YES];
					NSView* sciDbg = (__bridge NSView*)g_scintillaView;
					NSLog(@"LAYOUT: contentView=%@, tabFrame=%@, sciFrame=%@, statusFrame=%@, tabView.hidden=%d, tabView.superview=%@",
						NSStringFromRect(g_mainWindow.contentView.bounds),
						NSStringFromRect(tabFrame),
						sciDbg ? NSStringFromRect(sciDbg.frame) : @"nil",
						NSStringFromRect(NSMakeRect(0, 0, width, statusHeight)),
						tabView.isHidden,
						tabView.superview);
				}
			}

			updateStatusBar();
			return 0;
		}

		case WM_CLOSE:
			PostQuitMessage(0);
			return 0;

		case WM_TIMER:
			// Periodically update status bar (cursor position, etc.)
			updateStatusBar();
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
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSE, L"&Close\tCtrl+W");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSEALL, L"Close All");
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
	AppendMenuW(hViewMenu, MF_STRING | MF_CHECKED, IDM_VIEW_STATUSBAR, L"&Status Bar");
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
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 1, 0x008000);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 2, 0x008000);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 4, 0xFF8000);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 5, 0x0000FF);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 6, 0x800080);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 9, 0x808080);
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
@interface NppPhase3Delegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation NppPhase3Delegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
	// Register window class
	WNDCLASSEXW wc = {};
	wc.cbSize = sizeof(wc);
	wc.lpfnWndProc = MainWndProc;
	wc.lpszClassName = L"Notepad++";
	wc.hInstance = nullptr;
	RegisterClassExW(&wc);

	// Build menu bar
	HMENU hMenuBar = buildMenuBar();

	// Create main window
	g_mainHwnd = CreateWindowExW(
		0, L"Notepad++", L"Notepad++ (macOS) — Phase 3",
		WS_OVERLAPPEDWINDOW,
		CW_USEDEFAULT, CW_USEDEFAULT, 1000, 750,
		nullptr, hMenuBar, nullptr, nullptr
	);

	if (!g_mainHwnd)
	{
		NSLog(@"ERROR: Failed to create main window!");
		return;
	}

	auto* info = HandleRegistry::getWindowInfo(g_mainHwnd);
	if (info && info->nativeWindow)
	{
		g_mainWindow = (__bridge NSWindow*)info->nativeWindow;
		g_mainWindow.delegate = self;
		[g_mainWindow setMinSize:NSMakeSize(500, 400)];
	}

	SetMenu(g_mainHwnd, hMenuBar);

	NSView* contentView = g_mainWindow.contentView;

	// All views go directly in contentView — no container, no layers.
	// Create Scintilla first (bottom of z-order).
	g_scintillaView = ScintillaBridge_createView((__bridge void*)contentView, 0, 0, 0, 0);
	if (!g_scintillaView)
	{
		NSLog(@"ERROR: Failed to create ScintillaView!");
		return;
	}

	NSView* sciView = (__bridge NSView*)g_scintillaView;
	sciView.autoresizingMask = 0;

	// Create tab and status bar — shim adds them to contentView.
	// Since they're created after Scintilla, they're above it in z-order.
	g_tabHwnd = CreateWindowExW(
		0, WC_TABCONTROLW, L"",
		WS_CHILD | WS_VISIBLE | TCS_TOOLTIPS,
		0, 0, 1000, 28,
		g_mainHwnd, (HMENU)(intptr_t)IDC_TAB, nullptr, nullptr
	);

	g_statusBarHwnd = CreateWindowExW(
		0, STATUSCLASSNAMEW, L"",
		WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
		0, 0, 0, 0,
		g_mainHwnd, (HMENU)(intptr_t)IDC_STATUSBAR, nullptr, nullptr
	);

	// Disable autoresizing — WM_SIZE positions everything manually.
	auto* tabInfo = HandleRegistry::getWindowInfo(g_tabHwnd);
	if (tabInfo && tabInfo->nativeView)
		((__bridge NSView*)tabInfo->nativeView).autoresizingMask = 0;
	auto* sbInfo = HandleRegistry::getWindowInfo(g_statusBarHwnd);
	if (sbInfo && sbInfo->nativeView)
		((__bridge NSView*)sbInfo->nativeView).autoresizingMask = 0;

	// Set up status bar partitions
	int parts[] = {200, 400, 600, 800, -1};
	SendMessageW(g_statusBarHwnd, SB_SETPARTS, 5, (LPARAM)parts);
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_DOC_TYPE, (LPARAM)L"Normal text file");
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_ENCODING, (LPARAM)L"UTF-8");
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, STATUSBAR_EOF_FORMAT, (LPARAM)L"Unix (LF)");

	configureScintilla(g_scintillaView);

	// Add initial tab
	addNewTab(L"new 1");
	g_activeDoc = 0;
	g_nextUntitledId = 2;

	// Set welcome text
	const char* welcomeText =
		"// Welcome to Notepad++ on macOS — Phase 3!\n"
		"//\n"
		"// What's new in Phase 3:\n"
		"//   - Tabbed editing: Cmd+N for new tab, Cmd+W to close\n"
		"//   - Multi-document: each tab has its own text buffer\n"
		"//   - Status bar: line/column, document size, encoding\n"
		"//   - Tab control backed by Win32 TCM_* messages\n"
		"//   - Status bar backed by Win32 SB_* messages\n"
		"//   - WM_NOTIFY dispatch for TCN_SELCHANGE\n"
		"//   - File monitoring via FSEvents (macOS native)\n"
		"//\n"
		"// Try: Cmd+N (new tab), Cmd+O (open), click tabs to switch\n"
		"\n"
		"#include <iostream>\n"
		"\n"
		"int main() {\n"
		"    std::cout << \"Hello from Notepad++ macOS Phase 3!\" << std::endl;\n"
		"    return 0;\n"
		"}\n";

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)welcomeText);
	g_documents[0].content = welcomeText;
	ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOPOS, 0, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);

	// Show the window
	ShowWindow(g_mainHwnd, SW_SHOW);
	[NSApp activateIgnoringOtherApps:YES];

	// Set up a timer to periodically update the status bar
	SetTimer(g_mainHwnd, 1, 500, nullptr);

	// Trigger initial layout and status bar update
	RECT rc;
	GetClientRect(g_mainHwnd, &rc);
	MainWndProc(g_mainHwnd, WM_SIZE, 0, MAKELPARAM(rc.right, rc.bottom));
	updateStatusBar();

	NSLog(@"=== Notepad++ macOS Port — Phase 3 ===");
	NSLog(@"Tabbed editing, status bar, and WM_NOTIFY dispatch working!");
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
	return YES;
}

- (void)windowDidResize:(NSNotification*)notification
{
	if (!g_mainHwnd)
		return;

	RECT rc;
	GetClientRect(g_mainHwnd, &rc);
	MainWndProc(g_mainHwnd, WM_SIZE, 0, MAKELPARAM(rc.right, rc.bottom));
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

		NppPhase3Delegate* delegate = [[NppPhase3Delegate alloc] init];
		app.delegate = delegate;

		[app run];
	}
	return 0;
}
