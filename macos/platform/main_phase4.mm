// Notepad++ macOS Port — Phase 4 Entry Point
// Demonstrates: Find/Replace dialog, Go To Line dialog, dialog controls
// (Button, Edit, Static, ComboBox, CheckBox), GetDlgItem, SetDlgItemText,
// CheckDlgButton, SendDlgItemMessage, and dark mode support.
//
// Builds on Phase 3: tabs, status bar, multi-document editing, file monitoring.

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
#define IDM_SEARCH_FIND       43001
#define IDM_SEARCH_REPLACE    43003
#define IDM_SEARCH_FINDNEXT   43004
#define IDM_SEARCH_FINDPREV   43005
#define IDM_SEARCH_GOTOLINE   43009

// Control IDs
#define IDC_TABBAR       1001
#define IDC_STATUSBAR    1002

// Find/Replace dialog control IDs
#define IDC_FIND_EDIT        2001
#define IDC_REPLACE_EDIT     2002
#define IDC_FIND_NEXT        2003
#define IDC_FIND_PREV        2004
#define IDC_FIND_COUNT       2005
#define IDC_REPLACE_ONE      2006
#define IDC_REPLACE_ALL      2007
#define IDC_FIND_CLOSE       2008
#define IDC_MATCH_CASE       2009
#define IDC_WHOLE_WORD       2010
#define IDC_FIND_LABEL       2011
#define IDC_REPLACE_LABEL    2012
#define IDC_FIND_STATUS      2013

// Go To Line dialog control IDs
#define IDC_GOTO_EDIT        3001
#define IDC_GOTO_GO          3002
#define IDC_GOTO_CANCEL      3003
#define IDC_GOTO_LABEL       3004
#define IDC_GOTO_INFO        3005

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
	SCI_GOTOLINE = 2024,
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
	SCI_GETSELTEXT = 2161,
	SCI_GETANCHOR = 2009,
	SCI_SCROLLCARET = 2169,
	SCI_GETSELECTIONSTART = 2143,
	SCI_GETSELECTIONEND = 2145,
	SCI_SETTARGETSTART = 2190,
	SCI_GETTARGETSTART = 2191,
	SCI_SETTARGETEND = 2192,
	SCI_GETTARGETEND = 2193,
	SCI_REPLACETARGET = 2194,
	SCI_SEARCHINTARGET = 2197,
	SCI_SETSEARCHFLAGS = 2198,
};

// Scintilla search flags
#define SCFIND_MATCHCASE 4
#define SCFIND_WHOLEWORD 2

// ============================================================
// Document data — per-tab state
// ============================================================

struct DocumentData
{
	std::wstring filePath;
	std::wstring title = L"Untitled";
	std::string content;
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

// Find/Replace state
static HWND g_findDlgHwnd = nullptr;
static std::wstring g_findText;
static std::wstring g_replaceText;
static bool g_matchCase = false;
static bool g_wholeWord = false;
static bool g_findMode = true; // true = Find, false = Replace

// ============================================================
// Helper: Convert wchar_t* to NSString
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

// ============================================================
// Scintilla state save/restore
// ============================================================
static void saveScintillaState()
{
	if (g_activeTab < 0 || g_activeTab >= static_cast<int>(g_documents.size()))
		return;
	if (!g_scintillaView) return;

	auto& doc = g_documents[g_activeTab];
	intptr_t len = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXTLENGTH, 0, 0);
	if (len >= 0)
	{
		doc.content.resize(len + 1);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, len + 1,
		                            (intptr_t)doc.content.data());
		doc.content.resize(len);
	}
	doc.cursorPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	doc.anchorPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETANCHOR, 0, 0);
	doc.firstVisibleLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETFIRSTVISIBLELINE, 0, 0);
	doc.modified = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETMODIFY, 0, 0) != 0;
}

static void restoreScintillaState(int tabIndex)
{
	if (tabIndex < 0 || tabIndex >= static_cast<int>(g_documents.size()))
		return;
	if (!g_scintillaView) return;

	const auto& doc = g_documents[tabIndex];
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)doc.content.c_str());
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETFIRSTVISIBLELINE, doc.firstVisibleLine, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEL, doc.anchorPos, doc.cursorPos);
	if (!doc.modified)
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
}

// ============================================================
// Tab management
// ============================================================
static void switchToTab(int tabIndex)
{
	if (tabIndex < 0 || tabIndex >= static_cast<int>(g_documents.size()))
		return;
	if (tabIndex == g_activeTab)
		return;

	saveScintillaState();
	g_activeTab = tabIndex;
	SendMessageW(g_tabHwnd, TCM_SETCURSEL, tabIndex, 0);
	restoreScintillaState(tabIndex);

	const auto& doc = g_documents[tabIndex];
	NSString* title = WideToNSString(doc.title.c_str());
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", title]];
}

