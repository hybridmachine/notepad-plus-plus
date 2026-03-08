// Notepad++ macOS Port — Phase 3 Entry Point
// Demonstrates: Tabbed multi-document editing with tab control (SysTabControl32),
// status bar (msctls_statusbar32), WM_NOTIFY/TCN_SELCHANGE dispatch,
// file monitoring (FSEvents), and periodic timer updates.
//
// Builds on Phase 2: menus, file dialogs, WM_COMMAND, timers, clipboard.

#import <Cocoa/Cocoa.h>
#include "windows.h"
#include "commctrl.h"
#include "commdlg.h"
#include "handle_registry.h"
#include "scintilla_bridge.h"
#include "file_monitor_mac.h"

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

// Control IDs
#define IDC_TABBAR       1001
#define IDC_STATUSBAR    1002

// Timer ID
#define IDT_STATUSBAR    5001

// ============================================================
// SCI message IDs
// ============================================================
enum {
	SCI_CLEARALL = 2004,
	SCI_SETSAVEPOINT = 2014,
	SCI_GETLENGTH = 2006,
	SCI_GOTOPOS = 2025,
	SCI_GETCURRENTPOS = 2008,
	SCI_LINEFROMPOSITION = 2166,
	SCI_GETCOLUMN = 2129,
	SCI_GETLINECOUNT = 2154,
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
	SCI_SETFIRSTVISIBLELINE = 2613,
	SCI_GETFIRSTVISIBLELINE = 2152,
	SCI_SETSEL = 2160,
	SCI_GETANCHOR = 2009,
};

// ============================================================
// Document data — per-tab state
// ============================================================

struct DocumentData
{
	std::wstring filePath;
	std::wstring title = L"Untitled";
	std::string content;         // UTF-8 text
	intptr_t cursorPos = 0;
	intptr_t anchorPos = 0;
	intptr_t firstVisibleLine = 0;
	bool modified = false;
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
static int g_activeTab = -1;
static FileMonitorMac* g_fileMonitor = nullptr;

// ============================================================
// Helper: Save Scintilla state to current document
// ============================================================
static void saveScintillaState()
{
	if (g_activeTab < 0 || g_activeTab >= static_cast<int>(g_documents.size()))
		return;
	if (!g_scintillaView) return;

	auto& doc = g_documents[g_activeTab];

	// Save text content
	intptr_t len = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXTLENGTH, 0, 0);
	if (len >= 0)
	{
		doc.content.resize(len + 1);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, len + 1,
		                            (intptr_t)doc.content.data());
		doc.content.resize(len); // remove null terminator from string
	}

	// Save cursor/scroll position
	doc.cursorPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	doc.anchorPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETANCHOR, 0, 0);
	doc.firstVisibleLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETFIRSTVISIBLELINE, 0, 0);
	doc.modified = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETMODIFY, 0, 0) != 0;
}

// ============================================================
// Helper: Restore Scintilla state from a document
// ============================================================
static void restoreScintillaState(int tabIndex)
{
	if (tabIndex < 0 || tabIndex >= static_cast<int>(g_documents.size()))
		return;
	if (!g_scintillaView) return;

	const auto& doc = g_documents[tabIndex];

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0,
	                            (intptr_t)doc.content.c_str());
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETFIRSTVISIBLELINE,
	                            doc.firstVisibleLine, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEL,
	                            doc.anchorPos, doc.cursorPos);

	if (!doc.modified)
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);

	ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
}

// ============================================================
// Helper: Switch to a tab
// ============================================================
static void switchToTab(int tabIndex)
{
	if (tabIndex < 0 || tabIndex >= static_cast<int>(g_documents.size()))
		return;
	if (tabIndex == g_activeTab)
		return;

	// Save current tab state
	saveScintillaState();

	// Switch
	g_activeTab = tabIndex;
	SendMessageW(g_tabHwnd, TCM_SETCURSEL, tabIndex, 0);

	// Restore new tab state
	restoreScintillaState(tabIndex);

	// Update title
	const auto& doc = g_documents[tabIndex];
	NSString* title = [[NSString alloc] initWithBytes:doc.title.data()
	                                           length:doc.title.size() * sizeof(wchar_t)
	                                         encoding:NSUTF32LittleEndianStringEncoding];
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", title]];
}

