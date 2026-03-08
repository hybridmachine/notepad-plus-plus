// Win32 Controls Shim: Tab, StatusBar, Toolbar, ReBar, ImageList for macOS
// Phase 3: Real NSView-backed tab control and status bar.
// Toolbar and ReBar are data-only (N++ does custom drawing).

#import <Cocoa/Cocoa.h>
#include "windows.h"
#include "commctrl.h"
#include "handle_registry.h"
#include "win32_controls_impl.h"

#include <unordered_map>
#include <vector>
#include <string>
#include <algorithm>

// ============================================================
// Forward helpers
// ============================================================
static NSString* WideToNS(const wchar_t* wstr)
{
	if (!wstr) return @"";
	size_t len = wcslen(wstr);
	NSString* s = [[NSString alloc] initWithBytes:wstr
	                                       length:len * sizeof(wchar_t)
	                                     encoding:NSUTF32LittleEndianStringEncoding];
	return s ?: @"";
}

// ============================================================
// Control type detection
// ============================================================

bool Win32Controls_IsControlClass(const std::wstring& className)
{
	return Win32Controls_GetControlType(className) != ControlType::None;
}

ControlType Win32Controls_GetControlType(const std::wstring& className)
{
	if (className == L"SysTabControl32") return ControlType::TabControl;
	if (className == L"msctls_statusbar32") return ControlType::StatusBar;
	if (className == L"ToolbarWindow32") return ControlType::Toolbar;
	if (className == L"ReBarWindow32") return ControlType::ReBar;
	if (className == L"tooltips_class32") return ControlType::Tooltip;
	if (className == L"SysListView32") return ControlType::ListView;
	if (className == L"SysTreeView32") return ControlType::TreeView;
	return ControlType::None;
}

// ============================================================
// Tab Control data
// ============================================================

struct TabItemData
{
	std::wstring text;
	int image = -1;
	LPARAM lParam = 0;
};

struct TabControlData
{
	std::vector<TabItemData> items;
	int currentSel = -1;
	HWND hwnd = nullptr;
	HWND parent = nullptr;
};

static std::unordered_map<uintptr_t, TabControlData> s_tabControls;

// ============================================================
// ObjC helper: Routes NSSegmentedControl selection → WM_NOTIFY/TCN_SELCHANGE
// ============================================================

@interface Win32TabTarget : NSObject
@property (assign) HWND tabHwnd;
- (void)tabSelectionChanged:(id)sender;
@end

@implementation Win32TabTarget
- (void)tabSelectionChanged:(id)sender
{
	NSSegmentedControl* seg = (NSSegmentedControl*)sender;
	uintptr_t key = reinterpret_cast<uintptr_t>(self.tabHwnd);
	auto it = s_tabControls.find(key);
	if (it == s_tabControls.end()) return;

	int newSel = static_cast<int>([seg selectedSegment]);
	int oldSel = it->second.currentSel;
	it->second.currentSel = newSel;

	// Send WM_NOTIFY with TCN_SELCHANGE to the parent
	HWND parentHwnd = it->second.parent;
	if (parentHwnd)
	{
		auto* parentInfo = HandleRegistry::getWindowInfo(parentHwnd);
		if (parentInfo && parentInfo->wndProc)
		{
			NMHDR nmhdr;
			nmhdr.hwndFrom = self.tabHwnd;
			nmhdr.idFrom = static_cast<UINT_PTR>(
				HandleRegistry::getWindowInfo(self.tabHwnd)->controlId);
			nmhdr.code = TCN_SELCHANGE;
			parentInfo->wndProc(parentHwnd, WM_NOTIFY, nmhdr.idFrom,
			                    reinterpret_cast<LPARAM>(&nmhdr));
		}
	}
}
@end

// Global map of tab targets (prevent deallocation under ARC)
static NSMutableDictionary<NSNumber*, Win32TabTarget*>* s_tabTargets = nil;

// ============================================================
// StatusBar data
// ============================================================

// Custom NSView that draws a simple status bar with partitions
@interface Win32StatusBarView : NSView
@property (strong) NSMutableArray<NSString*>* partTexts;
@property (strong) NSMutableArray<NSNumber*>* partWidths;
@property (assign) int partCount;
@end

@implementation Win32StatusBarView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self)
	{
		_partTexts = [NSMutableArray array];
		_partWidths = [NSMutableArray array];
		_partCount = 0;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES; // Use top-left origin like Win32
}