static int addNewTab(const std::wstring& title, const std::string& content,
                      const std::wstring& filePath = L"")
{
	saveScintillaState();

	DocumentData doc;
	doc.title = title;
	doc.content = content;
	doc.filePath = filePath;
	g_documents.push_back(doc);

	int newIndex = static_cast<int>(g_documents.size()) - 1;

	TCITEMW tcItem = {};
	tcItem.mask = TCIF_TEXT;
	wchar_t titleBuf[256];
	wcsncpy(titleBuf, title.c_str(), 255);
	titleBuf[255] = L'\0';
	tcItem.pszText = titleBuf;
	SendMessageW(g_tabHwnd, TCM_INSERTITEMW, newIndex, reinterpret_cast<LPARAM>(&tcItem));

	g_activeTab = newIndex;
	SendMessageW(g_tabHwnd, TCM_SETCURSEL, newIndex, 0);

	if (g_scintillaView)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTEXT, 0, (intptr_t)content.c_str());
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOPOS, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
	}

	NSString* nsTitle = WideToNSString(title.c_str());
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", nsTitle]];

	return newIndex;
}

static void closeTab(int tabIndex)
{
	if (tabIndex < 0 || tabIndex >= static_cast<int>(g_documents.size()))
		return;

	if (g_documents.size() <= 1)
	{
		g_documents[0] = DocumentData();
		if (g_scintillaView)
		{
			ScintillaBridge_sendMessage(g_scintillaView, SCI_CLEARALL, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_EMPTYUNDOBUFFER, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSAVEPOINT, 0, 0);
		}
		TCITEMW tcItem = {};
		tcItem.mask = TCIF_TEXT;
		wchar_t title[] = L"Untitled";
		tcItem.pszText = title;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, 0, reinterpret_cast<LPARAM>(&tcItem));
		[g_mainWindow setTitle:@"Notepad++ — Untitled"];
		return;
	}

	SendMessageW(g_tabHwnd, TCM_DELETEITEM, tabIndex, 0);
	g_documents.erase(g_documents.begin() + tabIndex);

	if (g_activeTab >= static_cast<int>(g_documents.size()))
		g_activeTab = static_cast<int>(g_documents.size()) - 1;
	if (g_activeTab == tabIndex && g_activeTab > 0)
		--g_activeTab;

	SendMessageW(g_tabHwnd, TCM_SETCURSEL, g_activeTab, 0);
	restoreScintillaState(g_activeTab);

	const auto& doc = g_documents[g_activeTab];
	NSString* title = WideToNSString(doc.title.c_str());
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", title]];
}

// ============================================================
// Status bar
// ============================================================
static void updateStatusBar()
{
	if (!g_scintillaView || !g_statusBarHwnd) return;

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t line = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, pos, 0);
	intptr_t col = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCOLUMN, pos, 0);
	intptr_t lineCount = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLINECOUNT, 0, 0);
	intptr_t docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);

	wchar_t buf[128];
	swprintf(buf, 128, L"Ln %ld, Col %ld", (long)(line + 1), (long)(col + 1));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 0, reinterpret_cast<LPARAM>(buf));

	swprintf(buf, 128, L"%ld lines, %ld bytes", (long)lineCount, (long)docLen);
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 1, reinterpret_cast<LPARAM>(buf));

	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 2, reinterpret_cast<LPARAM>(L"UTF-8"));

	swprintf(buf, 128, L"Doc %d/%d", g_activeTab + 1, (int)g_documents.size());
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 3, reinterpret_cast<LPARAM>(buf));
}

// ============================================================
// Find/Replace operations using Scintilla
// ============================================================

static void updateFindStatus(const wchar_t* msg)
{
	if (g_findDlgHwnd)
		SetDlgItemTextW(g_findDlgHwnd, IDC_FIND_STATUS, msg);
}