// ============================================================
// Helper: Add a new tab
// ============================================================
static int addNewTab(const std::wstring& title, const std::string& content,
                      const std::wstring& filePath = L"")
{
	// Save current state
	saveScintillaState();

	DocumentData doc;
	doc.title = title;
	doc.content = content;
	doc.filePath = filePath;
	g_documents.push_back(doc);

	int newIndex = static_cast<int>(g_documents.size()) - 1;

	// Insert tab item
	TCITEMW tcItem = {};
	tcItem.mask = TCIF_TEXT;
	wchar_t titleBuf[256];
	wcsncpy(titleBuf, title.c_str(), 255);
	titleBuf[255] = L'\0';
	tcItem.pszText = titleBuf;
	SendMessageW(g_tabHwnd, TCM_INSERTITEMW, newIndex, reinterpret_cast<LPARAM>(&tcItem));

	// Switch to the new tab
	g_activeTab = newIndex;
	SendMessageW(g_tabHwnd, TCM_SETCURSEL, newIndex, 0);

	// Load content into Scintilla
	if (g_scintillaView)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)content.c_str());
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOPOS, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
	}

	// Update window title
	NSString* nsTitle = [[NSString alloc] initWithBytes:title.data()
	                                            length:title.size() * sizeof(wchar_t)
	                                          encoding:NSUTF32LittleEndianStringEncoding];
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", nsTitle]];

	return newIndex;
}

// ============================================================
// Helper: Close a tab
// ============================================================
static void closeTab(int tabIndex)
{
	if (tabIndex < 0 || tabIndex >= static_cast<int>(g_documents.size()))
		return;

	// Don't close the last tab
	if (g_documents.size() <= 1)
	{
		// Instead, clear it
		g_documents[0] = DocumentData();
		if (g_scintillaView)
		{
			ScintillaBridge_sendMessage(g_scintillaView, SCI_CLEARALL, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
		}

		// Update tab text
		TCITEMW tcItem = {};
		tcItem.mask = TCIF_TEXT;
		wchar_t title[] = L"Untitled";
		tcItem.pszText = title;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, 0, reinterpret_cast<LPARAM>(&tcItem));
		[g_mainWindow setTitle:@"Notepad++ — Untitled"];
		return;
	}

	// Remove the tab
	SendMessageW(g_tabHwnd, TCM_DELETEITEM, tabIndex, 0);
	g_documents.erase(g_documents.begin() + tabIndex);

	// Adjust active tab
	if (g_activeTab >= static_cast<int>(g_documents.size()))
		g_activeTab = static_cast<int>(g_documents.size()) - 1;
	if (g_activeTab == tabIndex && g_activeTab > 0)
		--g_activeTab;

	SendMessageW(g_tabHwnd, TCM_SETCURSEL, g_activeTab, 0);
	restoreScintillaState(g_activeTab);

	const auto& doc = g_documents[g_activeTab];
	NSString* title = [[NSString alloc] initWithBytes:doc.title.data()
	                                           length:doc.title.size() * sizeof(wchar_t)
	                                         encoding:NSUTF32LittleEndianStringEncoding];
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", title]];
}

// ============================================================
// Update status bar with current editor state
// ============================================================
static void updateStatusBar()
{
	if (!g_scintillaView || !g_statusBarHwnd) return;

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t line = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, pos, 0);
	intptr_t col = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCOLUMN, pos, 0);
	intptr_t lineCount = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLINECOUNT, 0, 0);
	intptr_t docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);

	// Part 0: Line/Col
	wchar_t buf[128];
	swprintf(buf, 128, L"Ln %ld, Col %ld", (long)(line + 1), (long)(col + 1));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 0, reinterpret_cast<LPARAM>(buf));

	// Part 1: Document info
	swprintf(buf, 128, L"%ld lines, %ld bytes", (long)lineCount, (long)docLen);
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 1, reinterpret_cast<LPARAM>(buf));

	// Part 2: Encoding
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 2, reinterpret_cast<LPARAM>(L"UTF-8"));

	// Part 3: Tab/doc count
	swprintf(buf, 128, L"Doc %d/%d", g_activeTab + 1, (int)g_documents.size());
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 3, reinterpret_cast<LPARAM>(buf));
}