- (void)drawRect:(NSRect)dirtyRect
{
	// Background
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(self.bounds);

	// Top border line
	[[NSColor separatorColor] setStroke];
	NSBezierPath* topLine = [NSBezierPath bezierPath];
	[topLine moveToPoint:NSMakePoint(0, 0)];
	[topLine lineToPoint:NSMakePoint(self.bounds.size.width, 0)];
	[topLine stroke];

	if (_partCount == 0) return;

	NSDictionary* attrs = @{
		NSFontAttributeName: [NSFont systemFontOfSize:11],
		NSForegroundColorAttributeName: [NSColor labelColor]
	};

	CGFloat x = 4;
	CGFloat totalWidth = self.bounds.size.width;

	for (int i = 0; i < _partCount; ++i)
	{
		// Calculate part width
		CGFloat partWidth;
		if (i < (int)_partWidths.count)
		{
			int w = _partWidths[i].intValue;
			if (w < 0 || i == _partCount - 1)
				partWidth = totalWidth - x; // last part or -1 fills remaining
			else
				partWidth = w;
		}
		else
		{
			partWidth = totalWidth - x;
		}

		// Draw separator
		if (i > 0)
		{
			[[NSColor separatorColor] setStroke];
			NSBezierPath* sep = [NSBezierPath bezierPath];
			[sep moveToPoint:NSMakePoint(x - 2, 3)];
			[sep lineToPoint:NSMakePoint(x - 2, self.bounds.size.height - 3)];
			[sep stroke];
		}

		// Draw text
		if (i < (int)_partTexts.count)
		{
			NSString* text = _partTexts[i];
			if (text.length > 0)
			{
				NSRect textRect = NSMakeRect(x + 2, 2, partWidth - 6,
				                             self.bounds.size.height - 4);
				[text drawInRect:textRect withAttributes:attrs];
			}
		}

		x += partWidth;
	}
}

@end

struct StatusBarData
{
	HWND hwnd = nullptr;
	std::vector<int> partWidths;
	std::vector<std::wstring> partTexts;
};

static std::unordered_map<uintptr_t, StatusBarData> s_statusBars;

// ============================================================
// Toolbar data (data-only, no visual rendering)
// ============================================================

struct ToolbarButtonData
{
	int iBitmap = 0;
	int idCommand = 0;
	BYTE fsState = TBSTATE_ENABLED;
	BYTE fsStyle = TBSTYLE_BUTTON;
	DWORD_PTR dwData = 0;
	INT_PTR iString = 0;
};

struct ToolbarData
{
	HWND hwnd = nullptr;
	std::vector<ToolbarButtonData> buttons;
	int buttonSizeCx = 24;
	int buttonSizeCy = 22;
};

static std::unordered_map<uintptr_t, ToolbarData> s_toolBars;

// ============================================================
// ReBar data (data-only)
// ============================================================

struct ReBarBandData
{
	UINT fMask = 0;
	UINT fStyle = 0;
	HWND hwndChild = nullptr;
	UINT cxMinChild = 0;
	UINT cyMinChild = 0;
	UINT cx = 0;
	UINT wID = 0;
	std::wstring text;
};

struct ReBarData
{
	HWND hwnd = nullptr;
	std::vector<ReBarBandData> bands;
};

static std::unordered_map<uintptr_t, ReBarData> s_reBars;

// ============================================================
// Control creation
// ============================================================

void* Win32Controls_CreateControl(ControlType type, void* parentView,
                                   int x, int y, int width, int height,
                                   unsigned long style, unsigned long exStyle)
{
	NSView* parent = (__bridge NSView*)parentView;
	if (!parent) return nullptr;

	CGFloat parentH = parent.bounds.size.height;

	switch (type)
	{
		case ControlType::TabControl:
		{
			// NSSegmentedControl for tabs
			NSRect frame = NSMakeRect(x, parentH - y - height, width, 28);
			NSSegmentedControl* seg = [[NSSegmentedControl alloc] initWithFrame:frame];
			seg.segmentStyle = NSSegmentStyleAutomatic;
			seg.trackingMode = NSSegmentSwitchTrackingSelectOne;
			seg.segmentCount = 0;
			seg.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
			[parent addSubview:seg];
			return (__bridge void*)seg;
		}

		case ControlType::StatusBar:
		{
			// Custom status bar view at bottom
			CGFloat barHeight = 22;
			NSRect frame = NSMakeRect(0, 0, parent.bounds.size.width, barHeight);
			Win32StatusBarView* bar = [[Win32StatusBarView alloc] initWithFrame:frame];
			bar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
			[parent addSubview:bar];
			return (__bridge void*)bar;
		}

		case ControlType::Toolbar:
		case ControlType::ReBar:
		case ControlType::Tooltip:
		case ControlType::ListView:
		case ControlType::TreeView:
		{
			// Data-only: create a hidden placeholder view
			NSRect frame = NSMakeRect(x, parentH - y - height, width, height);
			NSView* view = [[NSView alloc] initWithFrame:frame];
			[view setHidden:YES];
			[parent addSubview:view];
			return (__bridge void*)view;
		}

		default:
			return nullptr;
	}
}

// ============================================================
// Tab control message handling
// ============================================================