static bool doFindNext(bool forward)
{
	if (!g_scintillaView || g_findText.empty()) return false;

	// Get search text as UTF-8
	NSString* nsFind = WideToNSString(g_findText.c_str());
	const char* utf8Find = [nsFind UTF8String];

	// Set search flags
	int flags = 0;
	if (g_matchCase) flags |= SCFIND_MATCHCASE;
	if (g_wholeWord) flags |= SCFIND_WHOLEWORD;
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEARCHFLAGS, flags, 0);

	intptr_t docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);

	if (forward)
	{
		intptr_t selEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONEND, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, selEnd, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, docLen, 0);
	}
	else
	{
		intptr_t selStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONSTART, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, selStart, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, 0, 0);
	}

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_SEARCHINTARGET,
	                                            strlen(utf8Find), (intptr_t)utf8Find);
	if (pos >= 0)
	{
		intptr_t targetEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTARGETEND, 0, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEL, pos, targetEnd);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SCROLLCARET, 0, 0);
		updateFindStatus(L"Match found");
		return true;
	}
	else
	{
		// Wrap around
		if (forward)
		{
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, 0, 0);
			intptr_t selEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONEND, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, selEnd, 0);
		}
		else
		{
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, docLen, 0);
			intptr_t selStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONSTART, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, selStart, 0);
		}

		pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_SEARCHINTARGET,
		                                  strlen(utf8Find), (intptr_t)utf8Find);
		if (pos >= 0)
		{
			intptr_t targetEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTARGETEND, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEL, pos, targetEnd);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SCROLLCARET, 0, 0);
			updateFindStatus(L"Wrapped around");
			return true;
		}
	}

	updateFindStatus(L"Not found");
	return false;
}

static int doCount()
{
	if (!g_scintillaView || g_findText.empty()) return 0;

	NSString* nsFind = WideToNSString(g_findText.c_str());
	const char* utf8Find = [nsFind UTF8String];

	int flags = 0;
	if (g_matchCase) flags |= SCFIND_MATCHCASE;
	if (g_wholeWord) flags |= SCFIND_WHOLEWORD;
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEARCHFLAGS, flags, 0);

	intptr_t docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);
	int count = 0;
	intptr_t searchStart = 0;
	size_t findLen = strlen(utf8Find);

	while (searchStart < docLen)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, searchStart, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, docLen, 0);
		intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_SEARCHINTARGET,
		                                            findLen, (intptr_t)utf8Find);
		if (pos < 0) break;
		++count;
		searchStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTARGETEND, 0, 0);
	}

	wchar_t buf[64];
	swprintf(buf, 64, L"%d matches found", count);
	updateFindStatus(buf);
	return count;
}

static void doReplaceOne()
{
	if (!g_scintillaView) return;

	// Check if current selection matches find text
	intptr_t selStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONSTART, 0, 0);
	intptr_t selEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONEND, 0, 0);

	if (selStart == selEnd)
	{
		// Nothing selected, find next first
		doFindNext(true);
		return;
	}

	// Replace the current selection
	NSString* nsReplace = WideToNSString(g_replaceText.c_str());
	const char* utf8Replace = [nsReplace UTF8String];

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, selStart, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, selEnd, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_REPLACETARGET,
	                            strlen(utf8Replace), (intptr_t)utf8Replace);

	// Find next occurrence
	doFindNext(true);
	updateFindStatus(L"Replaced 1 occurrence");
}

static void doReplaceAll()
{
	if (!g_scintillaView || g_findText.empty()) return;

	NSString* nsFind = WideToNSString(g_findText.c_str());
	NSString* nsReplace = WideToNSString(g_replaceText.c_str());
	const char* utf8Find = [nsFind UTF8String];
	const char* utf8Replace = [nsReplace UTF8String];

	int flags = 0;
	if (g_matchCase) flags |= SCFIND_MATCHCASE;
	if (g_wholeWord) flags |= SCFIND_WHOLEWORD;
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEARCHFLAGS, flags, 0);

	intptr_t docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);
	int count = 0;
	intptr_t searchStart = 0;
	size_t findLen = strlen(utf8Find);
	size_t replaceLen = strlen(utf8Replace);

	while (searchStart < docLen)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, searchStart, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, docLen, 0);
		intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_SEARCHINTARGET,
		                                            findLen, (intptr_t)utf8Find);
		if (pos < 0) break;

		ScintillaBridge_sendMessage(g_scintillaView, SCI_REPLACETARGET,
		                            replaceLen, (intptr_t)utf8Replace);
		++count;

		searchStart = pos + static_cast<intptr_t>(replaceLen);
		docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);
	}

	wchar_t buf[64];
	swprintf(buf, 64, L"Replaced %d occurrences", count);
	updateFindStatus(buf);
}

// ============================================================
// Find/Replace dialog
// ============================================================

static void readFindDlgState()
{
	if (!g_findDlgHwnd) return;

	wchar_t buf[1024];
	GetDlgItemTextW(g_findDlgHwnd, IDC_FIND_EDIT, buf, 1024);
	g_findText = buf;

	GetDlgItemTextW(g_findDlgHwnd, IDC_REPLACE_EDIT, buf, 1024);
	g_replaceText = buf;

	g_matchCase = (IsDlgButtonChecked(g_findDlgHwnd, IDC_MATCH_CASE) == BST_CHECKED);
	g_wholeWord = (IsDlgButtonChecked(g_findDlgHwnd, IDC_WHOLE_WORD) == BST_CHECKED);
}