// ============================================================
// File operations
// ============================================================

static NSString* WideToNSString(const wchar_t* wstr)
{
	if (!wstr) return @"";
	size_t len = wcslen(wstr);
	NSString* str = [[NSString alloc] initWithBytes:wstr
	                                         length:len * sizeof(wchar_t)
	                                       encoding:NSUTF32LittleEndianStringEncoding];
	return str ?: @"";
}

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
	                   L"C/C++ Files\0*.c;*.cpp;*.cc;*.h;*.hpp\0"
	                   L"Text Files\0*.txt\0";
	ofn.nFilterIndex = 1;
	ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;

	if (GetOpenFileNameW(&ofn))
	{
		NSString* path = WideToNSString(filePath);
		NSError* error = nil;
		NSString* content = [NSString stringWithContentsOfFile:path
		                                             encoding:NSUTF8StringEncoding
		                                                error:&error];
		if (content)
		{
			std::wstring wpath(filePath);
			std::wstring title = wpath;
			// Extract filename from path
			size_t lastSlash = title.rfind(L'/');
			if (lastSlash != std::wstring::npos)
				title = title.substr(lastSlash + 1);

			addNewTab(title, std::string([content UTF8String]), wpath);

			// Start monitoring the file's directory
			if (g_fileMonitor)
			{
				std::wstring dir = wpath.substr(0, wpath.rfind(L'/'));
				g_fileMonitor->addDirectory(dir);
			}
		}
		else if (error)
		{
			NSLog(@"Error opening file: %@", error);
		}
	}
}

static void saveCurrentFile()
{
	if (g_activeTab < 0 || g_activeTab >= static_cast<int>(g_documents.size()))
		return;

	auto& doc = g_documents[g_activeTab];

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
		doc.title = doc.filePath;
		size_t lastSlash = doc.title.rfind(L'/');
		if (lastSlash != std::wstring::npos)
			doc.title = doc.title.substr(lastSlash + 1);

		// Update tab text
		TCITEMW tcItem = {};
		tcItem.mask = TCIF_TEXT;
		wchar_t titleBuf[256];
		wcsncpy(titleBuf, doc.title.c_str(), 255);
		titleBuf[255] = L'\0';
		tcItem.pszText = titleBuf;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, g_activeTab, reinterpret_cast<LPARAM>(&tcItem));
	}

	// Get text from Scintilla
	if (!g_scintillaView) return;

	intptr_t len = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXTLENGTH, 0, 0);
	if (len >= 0)
	{
		char* buf = new char[len + 1];
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, len + 1, (intptr_t)buf);

		NSString* path = WideToNSString(doc.filePath.c_str());
		NSString* content = [NSString stringWithUTF8String:buf];
		NSError* error = nil;
		[content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

		if (error)
			NSLog(@"Error saving file: %@", error);
		else
		{
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
			NSString* nsTitle = WideToNSString(doc.title.c_str());
			[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", nsTitle]];
		}

		delete[] buf;
	}
}