static bool HandleTabMessage(HWND hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam,
                              intptr_t& result)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hwnd);
	auto it = s_tabControls.find(key);
	if (it == s_tabControls.end()) return false;

	auto& tab = it->second;
	auto* info = HandleRegistry::getWindowInfo(hwnd);
	NSSegmentedControl* seg = info ? (__bridge NSSegmentedControl*)info->nativeView : nil;

	switch (msg)
	{
		case TCM_INSERTITEMW:
		{
			int index = static_cast<int>(wParam);
			const TCITEMW* pItem = reinterpret_cast<const TCITEMW*>(lParam);
			if (!pItem) { result = -1; return true; }

			TabItemData item;
			if (pItem->mask & TCIF_TEXT && pItem->pszText)
				item.text = pItem->pszText;
			if (pItem->mask & TCIF_IMAGE)
				item.image = pItem->iImage;
			if (pItem->mask & TCIF_PARAM)
				item.lParam = pItem->lParam;

			if (index < 0 || index > static_cast<int>(tab.items.size()))
				index = static_cast<int>(tab.items.size());

			tab.items.insert(tab.items.begin() + index, item);

			// Update NSSegmentedControl
			if (seg)
			{
				seg.segmentCount = static_cast<NSInteger>(tab.items.size());
				for (int i = 0; i < static_cast<int>(tab.items.size()); ++i)
				{
					[seg setLabel:WideToNS(tab.items[i].text.c_str()) forSegment:i];
					[seg setWidth:0 forSegment:i]; // auto-size
				}

				if (tab.currentSel < 0 && !tab.items.empty())
				{
					tab.currentSel = 0;
					seg.selectedSegment = 0;
				}
			}

			result = index;
			return true;
		}

		case TCM_DELETEITEM:
		{
			int index = static_cast<int>(wParam);
			if (index < 0 || index >= static_cast<int>(tab.items.size()))
			{
				result = FALSE;
				return true;
			}

			tab.items.erase(tab.items.begin() + index);

			if (seg)
			{
				seg.segmentCount = static_cast<NSInteger>(tab.items.size());
				for (int i = 0; i < static_cast<int>(tab.items.size()); ++i)
					[seg setLabel:WideToNS(tab.items[i].text.c_str()) forSegment:i];
			}

			if (tab.currentSel >= static_cast<int>(tab.items.size()))
				tab.currentSel = tab.items.empty() ? -1 : static_cast<int>(tab.items.size()) - 1;

			if (seg && tab.currentSel >= 0)
				seg.selectedSegment = tab.currentSel;

			result = TRUE;
			return true;
		}

		case TCM_DELETEALLITEMS:
		{
			tab.items.clear();
			tab.currentSel = -1;
			if (seg) seg.segmentCount = 0;
			result = TRUE;
			return true;
		}

		case TCM_GETCURSEL:
			result = tab.currentSel;
			return true;

		case TCM_SETCURSEL:
		{
			int index = static_cast<int>(wParam);
			int oldSel = tab.currentSel;

			if (index >= 0 && index < static_cast<int>(tab.items.size()))
			{
				tab.currentSel = index;
				if (seg) seg.selectedSegment = index;
			}

			result = oldSel;
			return true;
		}

		case TCM_GETITEMCOUNT:
			result = static_cast<intptr_t>(tab.items.size());
			return true;

		case TCM_GETITEMW:
		{
			int index = static_cast<int>(wParam);
			TCITEMW* pItem = reinterpret_cast<TCITEMW*>(lParam);
			if (!pItem || index < 0 || index >= static_cast<int>(tab.items.size()))
			{
				result = FALSE;
				return true;
			}

			const auto& item = tab.items[index];
			if (pItem->mask & TCIF_TEXT && pItem->pszText && pItem->cchTextMax > 0)
			{
				int maxCopy = pItem->cchTextMax - 1;
				int len = (std::min)(maxCopy, static_cast<int>(item.text.size()));
				wcsncpy(pItem->pszText, item.text.c_str(), len);
				pItem->pszText[len] = L'\0';
			}
			if (pItem->mask & TCIF_IMAGE)
				pItem->iImage = item.image;
			if (pItem->mask & TCIF_PARAM)
				pItem->lParam = item.lParam;

			result = TRUE;
			return true;
		}

		case TCM_SETITEMW:
		{
			int index = static_cast<int>(wParam);
			const TCITEMW* pItem = reinterpret_cast<const TCITEMW*>(lParam);
			if (!pItem || index < 0 || index >= static_cast<int>(tab.items.size()))
			{
				result = FALSE;
				return true;
			}

			auto& item = tab.items[index];
			if (pItem->mask & TCIF_TEXT && pItem->pszText)
			{
				item.text = pItem->pszText;
				if (seg)
					[seg setLabel:WideToNS(item.text.c_str()) forSegment:index];
			}
			if (pItem->mask & TCIF_IMAGE)
				item.image = pItem->iImage;
			if (pItem->mask & TCIF_PARAM)
				item.lParam = pItem->lParam;

			result = TRUE;
			return true;
		}

		case TCM_GETITEMRECT:
		{
			int index = static_cast<int>(wParam);
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (!pRect || !seg || index < 0 || index >= static_cast<int>(tab.items.size()))
			{
				result = FALSE;
				return true;
			}

			// Approximate: divide evenly
			CGFloat segWidth = seg.frame.size.width / (std::max)(1, (int)tab.items.size());
			pRect->left = static_cast<LONG>(index * segWidth);
			pRect->top = 0;
			pRect->right = static_cast<LONG>((index + 1) * segWidth);
			pRect->bottom = static_cast<LONG>(seg.frame.size.height);
			result = TRUE;
			return true;
		}

		case TCM_ADJUSTRECT:
		{
			// wParam TRUE = given window rect, return display rect
			// wParam FALSE = given display rect, return window rect
			// For simplicity, just shrink/expand by tab bar height
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (pRect)
			{
				if (wParam) // larger
					pRect->top += 28; // tab bar height
				else
					pRect->top -= 28;
			}
			result = 0;
			return true;
		}

		case TCM_SETITEMSIZE:
		case TCM_SETPADDING:
		case TCM_SETIMAGELIST:
		case TCM_GETIMAGELIST:
		case TCM_SETMINTABWIDTH:
		case TCM_SETEXTENDEDSTYLE:
		case TCM_GETEXTENDEDSTYLE:
		case TCM_HIGHLIGHTITEM:
		case TCM_GETTOOLTIPS:
		case TCM_SETTOOLTIPS:
		case TCM_GETROWCOUNT:
		case TCM_GETCURFOCUS:
		case TCM_SETCURFOCUS:
			result = 0;
			return true;

		case TCM_HITTEST:
		{
			TCHITTESTINFO* pHitTest = reinterpret_cast<TCHITTESTINFO*>(lParam);
			if (!pHitTest || !seg)
			{
				result = -1;
				return true;
			}
			// Simple hit test: check which segment the point falls in
			CGFloat segWidth = seg.frame.size.width / (std::max)(1, (int)tab.items.size());
			int hitIndex = static_cast<int>(pHitTest->pt.x / segWidth);
			if (hitIndex >= 0 && hitIndex < static_cast<int>(tab.items.size()))
			{
				pHitTest->flags = TCHT_ONITEMLABEL;
				result = hitIndex;
			}
			else
			{
				pHitTest->flags = TCHT_NOWHERE;
				result = -1;
			}
			return true;
		}
	}

	return false;
}