static void createFindReplaceDlg(bool replaceMode)
{
	g_findMode = !replaceMode;

	// If dialog already exists, just show/update it
	if (g_findDlgHwnd)
	{
		auto* info = HandleRegistry::getWindowInfo(g_findDlgHwnd);
		if (info && info->nativeWindow)
		{
			NSWindow* win = (__bridge NSWindow*)info->nativeWindow;

			// Resize the window to match the mode (keep top edge fixed)
			int dlgHeight = replaceMode ? 240 : 180;
			NSRect contentRect = [win contentRectForFrameRect:win.frame];
			CGFloat heightDiff = dlgHeight - contentRect.size.height;
			NSRect newFrame = win.frame;
			newFrame.origin.y -= heightDiff;
			newFrame.size.height += heightDiff;
			[win setFrame:newFrame display:YES];

			// Reposition ALL controls (resize changes Cocoa Y-flip base)
			int dlgWidth = 450;
			int cbY = replaceMode ? 75 : 45;
			int btnY = replaceMode ? 110 : 75;
			int rBtnY = 145;
			int statusY = replaceMode ? 210 : 115;
			int btnW = 90;
			int btnH = 28;
			int btnGap = 8;

			// Find row (fixed Win32 positions, but need recalc after resize)
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_LABEL), 15, 15, 80, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_EDIT), 100, 12, 230, 24, TRUE);

			// Replace row
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_LABEL), 15, 45, 80, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_EDIT), 100, 42, 230, 24, TRUE);

			// Checkboxes
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_MATCH_CASE), 15, cbY, 120, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_WHOLE_WORD), 145, cbY, 120, 20, TRUE);

			// Find buttons
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_NEXT), 15, btnY, btnW, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_PREV), 15 + btnW + btnGap, btnY, btnW, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_COUNT), 15 + 2 * (btnW + btnGap), btnY, 70, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_CLOSE), dlgWidth - 85, btnY, 70, btnH, TRUE);

			// Replace buttons
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ONE), 15, rBtnY, btnW, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ALL), 15 + btnW + btnGap, rBtnY, btnW + 10, btnH, TRUE);

			// Status label
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_STATUS), 15, statusY, dlgWidth - 30, 20, TRUE);

			// Show/hide replace controls
			HWND hReplace = GetDlgItem(g_findDlgHwnd, IDC_REPLACE_EDIT);
			HWND hReplaceLabel = GetDlgItem(g_findDlgHwnd, IDC_REPLACE_LABEL);
			HWND hReplaceOne = GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ONE);
			HWND hReplaceAll = GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ALL);

			ShowWindow(hReplace, replaceMode ? SW_SHOW : SW_HIDE);
			ShowWindow(hReplaceLabel, replaceMode ? SW_SHOW : SW_HIDE);
			ShowWindow(hReplaceOne, replaceMode ? SW_SHOW : SW_HIDE);
			ShowWindow(hReplaceAll, replaceMode ? SW_SHOW : SW_HIDE);

			[win setTitle:replaceMode ? @"Replace" : @"Find"];
			[win makeKeyAndOrderFront:nil];
		}
		return;
	}

	// Create dialog window as NSPanel
	int dlgWidth = 450;
	int dlgHeight = replaceMode ? 240 : 180;

	NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
	NSRect contentRect = NSMakeRect(0, 0, dlgWidth, dlgHeight);
	NSPanel* panel = [[NSPanel alloc] initWithContentRect:contentRect
	                                    styleMask:styleMask
	                                    backing:NSBackingStoreBuffered
	                                    defer:NO];
	[panel setTitle:replaceMode ? @"Replace" : @"Find"];
	[panel setReleasedWhenClosed:NO];
	[panel setFloatingPanel:YES];
	[panel setBecomesKeyOnlyIfNeeded:YES];

	// Center on main window
	if (g_mainWindow)
	{
		NSRect mainFrame = g_mainWindow.frame;
		CGFloat x = mainFrame.origin.x + (mainFrame.size.width - dlgWidth) / 2;
		CGFloat y = mainFrame.origin.y + (mainFrame.size.height - dlgHeight) / 2;
		[panel setFrameOrigin:NSMakePoint(x, y)];
	}
	else
	{
		[panel center];
	}

	// Register as HWND
	HandleRegistry::WindowInfo dlgInfo;
	dlgInfo.className = L"#32770";
	dlgInfo.windowName = replaceMode ? L"Replace" : L"Find";
	dlgInfo.style = WS_POPUP | WS_CAPTION;
	dlgInfo.parent = g_mainHwnd;
	dlgInfo.nativeWindow = (__bridge void*)panel;
	dlgInfo.nativeView = (__bridge void*)[panel contentView];

	g_findDlgHwnd = HandleRegistry::createWindow(dlgInfo);

	// Create controls using Win32 API
	// "Find:" label
	CreateWindowExW(0, L"Static", L"Find:",
		WS_CHILD | WS_VISIBLE | SS_LEFT,
		15, 15, 80, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_LABEL), nullptr, nullptr);

	// Find text field
	CreateWindowExW(0, L"Edit", L"",
		WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
		100, 12, 230, 24,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_EDIT), nullptr, nullptr);

	// "Replace:" label
	HWND hReplaceLabel = CreateWindowExW(0, L"Static", L"Replace:",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | SS_LEFT,
		15, 45, 80, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_LABEL), nullptr, nullptr);

	// Replace text field
	HWND hReplaceEdit = CreateWindowExW(0, L"Edit", L"",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | ES_AUTOHSCROLL,
		100, 42, 230, 24,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_EDIT), nullptr, nullptr);

	// Checkboxes
	int cbY = replaceMode ? 75 : 45;
	CreateWindowExW(0, L"Button", L"Match case",
		WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
		15, cbY, 120, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_MATCH_CASE), nullptr, nullptr);

	CreateWindowExW(0, L"Button", L"Whole word",
		WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
		145, cbY, 120, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_WHOLE_WORD), nullptr, nullptr);

	// Buttons row
	int btnY = replaceMode ? 110 : 75;
	int btnW = 90;
	int btnH = 28;
	int btnGap = 8;

	CreateWindowExW(0, L"Button", L"Find Next",
		WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
		15, btnY, btnW, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_NEXT), nullptr, nullptr);

	CreateWindowExW(0, L"Button", L"Find Prev",
		WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
		15 + btnW + btnGap, btnY, btnW, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_PREV), nullptr, nullptr);

	CreateWindowExW(0, L"Button", L"Count",
		WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
		15 + 2 * (btnW + btnGap), btnY, 70, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_COUNT), nullptr, nullptr);

	CreateWindowExW(0, L"Button", L"Close",
		WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
		dlgWidth - 85, btnY, 70, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_CLOSE), nullptr, nullptr);

	// Replace buttons row
	int rBtnY = replaceMode ? 145 : 145;
	HWND hReplaceOne = CreateWindowExW(0, L"Button", L"Replace",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | BS_PUSHBUTTON,
		15, rBtnY, btnW, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_ONE), nullptr, nullptr);

	HWND hReplaceAll = CreateWindowExW(0, L"Button", L"Replace All",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | BS_PUSHBUTTON,
		15 + btnW + btnGap, rBtnY, btnW + 10, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_ALL), nullptr, nullptr);

	// Status label at bottom
	int statusY = replaceMode ? 210 : 115;
	CreateWindowExW(0, L"Static", L"",
		WS_CHILD | WS_VISIBLE | SS_LEFT,
		15, statusY, dlgWidth - 30, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_STATUS), nullptr, nullptr);

	// Set up the WndProc for button click handling
	// We handle WM_COMMAND from the find dialog in the main WndProc
	// by setting the dialog's wndProc
	auto* findDlgInfo = HandleRegistry::getWindowInfo(g_findDlgHwnd);
	if (findDlgInfo)
	{
		findDlgInfo->wndProc = [](HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT {
			if (msg == WM_COMMAND)
			{
				UINT cmdId = LOWORD(wParam);
				UINT notif = HIWORD(wParam);

				if (notif == BN_CLICKED)
				{
					switch (cmdId)
					{
						case IDC_FIND_NEXT:
							readFindDlgState();
							doFindNext(true);
							return 0;

						case IDC_FIND_PREV:
							readFindDlgState();
							doFindNext(false);
							return 0;

						case IDC_FIND_COUNT:
							readFindDlgState();
							doCount();
							return 0;

						case IDC_REPLACE_ONE:
							readFindDlgState();
							doReplaceOne();
							return 0;

						case IDC_REPLACE_ALL:
							readFindDlgState();
							doReplaceAll();
							return 0;

						case IDC_FIND_CLOSE:
						{
							auto* info = HandleRegistry::getWindowInfo(hWnd);
							if (info && info->nativeWindow)
							{
								NSWindow* win = (__bridge NSWindow*)info->nativeWindow;
								[win orderOut:nil];
							}
							return 0;
						}
					}
				}
			}
			return DefWindowProcW(hWnd, msg, wParam, lParam);
		};
	}

	// Pre-fill find text from current selection
	if (g_scintillaView)
	{
		intptr_t selStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONSTART, 0, 0);
		intptr_t selEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONEND, 0, 0);
		if (selEnd > selStart && (selEnd - selStart) < 256)
		{
			char utf8Buf[512] = {};
			ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELTEXT, 0, (intptr_t)utf8Buf);
			NSString* sel = [NSString stringWithUTF8String:utf8Buf];
			if (sel.length > 0)
			{
				NSData* data = [sel dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
				if (data && data.length > 0)
				{
					std::wstring wsel(reinterpret_cast<const wchar_t*>(data.bytes),
					                  data.length / sizeof(wchar_t));
					SetDlgItemTextW(g_findDlgHwnd, IDC_FIND_EDIT, wsel.c_str());
				}
			}
		}
	}

	[panel makeKeyAndOrderFront:nil];
}