// ============================================================
// WndProc
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
					addNewTab(L"Untitled", "");
					return 0;

				case IDM_FILE_OPEN:
					openFile();
					return 0;

				case IDM_FILE_SAVE:
					saveCurrentFile();
					return 0;

				case IDM_FILE_CLOSE:
					closeTab(g_activeTab);
					return 0;

				case IDM_FILE_CLOSEALL:
					while (g_documents.size() > 1)
						closeTab(static_cast<int>(g_documents.size()) - 1);
					closeTab(0); // clears the last tab
					return 0;

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
			}
			break;
		}

		case WM_NOTIFY:
		{
			NMHDR* pNmhdr = reinterpret_cast<NMHDR*>(lParam);
			if (pNmhdr && pNmhdr->code == TCN_SELCHANGE)
			{
				// Tab selection changed
				int newSel = static_cast<int>(SendMessageW(g_tabHwnd, TCM_GETCURSEL, 0, 0));
				if (newSel != g_activeTab && newSel >= 0)
					switchToTab(newSel);
				return 0;
			}
			break;
		}

		case WM_TIMER:
		{
			if (wParam == IDT_STATUSBAR)
			{
				updateStatusBar();
				return 0;
			}
			break;
		}

		case WM_SIZE:
		{
			// Re-layout: tab bar at top, status bar at bottom, Scintilla fills middle
			if (g_scintillaView)
				ScintillaBridge_resizeToFit(g_scintillaView);
			return 0;
		}

		case WM_CLOSE:
			KillTimer(hWnd, IDT_STATUSBAR);
			PostQuitMessage(0);
			return 0;
	}

	return DefWindowProcW(hWnd, msg, wParam, lParam);
}

// ============================================================
// Build menus
// ============================================================

static HMENU buildMenuBar()
{
	HMENU hMenuBar = CreateMenu();

	HMENU hFileMenu = CreatePopupMenu();
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_NEW, L"&New\tCtrl+N");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_OPEN, L"&Open...\tCtrl+O");
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_SAVE, L"&Save\tCtrl+S");
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSE, L"&Close\tCtrl+W");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSEALL, L"Close &All");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hFileMenu), L"&File");

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

	HMENU hViewMenu = CreatePopupMenu();
	AppendMenuW(hViewMenu, MF_STRING, IDM_VIEW_WORDWRAP, L"&Word Wrap");
	AppendMenuW(hViewMenu, MF_STRING | MF_CHECKED, IDM_VIEW_LINENUMBER, L"&Line Numbers");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hViewMenu), L"&View");

	return hMenuBar;
}