// ============================================================
// StatusBar message handling
// ============================================================

static bool HandleStatusBarMessage(HWND hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam,
                                    intptr_t& result)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hwnd);
	auto it = s_statusBars.find(key);
	if (it == s_statusBars.end()) return false;

	auto& sb = it->second;
	auto* info = HandleRegistry::getWindowInfo(hwnd);
	Win32StatusBarView* barView = info ? (__bridge Win32StatusBarView*)info->nativeView : nil;

	switch (msg)
	{
		case SB_SETPARTS:
		{
			int count = static_cast<int>(wParam);
			const int* widths = reinterpret_cast<const int*>(lParam);
			sb.partWidths.clear();
			sb.partTexts.resize(count);

			if (barView)
			{
				barView.partCount = count;
				[barView.partWidths removeAllObjects];
				[barView.partTexts removeAllObjects];
			}

			for (int i = 0; i < count; ++i)
			{
				sb.partWidths.push_back(widths ? widths[i] : -1);
				if (barView)
				{
					[barView.partWidths addObject:@(widths ? widths[i] : -1)];
					[barView.partTexts addObject:@""];
				}
			}

			if (barView) [barView setNeedsDisplay:YES];
			result = TRUE;
			return true;
		}

		case SB_SETTEXTW:
		{
			int part = static_cast<int>(wParam & 0xFF);
			// bits 8-15 are drawing type (SBT_OWNERDRAW etc.)
			const wchar_t* text = reinterpret_cast<const wchar_t*>(lParam);

			if (part >= 0 && part < static_cast<int>(sb.partTexts.size()))
			{
				sb.partTexts[part] = text ? text : L"";
				if (barView && part < (int)barView.partTexts.count)
				{
					barView.partTexts[part] = WideToNS(text);
					[barView setNeedsDisplay:YES];
				}
			}
			result = TRUE;
			return true;
		}

		case SB_GETTEXTW:
		{
			int part = static_cast<int>(wParam);
			wchar_t* buf = reinterpret_cast<wchar_t*>(lParam);
			if (part >= 0 && part < static_cast<int>(sb.partTexts.size()) && buf)
			{
				wcscpy(buf, sb.partTexts[part].c_str());
				result = static_cast<intptr_t>(sb.partTexts[part].size());
			}
			else
			{
				result = 0;
			}
			return true;
		}

		case SB_GETTEXTLENGTHW:
		{
			int part = static_cast<int>(wParam);
			if (part >= 0 && part < static_cast<int>(sb.partTexts.size()))
				result = static_cast<intptr_t>(sb.partTexts[part].size());
			else
				result = 0;
			return true;
		}

		case SB_GETPARTS:
		{
			int maxParts = static_cast<int>(wParam);
			int* widths = reinterpret_cast<int*>(lParam);
			int count = static_cast<int>(sb.partWidths.size());
			if (widths)
			{
				int n = (std::min)(maxParts, count);
				for (int i = 0; i < n; ++i)
					widths[i] = sb.partWidths[i];
			}
			result = count;
			return true;
		}

		case SB_GETRECT:
		{
			int part = static_cast<int>(wParam);
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (pRect && barView)
			{
				CGFloat x = 0;
				for (int i = 0; i < part && i < static_cast<int>(sb.partWidths.size()); ++i)
				{
					int w = sb.partWidths[i];
					x += (w > 0) ? w : (barView.bounds.size.width - x);
				}
				int w = (part < static_cast<int>(sb.partWidths.size())) ? sb.partWidths[part] : -1;
				CGFloat width = (w > 0) ? w : (barView.bounds.size.width - x);
				pRect->left = static_cast<LONG>(x);
				pRect->top = 0;
				pRect->right = static_cast<LONG>(x + width);
				pRect->bottom = static_cast<LONG>(barView.bounds.size.height);
				result = TRUE;
			}
			else
			{
				result = FALSE;
			}
			return true;
		}

		case SB_SETMINHEIGHT:
		{
			if (barView)
			{
				CGFloat h = static_cast<CGFloat>(wParam);
				NSRect f = barView.frame;
				f.size.height = h;
				barView.frame = f;
			}
			result = 0;
			return true;
		}

		case SB_SIMPLE:
		case SB_ISSIMPLE:
		case SB_SETICON:
		case SB_SETTIPTEXTW:
		case SB_GETTIPTEXTW:
		case SB_GETBORDERS:
			result = 0;
			return true;
	}

	return false;
}