// ============================================================
// Go To Line dialog (modal)
// ============================================================

static void showGoToLineDlg()
{
	if (!g_scintillaView) return;

	intptr_t lineCount = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLINECOUNT, 0, 0);
	intptr_t curPos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t curLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, curPos, 0);

	// Create a simple alert-style dialog using NSAlert with accessory view
	@autoreleasepool {
		NSAlert* alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Go To Line"];
		[alert setInformativeText:[NSString stringWithFormat:
			@"Enter line number (1-%ld). Current line: %ld",
			(long)lineCount, (long)(curLine + 1)]];
		[alert addButtonWithTitle:@"Go"];
		[alert addButtonWithTitle:@"Cancel"];

		NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
		input.stringValue = [NSString stringWithFormat:@"%ld", (long)(curLine + 1)];
		[alert setAccessoryView:input];

		// Select all text in the field
		[alert.window setInitialFirstResponder:input];

		NSModalResponse response = [alert runModal];
		if (response == NSAlertFirstButtonReturn)
		{
			int lineNum = input.intValue;
			if (lineNum > 0 && lineNum <= static_cast<int>(lineCount))
			{
				ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOLINE, lineNum - 1, 0);
				ScintillaBridge_sendMessage(g_scintillaView, SCI_SCROLLCARET, 0, 0);
			}
		}
	}
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
			size_t lastSlash = title.rfind(L'/');
			if (lastSlash != std::wstring::npos)
				title = title.substr(lastSlash + 1);
			addNewTab(title, std::string([content UTF8String]), wpath);

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

		TCITEMW tcItem = {};
		tcItem.mask = TCIF_TEXT;
		wchar_t titleBuf[256];
		wcsncpy(titleBuf, doc.title.c_str(), 255);
		titleBuf[255] = L'\0';
		tcItem.pszText = titleBuf;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, g_activeTab, reinterpret_cast<LPARAM>(&tcItem));
	}

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
					closeTab(0);
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

				case IDM_SEARCH_FIND:
					createFindReplaceDlg(false);
					return 0;
				case IDM_SEARCH_REPLACE:
					createFindReplaceDlg(true);
					return 0;
				case IDM_SEARCH_FINDNEXT:
					if (g_findText.empty())
						createFindReplaceDlg(false);
					else
						doFindNext(true);
					return 0;
				case IDM_SEARCH_FINDPREV:
					if (g_findText.empty())
						createFindReplaceDlg(false);
					else
						doFindNext(false);
					return 0;
				case IDM_SEARCH_GOTOLINE:
					showGoToLineDlg();
					return 0;
			}
			break;
		}

		case WM_NOTIFY:
		{
			NMHDR* pNmhdr = reinterpret_cast<NMHDR*>(lParam);
			if (pNmhdr && pNmhdr->code == TCN_SELCHANGE)
			{
				int newSel = static_cast<int>(SendMessageW(g_tabHwnd, TCM_GETCURSEL, 0, 0));
				if (newSel != g_activeTab && newSel >= 0)
					switchToTab(newSel);
				return 0;
			}
			break;
		}

		case WM_TIMER:
			if (wParam == IDT_STATUSBAR)
			{
				updateStatusBar();
				return 0;
			}
			break;

		case WM_SIZE:
			if (g_scintillaView)
				ScintillaBridge_resizeToFit(g_scintillaView);
			return 0;

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

	HMENU hSearchMenu = CreatePopupMenu();
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_FIND, L"&Find...\tCtrl+F");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_REPLACE, L"&Replace...\tCtrl+H");
	AppendMenuW(hSearchMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_FINDNEXT, L"Find &Next\tF3");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_FINDPREV, L"Find &Previous\tShift+F3");
	AppendMenuW(hSearchMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_GOTOLINE, L"&Go to Line...\tCtrl+G");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hSearchMenu), L"&Search");

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

	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 0, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 0, 50);

	ScintillaBridge_sendMessage(sci, SCI_SETLEXERLANGUAGE, 0, (intptr_t)"cpp");

	const char* keywords = "int char float double void bool true false "
	                        "if else for while do switch case break continue return "
	                        "class struct enum namespace using typedef "
	                        "const static virtual override public private protected "
	                        "new delete nullptr sizeof typeof "
	                        "try catch throw include define ifdef ifndef endif";
	ScintillaBridge_sendMessage(sci, SCI_SETKEYWORDS, 0, (intptr_t)keywords);

	ScintillaBridge_sendMessage(sci, SCI_STYLESETFONT, 32, (intptr_t)"Menlo");
	ScintillaBridge_sendMessage(sci, SCI_STYLESETSIZE, 32, 13);
	ScintillaBridge_sendMessage(sci, SCI_STYLECLEARALL, 0, 0);

	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 1, 0x008000);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 2, 0x008000);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 4, 0xFF8000);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 5, 0x0000FF);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 6, 0x800080);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETFORE, 9, 0x808080);
	ScintillaBridge_sendMessage(sci, SCI_STYLESETBOLD, 5, 1);

	ScintillaBridge_sendMessage(sci, SCI_SETPROPERTY, (uintptr_t)"fold", (intptr_t)"1");
	ScintillaBridge_sendMessage(sci, SCI_SETPROPERTY, (uintptr_t)"fold.compact", (intptr_t)"0");
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 2, 4);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINMASKN, 2, 0xFE000000);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 2, 16);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINSENSITIVEN, 2, 1);

	ScintillaBridge_sendMessage(sci, SCI_SETCARETLINEVISIBLE, 1, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETCARETLINEBACK, 0xF0F0F0, 0);
}