// ============================================================
// Configure Scintilla
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
	wc.lpszClassName = L"Notepad++Phase3";
	RegisterClassExW(&wc);

	// Build menu bar
	HMENU hMenuBar = buildMenuBar();

	// Create main window
	g_mainHwnd = CreateWindowExW(
		0, L"Notepad++Phase3", L"Notepad++ (macOS) — Phase 3",
		WS_OVERLAPPEDWINDOW,
		CW_USEDEFAULT, CW_USEDEFAULT, 1000, 750,
		nullptr, hMenuBar, nullptr, nullptr
	);

	if (!g_mainHwnd)
	{
		NSLog(@"ERROR: Failed to create main window!");
		return;
	}

	auto* mainInfo = HandleRegistry::getWindowInfo(g_mainHwnd);
	if (mainInfo && mainInfo->nativeWindow)
	{
		g_mainWindow = (__bridge NSWindow*)mainInfo->nativeWindow;
		g_mainWindow.delegate = self;
		[g_mainWindow setMinSize:NSMakeSize(500, 400)];
	}

	SetMenu(g_mainHwnd, hMenuBar);

	NSView* contentView = g_mainWindow.contentView;

	// Create tab control at top using Win32 API
	g_tabHwnd = CreateWindowExW(
		0, L"SysTabControl32", L"",
		WS_CHILD | WS_VISIBLE | TCS_FOCUSNEVER,
		0, 0,
		static_cast<int>(contentView.bounds.size.width), 28,
		g_mainHwnd,
		reinterpret_cast<HMENU>(IDC_TABBAR),
		nullptr, nullptr
	);

	// Create status bar at bottom using Win32 API
	g_statusBarHwnd = CreateWindowExW(
		0, L"msctls_statusbar32", L"",
		WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
		0, 0, 0, 0,
		g_mainHwnd,
		reinterpret_cast<HMENU>(IDC_STATUSBAR),
		nullptr, nullptr
	);

	// Set up status bar parts
	int parts[] = {200, 400, 500, -1};
	SendMessageW(g_statusBarHwnd, SB_SETPARTS, 4, reinterpret_cast<LPARAM>(parts));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 0, reinterpret_cast<LPARAM>(L"Ln 1, Col 1"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 1, reinterpret_cast<LPARAM>(L"0 lines"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 2, reinterpret_cast<LPARAM>(L"UTF-8"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 3, reinterpret_cast<LPARAM>(L"Ready"));

	// Create Scintilla editor in the middle area
	// Calculate area between tab bar and status bar
	CGFloat tabHeight = 28;
	CGFloat statusHeight = 22;
	CGFloat editorY = tabHeight;
	CGFloat editorHeight = contentView.bounds.size.height - tabHeight - statusHeight;

	// Position status bar at bottom
	if (g_statusBarHwnd)
	{
		auto* sbInfo = HandleRegistry::getWindowInfo(g_statusBarHwnd);
		if (sbInfo && sbInfo->nativeView)
		{
			NSView* sbView = (__bridge NSView*)sbInfo->nativeView;
			sbView.frame = NSMakeRect(0, 0, contentView.bounds.size.width, statusHeight);
			sbView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
		}
	}

	// Create a container view for Scintilla (between tab bar and status bar)
	NSRect editorFrame = NSMakeRect(0, statusHeight, contentView.bounds.size.width, editorHeight);
	NSView* editorContainer = [[NSView alloc] initWithFrame:editorFrame];
	editorContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	[contentView addSubview:editorContainer];

	g_scintillaView = ScintillaBridge_createView((__bridge void*)editorContainer, 0, 0, 0, 0);
	if (!g_scintillaView)
	{
		NSLog(@"ERROR: Failed to create ScintillaView!");
		return;
	}

	configureScintilla(g_scintillaView);

	// Create first document tab
	const char* welcomeText =
		"// Welcome to Notepad++ on macOS — Phase 3!\n"
		"//\n"
		"// What's new in Phase 3:\n"
		"//   - Tab control (SysTabControl32 → NSSegmentedControl)\n"
		"//   - Multi-document editing with per-tab state\n"
		"//   - Status bar showing line/col, doc info, encoding\n"
		"//   - WM_NOTIFY/TCN_SELCHANGE dispatch for tab switching\n"
		"//   - File monitoring via FSEvents\n"
		"//   - Periodic timer for status bar updates\n"
		"//\n"
		"// Try:\n"
		"//   Cmd+N for new tab\n"
		"//   Cmd+O to open file (creates new tab)\n"
		"//   Cmd+W to close current tab\n"
		"//   Click tabs to switch between documents\n"
		"\n"
		"#include <iostream>\n"
		"\n"
		"int main() {\n"
		"    std::cout << \"Hello from Notepad++ macOS — Phase 3!\" << std::endl;\n"
		"    return 0;\n"
		"}\n";

	addNewTab(L"Welcome", std::string(welcomeText));

	// Start status bar update timer (500ms interval)
	SetTimer(g_mainHwnd, IDT_STATUSBAR, 500, nullptr);

	// Initialize file monitor
	g_fileMonitor = new FileMonitorMac();

	// Show the window
	ShowWindow(g_mainHwnd, SW_SHOW);
	[NSApp activateIgnoringOtherApps:YES];

	NSLog(@"=== Notepad++ macOS Port — Phase 3 ===");
	NSLog(@"Tabs, status bar, multi-document editing, and file monitoring working!");
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
	return YES;
}

- (void)applicationWillTerminate:(NSNotification*)notification
{
	if (g_fileMonitor)
	{
		g_fileMonitor->terminate();
		delete g_fileMonitor;
		g_fileMonitor = nullptr;
	}
}

- (void)windowDidResize:(NSNotification*)notification
{
	if (g_scintillaView)
		ScintillaBridge_resizeToFit(g_scintillaView);

	// Resize tab bar width
	if (g_tabHwnd && g_mainWindow)
	{
		auto* tabInfo = HandleRegistry::getWindowInfo(g_tabHwnd);
		if (tabInfo && tabInfo->nativeView)
		{
			NSView* tabView = (__bridge NSView*)tabInfo->nativeView;
			NSRect f = tabView.frame;
			f.size.width = g_mainWindow.contentView.bounds.size.width;
			tabView.frame = f;
		}
	}
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