// ============================================================
// Toolbar message handling (data-only)
// ============================================================

static bool HandleToolbarMessage(HWND hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam,
                                  intptr_t& result)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hwnd);
	auto it = s_toolBars.find(key);
	if (it == s_toolBars.end()) return false;

	auto& tb = it->second;

	switch (msg)
	{
		case TB_BUTTONSTRUCTSIZE:
			result = 0;
			return true;

		case TB_ADDBUTTONS:
		{
			int count = static_cast<int>(wParam);
			const TBBUTTON* buttons = reinterpret_cast<const TBBUTTON*>(lParam);
			if (buttons)
			{
				for (int i = 0; i < count; ++i)
				{
					ToolbarButtonData btn;
					btn.iBitmap = buttons[i].iBitmap;
					btn.idCommand = buttons[i].idCommand;
					btn.fsState = buttons[i].fsState;
					btn.fsStyle = buttons[i].fsStyle;
					btn.dwData = buttons[i].dwData;
					btn.iString = buttons[i].iString;
					tb.buttons.push_back(btn);
				}
			}
			result = TRUE;
			return true;
		}

		case TB_INSERTBUTTONW:
		{
			int index = static_cast<int>(wParam);
			const TBBUTTON* pBtn = reinterpret_cast<const TBBUTTON*>(lParam);
			if (pBtn)
			{
				ToolbarButtonData btn;
				btn.iBitmap = pBtn->iBitmap;
				btn.idCommand = pBtn->idCommand;
				btn.fsState = pBtn->fsState;
				btn.fsStyle = pBtn->fsStyle;
				btn.dwData = pBtn->dwData;
				btn.iString = pBtn->iString;

				if (index < 0 || index > static_cast<int>(tb.buttons.size()))
					index = static_cast<int>(tb.buttons.size());
				tb.buttons.insert(tb.buttons.begin() + index, btn);
			}
			result = TRUE;
			return true;
		}

		case TB_DELETEBUTTON:
		{
			int index = static_cast<int>(wParam);
			if (index >= 0 && index < static_cast<int>(tb.buttons.size()))
			{
				tb.buttons.erase(tb.buttons.begin() + index);
				result = TRUE;
			}
			else
			{
				result = FALSE;
			}
			return true;
		}

		case TB_BUTTONCOUNT:
			result = static_cast<intptr_t>(tb.buttons.size());
			return true;

		case TB_GETBUTTON:
		{
			int index = static_cast<int>(wParam);
			TBBUTTON* pBtn = reinterpret_cast<TBBUTTON*>(lParam);
			if (pBtn && index >= 0 && index < static_cast<int>(tb.buttons.size()))
			{
				const auto& btn = tb.buttons[index];
				pBtn->iBitmap = btn.iBitmap;
				pBtn->idCommand = btn.idCommand;
				pBtn->fsState = btn.fsState;
				pBtn->fsStyle = btn.fsStyle;
				pBtn->dwData = btn.dwData;
				pBtn->iString = btn.iString;
				result = TRUE;
			}
			else
			{
				result = FALSE;
			}
			return true;
		}

		case TB_COMMANDTOINDEX:
		{
			int cmdId = static_cast<int>(wParam);
			for (int i = 0; i < static_cast<int>(tb.buttons.size()); ++i)
			{
				if (tb.buttons[i].idCommand == cmdId)
				{
					result = i;
					return true;
				}
			}
			result = -1;
			return true;
		}

		case TB_ENABLEBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			bool enable = lParam != 0;
			for (auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (enable)
						btn.fsState |= TBSTATE_ENABLED;
					else
						btn.fsState &= ~TBSTATE_ENABLED;
					break;
				}
			}
			result = TRUE;
			return true;
		}

		case TB_CHECKBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			bool check = lParam != 0;
			for (auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (check)
						btn.fsState |= TBSTATE_CHECKED;
					else
						btn.fsState &= ~TBSTATE_CHECKED;
					break;
				}
			}
			result = TRUE;
			return true;
		}

		case TB_HIDEBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			bool hide = lParam != 0;
			for (auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (hide)
						btn.fsState |= TBSTATE_HIDDEN;
					else
						btn.fsState &= ~TBSTATE_HIDDEN;
					break;
				}
			}
			result = TRUE;
			return true;
		}

		case TB_ISBUTTONENABLED:
		{
			int cmdId = static_cast<int>(wParam);
			for (const auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					result = (btn.fsState & TBSTATE_ENABLED) ? TRUE : FALSE;
					return true;
				}
			}
			result = FALSE;
			return true;
		}

		case TB_ISBUTTONCHECKED:
		{
			int cmdId = static_cast<int>(wParam);
			for (const auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					result = (btn.fsState & TBSTATE_CHECKED) ? TRUE : FALSE;
					return true;
				}
			}
			result = FALSE;
			return true;
		}

		case TB_ISBUTTONHIDDEN:
		{
			int cmdId = static_cast<int>(wParam);
			for (const auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					result = (btn.fsState & TBSTATE_HIDDEN) ? TRUE : FALSE;
					return true;
				}
			}
			result = FALSE;
			return true;
		}

		case TB_GETSTATE:
		{
			int cmdId = static_cast<int>(wParam);
			for (const auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					result = btn.fsState;
					return true;
				}
			}
			result = -1;
			return true;
		}

		case TB_SETSTATE:
		{
			int cmdId = static_cast<int>(wParam);
			BYTE newState = static_cast<BYTE>(LOWORD(lParam));
			for (auto& btn : tb.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					btn.fsState = newState;
					break;
				}
			}
			result = TRUE;
			return true;
		}

		case TB_SETBUTTONSIZE:
		{
			tb.buttonSizeCx = LOWORD(lParam);
			tb.buttonSizeCy = HIWORD(lParam);
			result = TRUE;
			return true;
		}

		case TB_GETBUTTONSIZE:
			result = MAKELONG(tb.buttonSizeCx, tb.buttonSizeCy);
			return true;

		case TB_SETBITMAPSIZE:
		case TB_SETIMAGELIST:
		case TB_GETIMAGELIST:
		case TB_SETHOTIMAGELIST:
		case TB_SETDISABLEDIMAGELIST:
		case TB_AUTOSIZE:
		case TB_SETMAXTEXTROWS:
		case TB_GETTOOLTIPS:
		case TB_SETTOOLTIPS:
		case TB_SETPARENT:
		case TB_SETEXTENDEDSTYLE:
		case TB_GETEXTENDEDSTYLE:
		case TB_ADDBITMAP:
		case TB_SETDRAWTEXTFLAGS:
		case TB_SETPADDING:
		case TB_GETPADDING:
		case TB_SETCMDID:
		case TB_CUSTOMIZE:
		case TB_SAVERESTORE:
		case TB_PRESSBUTTON:
		case TB_INDETERMINATE:
		case TB_ISBUTTONPRESSED:
		case TB_SETROWS:
		case TB_GETROWS:
		case TB_GETBITMAPFLAGS:
			result = 0;
			return true;

		case TB_GETITEMRECT:
		case TB_GETRECT:
		{
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (pRect)
			{
				int index = (msg == TB_COMMANDTOINDEX) ? static_cast<int>(wParam) : static_cast<int>(wParam);
				pRect->left = index * tb.buttonSizeCx;
				pRect->top = 0;
				pRect->right = pRect->left + tb.buttonSizeCx;
				pRect->bottom = tb.buttonSizeCy;
			}
			result = TRUE;
			return true;
		}

		case TB_GETBUTTONINFOW:
		case TB_SETBUTTONINFOW:
			result = -1;
			return true;

		case TB_GETITEMDROPDOWNRECT:
		{
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (pRect)
				memset(pRect, 0, sizeof(RECT));
			result = FALSE;
			return true;
		}
	}

	return false;
}