// ============================================================
// Dark mode support
// ============================================================

static void applyAppearance()
{
	// Respect system dark/light mode
	// NSApp.effectiveAppearance is automatically tracked
	// Scintilla and NSViews will follow the system appearance

	// Check if we're in dark mode
	NSAppearanceName appearanceName = [NSApp.effectiveAppearance
		bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	bool isDark = [appearanceName isEqualToString:NSAppearanceNameDarkAqua];

	if (g_scintillaView)
	{
		if (isDark)
		{
			// Dark mode colors
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 32, 0xD4D4D4);
			ScintillaBridge_sendMessage(g_scintillaView, 2052 /*SCI_STYLESETBACK*/, 32, 0x1E1E1E);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLECLEARALL, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETCARETLINEBACK, 0x2A2A2A, 0);
			// Syntax colors for dark mode
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 1, 0x6A9955);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 2, 0x6A9955);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 4, 0xCE9178);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 5, 0x569CD6);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 6, 0xB5CEA8);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 9, 0xC586C0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETBOLD, 5, 1);
			// Set caret color to white
			ScintillaBridge_sendMessage(g_scintillaView, 2069 /*SCI_SETCARETFORE*/, 0xAEAFAD, 0);
		}
		else
		{
			// Light mode colors (default)
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 32, 0x000000);
			ScintillaBridge_sendMessage(g_scintillaView, 2052 /*SCI_STYLESETBACK*/, 32, 0xFFFFFF);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLECLEARALL, 0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETCARETLINEBACK, 0xF0F0F0, 0);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 1, 0x008000);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 2, 0x008000);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 4, 0xFF8000);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 5, 0x0000FF);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 6, 0x800080);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 9, 0x808080);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETBOLD, 5, 1);
			ScintillaBridge_sendMessage(g_scintillaView, 2069 /*SCI_SETCARETFORE*/, 0x000000, 0);
		}
	}
}