// ============================================================
// ReBar message handling (data-only)
// ============================================================

static bool HandleReBarMessage(HWND hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam,
                                intptr_t& result)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hwnd);
	auto it = s_reBars.find(key);
	if (it == s_reBars.end()) return false;

	auto& rb = it->second;

	switch (msg)
	{
		case RB_INSERTBANDW:
		{
			const REBARBANDINFOW* pBand = reinterpret_cast<const REBARBANDINFOW*>(lParam);
			if (pBand)
			{
				ReBarBandData band;
				band.fMask = pBand->fMask;
				band.fStyle = pBand->fStyle;
				if (pBand->fMask & RBBIM_CHILD) band.hwndChild = pBand->hwndChild;
				if (pBand->fMask & RBBIM_CHILDSIZE) { band.cxMinChild = pBand->cxMinChild; band.cyMinChild = pBand->cyMinChild; }
				if (pBand->fMask & RBBIM_SIZE) band.cx = pBand->cx;
				if (pBand->fMask & RBBIM_ID) band.wID = pBand->wID;
				if (pBand->fMask & RBBIM_TEXT && pBand->lpText) band.text = pBand->lpText;

				int index = static_cast<int>(wParam);
				if (index < 0 || index > static_cast<int>(rb.bands.size()))
					index = static_cast<int>(rb.bands.size());
				rb.bands.insert(rb.bands.begin() + index, band);
			}
			result = TRUE;
			return true;
		}

		case RB_DELETEBAND:
		{
			int index = static_cast<int>(wParam);
			if (index >= 0 && index < static_cast<int>(rb.bands.size()))
			{
				rb.bands.erase(rb.bands.begin() + index);
				result = TRUE;
			}
			else
			{
				result = FALSE;
			}
			return true;
		}

		case RB_GETBANDCOUNT:
			result = static_cast<intptr_t>(rb.bands.size());
			return true;

		case RB_SETBANDINFOW:
		{
			int index = static_cast<int>(wParam);
			const REBARBANDINFOW* pBand = reinterpret_cast<const REBARBANDINFOW*>(lParam);
			if (pBand && index >= 0 && index < static_cast<int>(rb.bands.size()))
			{
				auto& band = rb.bands[index];
				if (pBand->fMask & RBBIM_STYLE) band.fStyle = pBand->fStyle;
				if (pBand->fMask & RBBIM_CHILD) band.hwndChild = pBand->hwndChild;
				if (pBand->fMask & RBBIM_CHILDSIZE) { band.cxMinChild = pBand->cxMinChild; band.cyMinChild = pBand->cyMinChild; }
				if (pBand->fMask & RBBIM_SIZE) band.cx = pBand->cx;
				if (pBand->fMask & RBBIM_ID) band.wID = pBand->wID;
				if (pBand->fMask & RBBIM_TEXT && pBand->lpText) band.text = pBand->lpText;
				result = TRUE;
			}
			else
			{
				result = FALSE;
			}
			return true;
		}

		case RB_GETBANDINFOW:
		{
			int index = static_cast<int>(wParam);
			REBARBANDINFOW* pBand = reinterpret_cast<REBARBANDINFOW*>(lParam);
			if (pBand && index >= 0 && index < static_cast<int>(rb.bands.size()))
			{
				const auto& band = rb.bands[index];
				if (pBand->fMask & RBBIM_STYLE) pBand->fStyle = band.fStyle;
				if (pBand->fMask & RBBIM_CHILD) pBand->hwndChild = band.hwndChild;
				if (pBand->fMask & RBBIM_CHILDSIZE) { pBand->cxMinChild = band.cxMinChild; pBand->cyMinChild = band.cyMinChild; }
				if (pBand->fMask & RBBIM_SIZE) pBand->cx = band.cx;
				if (pBand->fMask & RBBIM_ID) pBand->wID = band.wID;
				result = TRUE;
			}
			else
			{
				result = FALSE;
			}
			return true;
		}

		case RB_IDTOINDEX:
		{
			UINT id = static_cast<UINT>(wParam);
			for (int i = 0; i < static_cast<int>(rb.bands.size()); ++i)
			{
				if (rb.bands[i].wID == id)
				{
					result = i;
					return true;
				}
			}
			result = -1;
			return true;
		}

		case RB_SHOWBAND:
		{
			int index = static_cast<int>(wParam);
			if (index >= 0 && index < static_cast<int>(rb.bands.size()))
			{
				if (lParam)
					rb.bands[index].fStyle &= ~RBBS_HIDDEN;
				else
					rb.bands[index].fStyle |= RBBS_HIDDEN;
			}
			result = TRUE;
			return true;
		}

		case RB_SETBARINFO:
		case RB_GETBARINFO:
		case RB_GETROWCOUNT:
		case RB_GETROWHEIGHT:
		case RB_SIZETORECT:
		case RB_SETBKCOLOR:
		case RB_GETBKCOLOR:
		case RB_SETTEXTCOLOR:
		case RB_GETTEXTCOLOR:
		case RB_MOVEBAND:
		case RB_GETBARHEIGHT:
			result = 0;
			return true;
	}

	return false;
}

// ============================================================
// Dispatcher
// ============================================================

bool Win32Controls_HandleMessage(void* hwndVoid, ControlType type,
                                  unsigned int msg, uintptr_t wParam, intptr_t lParam,
                                  intptr_t& result)
{
	HWND hwnd = reinterpret_cast<HWND>(hwndVoid);

	switch (type)
	{
		case ControlType::TabControl:
			return HandleTabMessage(hwnd, msg, wParam, lParam, result);
		case ControlType::StatusBar:
			return HandleStatusBarMessage(hwnd, msg, wParam, lParam, result);
		case ControlType::Toolbar:
			return HandleToolbarMessage(hwnd, msg, wParam, lParam, result);
		case ControlType::ReBar:
			return HandleReBarMessage(hwnd, msg, wParam, lParam, result);
		default:
			return false;
	}
}

// ============================================================
// Control lifecycle management
// ============================================================

void Win32Controls_DestroyControl(void* hwndVoid, ControlType type)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hwndVoid);

	switch (type)
	{
		case ControlType::TabControl:
		{
			s_tabControls.erase(key);
			NSNumber* num = @(key);
			[s_tabTargets removeObjectForKey:num];
			break;
		}
		case ControlType::StatusBar:
			s_statusBars.erase(key);
			break;
		case ControlType::Toolbar:
			s_toolBars.erase(key);
			break;
		case ControlType::ReBar:
			s_reBars.erase(key);
			break;
		default:
			break;
	}
}