// ============================================================
// Application Delegate
// ============================================================

@interface NppPhase4Delegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation NppPhase4Delegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
	// Register window class
	WNDCLASSEXW wc = {};
	wc.cbSize = sizeof(wc);
	wc.lpfnWndProc = MainWndProc;
	wc.lpszClassName = L"Notepad++Phase4";
	RegisterClassExW(&wc);

	// Build menu bar
	HMENU hMenuBar = buildMenuBar();

	// Create main window
	g_mainHwnd = CreateWindowExW(
		0, L"Notepad++Phase4", L"Notepad++ (macOS) — Phase 4",
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

	// Create tab control at top
	g_tabHwnd = CreateWindowExW(
		0, L"SysTabControl32", L"",
		WS_CHILD | WS_VISIBLE | TCS_FOCUSNEVER,
		0, 0,
		static_cast<int>(contentView.bounds.size.width), 28,
		g_mainHwnd,
		reinterpret_cast<HMENU>(IDC_TABBAR),
		nullptr, nullptr
	);

	// Create status bar at bottom
	g_statusBarHwnd = CreateWindowExW(
		0, L"msctls_statusbar32", L"",
		WS_CHILD | WS_VISIBLE | SBARS_SIZEGRIP,
		0, 0, 0, 0,
		g_mainHwnd,
		reinterpret_cast<HMENU>(IDC_STATUSBAR),
		nullptr, nullptr
	);

	int parts[] = {200, 400, 500, -1};
	SendMessageW(g_statusBarHwnd, SB_SETPARTS, 4, reinterpret_cast<LPARAM>(parts));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 0, reinterpret_cast<LPARAM>(L"Ln 1, Col 1"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 1, reinterpret_cast<LPARAM>(L"0 lines"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 2, reinterpret_cast<LPARAM>(L"UTF-8"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 3, reinterpret_cast<LPARAM>(L"Ready"));

	// Create Scintilla editor
	CGFloat tabHeight = 28;
	CGFloat statusHeight = 22;
	CGFloat editorHeight = contentView.bounds.size.height - tabHeight - statusHeight;

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

	// Apply dark/light mode
	applyAppearance();

	// Create first document
	const char* welcomeText =
		"// Welcome to Notepad++ on macOS — Phase 4!\n"
		"//\n"
		"// What's new in Phase 4:\n"
		"//   - Find/Replace dialog (Cmd+F / Cmd+H)\n"
		"//     * Find Next, Find Previous, Count\n"
		"//     * Replace, Replace All\n"
		"//     * Match Case and Whole Word options\n"
		"//   - Go To Line dialog (Cmd+G)\n"
		"//   - Dialog controls: Button, Edit, Static, CheckBox\n"
		"//   - GetDlgItem, SetDlgItemText, CheckDlgButton, etc.\n"
		"//   - Dark mode support via NSAppearance\n"
		"//\n"
		"// Try:\n"
		"//   Cmd+F for Find\n"
		"//   Cmd+H for Replace\n"
		"//   Cmd+G for Go To Line\n"
		"//   F3 / Shift+F3 for Find Next / Previous\n"
		"\n"
		"#include <iostream>\n"
		"#include <string>\n"
		"#include <vector>\n"
		"\n"
		"// A sample class to test Find/Replace\n"
		"class Greeter {\n"
		"public:\n"
		"    Greeter(const std::string& name) : _name(name) {}\n"
		"\n"
		"    void greet() const {\n"
		"        std::cout << \"Hello, \" << _name << \"!\" << std::endl;\n"
		"    }\n"
		"\n"
		"    void farewell() const {\n"
		"        std::cout << \"Goodbye, \" << _name << \"!\" << std::endl;\n"
		"    }\n"
		"\n"
		"private:\n"
		"    std::string _name;\n"
		"};\n"
		"\n"
		"int main() {\n"
		"    std::vector<std::string> names = {\"Alice\", \"Bob\", \"Charlie\"};\n"
		"\n"
		"    for (const auto& name : names) {\n"
		"        Greeter greeter(name);\n"
		"        greeter.greet();\n"
		"        greeter.farewell();\n"
		"    }\n"
		"\n"
		"    return 0;\n"
		"}\n";

	addNewTab(L"Welcome", std::string(welcomeText));

	// Start status bar update timer
	SetTimer(g_mainHwnd, IDT_STATUSBAR, 500, nullptr);

	// Initialize file monitor
	g_fileMonitor = new FileMonitorMac();

	// Show the window
	ShowWindow(g_mainHwnd, SW_SHOW);
	[NSApp activateIgnoringOtherApps:YES];

	// Listen for appearance changes
	[NSDistributedNotificationCenter.defaultCenter
		addObserver:self
		   selector:@selector(appearanceChanged:)
		       name:@"AppleInterfaceThemeChangedNotification"
		     object:nil];

	NSLog(@"=== Notepad++ macOS Port — Phase 4 ===");
	NSLog(@"Find/Replace, Go To Line, dialog controls, and dark mode working!");
}

- (void)appearanceChanged:(NSNotification*)notification
{
	dispatch_async(dispatch_get_main_queue(), ^{
		applyAppearance();
	});
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

		NppPhase4Delegate* delegate = [[NppPhase4Delegate alloc] init];
		app.delegate = delegate;

		[app run];
	}
	return 0;
}