// Called from CreateWindowExW after the HWND is created and registered
// to initialize per-control data structures.
void Win32Controls_InitControl(HWND hwnd, ControlType type, HWND parent)
{
	uintptr_t key = reinterpret_cast<uintptr_t>(hwnd);

	switch (type)
	{
		case ControlType::TabControl:
		{
			TabControlData data;
			data.hwnd = hwnd;
			data.parent = parent;
			s_tabControls[key] = data;

			// Set up action target for the NSSegmentedControl
			auto* info = HandleRegistry::getWindowInfo(hwnd);
			if (info && info->nativeView)
			{
				if (!s_tabTargets)
					s_tabTargets = [NSMutableDictionary dictionary];

				Win32TabTarget* target = [[Win32TabTarget alloc] init];
				target.tabHwnd = hwnd;

				NSSegmentedControl* seg = (__bridge NSSegmentedControl*)info->nativeView;
				seg.target = target;
				seg.action = @selector(tabSelectionChanged:);

				s_tabTargets[@(key)] = target;
			}
			break;
		}
		case ControlType::StatusBar:
		{
			StatusBarData data;
			data.hwnd = hwnd;
			s_statusBars[key] = data;
			break;
		}
		case ControlType::Toolbar:
		{
			ToolbarData data;
			data.hwnd = hwnd;
			s_toolBars[key] = data;
			break;
		}
		case ControlType::ReBar:
		{
			ReBarData data;
			data.hwnd = hwnd;
			s_reBars[key] = data;
			break;
		}
		default:
			break;
	}
}

// ============================================================
// ImageList stubs (count-tracking only)
// ============================================================

struct ImageListData
{
	int cx = 0;
	int cy = 0;
	UINT flags = 0;
	int count = 0;
};

static std::unordered_map<uintptr_t, ImageListData> s_imageLists;
static uintptr_t s_nextImageList = 0x30000;

HIMAGELIST ImageList_Create(int cx, int cy, UINT flags, int cInitial, int cGrow)
{
	HIMAGELIST himl = reinterpret_cast<HIMAGELIST>(s_nextImageList++);
	ImageListData data;
	data.cx = cx;
	data.cy = cy;
	data.flags = flags;
	data.count = 0;
	s_imageLists[reinterpret_cast<uintptr_t>(himl)] = data;
	return himl;
}

BOOL ImageList_Destroy(HIMAGELIST himl)
{
	s_imageLists.erase(reinterpret_cast<uintptr_t>(himl));
	return TRUE;
}

int ImageList_Add(HIMAGELIST himl, HBITMAP hbmImage, HBITMAP hbmMask)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	if (it != s_imageLists.end())
		return it->second.count++;
	return -1;
}

int ImageList_AddMasked(HIMAGELIST himl, HBITMAP hbmImage, COLORREF crMask)
{
	return ImageList_Add(himl, hbmImage, nullptr);
}

int ImageList_ReplaceIcon(HIMAGELIST himl, int i, HICON hicon)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	if (it == s_imageLists.end()) return -1;

	if (i == -1) // append
		return it->second.count++;
	return i;
}

BOOL ImageList_Remove(HIMAGELIST himl, int i)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	if (it == s_imageLists.end()) return FALSE;

	if (i == -1) // remove all
		it->second.count = 0;
	else if (it->second.count > 0)
		--it->second.count;

	return TRUE;
}

int ImageList_GetImageCount(HIMAGELIST himl)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	return (it != s_imageLists.end()) ? it->second.count : 0;
}

BOOL ImageList_SetImageCount(HIMAGELIST himl, UINT uNewCount)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	if (it != s_imageLists.end())
	{
		it->second.count = static_cast<int>(uNewCount);
		return TRUE;
	}
	return FALSE;
}

BOOL ImageList_Draw(HIMAGELIST himl, int i, HDC hdcDst, int x, int y, UINT fStyle)
{
	return TRUE; // stub
}

BOOL ImageList_DrawEx(HIMAGELIST himl, int i, HDC hdcDst, int x, int y, int dx, int dy,
                       COLORREF rgbBk, COLORREF rgbFg, UINT fStyle)
{
	return TRUE; // stub
}

BOOL ImageList_SetIconSize(HIMAGELIST himl, int cx, int cy)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	if (it != s_imageLists.end())
	{
		it->second.cx = cx;
		it->second.cy = cy;
		return TRUE;
	}
	return FALSE;
}

HICON ImageList_GetIcon(HIMAGELIST himl, int i, UINT flags)
{
	return nullptr;
}

BOOL ImageList_GetIconSize(HIMAGELIST himl, int* cx, int* cy)
{
	auto it = s_imageLists.find(reinterpret_cast<uintptr_t>(himl));
	if (it != s_imageLists.end())
	{
		if (cx) *cx = it->second.cx;
		if (cy) *cy = it->second.cy;
		return TRUE;
	}
	return FALSE;
}

BOOL ImageList_GetImageInfo(HIMAGELIST himl, int i, IMAGEINFO* pImageInfo)
{
	if (pImageInfo) memset(pImageInfo, 0, sizeof(IMAGEINFO));
	return FALSE;
}

BOOL ImageList_BeginDrag(HIMAGELIST himlTrack, int iTrack, int dxHotspot, int dyHotspot) { return TRUE; }
BOOL ImageList_DragEnter(HWND hwndLock, int x, int y) { return TRUE; }
BOOL ImageList_DragMove(int x, int y) { return TRUE; }
BOOL ImageList_DragShowNolock(BOOL fShow) { return TRUE; }
BOOL ImageList_DragLeave(HWND hwndLock) { return TRUE; }
void ImageList_EndDrag() {}
HIMAGELIST ImageList_Merge(HIMAGELIST himl1, int i1, HIMAGELIST himl2, int i2, int dx, int dy) { return nullptr; }
