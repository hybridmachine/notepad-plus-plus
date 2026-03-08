// Win32 Shim: Common Controls for macOS
// Phase 3: Tab control, status bar, toolbar, rebar implementations.
// Each control type stores per-HWND data in a global map and
// handles control-specific messages (TCM_*, SB_*, TB_*, RB_*).

#import <Cocoa/Cocoa.h>
#include "windows.h"
#include "commctrl.h"
#include "handle_registry.h"

#include <string>
#include <vector>
#include <unordered_map>

// ============================================================
// Tab Control Data
// ============================================================

struct TabItem
{
	std::wstring text;
	LPARAM lParam = 0;
	int iImage = -1;
	DWORD dwState = 0;
};

struct TabControlData
{
	std::vector<TabItem> items;
	int selectedIndex = -1;
	HIMAGELIST imageList = nullptr;
};

static std::unordered_map<uintptr_t, TabControlData> s_tabControls;

// ============================================================
// Status Bar Data
// ============================================================

struct StatusBarData
{
	std::vector<int> partWidths;       // Right edges of each part (-1 = extend to right)
	std::vector<std::wstring> texts;   // Text for each part
	BOOL simpleMode = FALSE;
	std::wstring simpleText;
};

static std::unordered_map<uintptr_t, StatusBarData> s_statusBars;

// ============================================================
// Toolbar Data
// ============================================================

struct ToolBarButtonData
{
	int iBitmap = 0;
	int idCommand = 0;
	BYTE fsState = TBSTATE_ENABLED;
	BYTE fsStyle = TBSTYLE_BUTTON;
	DWORD_PTR dwData = 0;
	INT_PTR iString = -1;
};

struct ToolBarData
{
	std::vector<ToolBarButtonData> buttons;
	HIMAGELIST imageList = nullptr;
	HIMAGELIST disabledImageList = nullptr;
	HIMAGELIST hotImageList = nullptr;
	int buttonWidth = 24;
	int buttonHeight = 24;
};

static std::unordered_map<uintptr_t, ToolBarData> s_toolBars;

// ============================================================
// ReBar Data
// ============================================================

struct ReBarBandData
{
	UINT fMask = 0;
	UINT fStyle = 0;
	HWND hwndChild = nullptr;
	int cx = 0;
	int cy = 0;
	int cyMinChild = 0;
	int cxMinChild = 0;
	std::wstring text;
};

struct ReBarData
{
	std::vector<ReBarBandData> bands;
};

static std::unordered_map<uintptr_t, ReBarData> s_reBars;

// ============================================================
// Helper: Convert wchar_t* to NSString
// ============================================================
static NSString* WideToNS(const wchar_t* wstr)
{
	if (!wstr) return @"";
	size_t len = wcslen(wstr);
	NSString* str = [[NSString alloc] initWithBytes:wstr
	                                         length:len * sizeof(wchar_t)
	                                       encoding:NSUTF32LittleEndianStringEncoding];
	return str ?: @"";
}

// ============================================================
// Helper: Send WM_NOTIFY to parent
// ============================================================
static LRESULT SendNotifyToParent(HWND hWnd, UINT code)
{
	auto* info = HandleRegistry::getWindowInfo(hWnd);
	if (!info || !info->parent)
		return 0;

	auto* parentInfo = HandleRegistry::getWindowInfo(info->parent);
	if (!parentInfo || !parentInfo->wndProc)
		return 0;

	NMHDR nmhdr = {};
	nmhdr.hwndFrom = hWnd;
	nmhdr.idFrom = static_cast<UINT_PTR>(info->controlId);
	nmhdr.code = code;

	return parentInfo->wndProc(info->parent, WM_NOTIFY,
	                           static_cast<WPARAM>(info->controlId),
	                           reinterpret_cast<LPARAM>(&nmhdr));
}

// ============================================================
// ObjC helper: Custom tab bar view (replaces NSSegmentedControl)
// ============================================================

static const CGFloat kTabMinWidth = 80.0;
static const CGFloat kTabMaxWidth = 200.0;
static const CGFloat kTabPadding = 16.0;
static const CGFloat kTabCloseButtonWidth = 0.0; // Future: close button area

@interface Win32TabBarView : NSView
@property (assign) HWND hwnd;
@end

@implementation Win32TabBarView

- (BOOL)isFlipped { return YES; } // Use top-left origin like Win32

- (void)drawRect:(NSRect)dirtyRect
{
	NSLog(@"TAB_DRAW: drawRect called, bounds=%@, frame=%@, superview=%@, hwnd=%p",
		NSStringFromRect(self.bounds), NSStringFromRect(self.frame),
		self.superview, self.hwnd);

	// Draw background
	[[NSColor colorWithCalibratedWhite:0.85 alpha:1.0] setFill];
	NSRectFill(self.bounds);

	// Draw bottom border line
	[[NSColor grayColor] setStroke];
	NSBezierPath* border = [NSBezierPath bezierPath];
	[border moveToPoint:NSMakePoint(0, self.bounds.size.height - 0.5)];
	[border lineToPoint:NSMakePoint(self.bounds.size.width, self.bounds.size.height - 0.5)];
	[border stroke];

	auto key = reinterpret_cast<uintptr_t>(self.hwnd);
	auto it = s_tabControls.find(key);
	if (it == s_tabControls.end())
		return;

	auto& data = it->second;
	NSFont* font = [NSFont systemFontOfSize:11];
	CGFloat x = 2.0;
	CGFloat tabH = self.bounds.size.height;

	for (int i = 0; i < static_cast<int>(data.items.size()); ++i)
	{
		NSString* label = WideToNS(data.items[i].text.c_str());
		NSDictionary* attrs = @{NSFontAttributeName: font};
		CGFloat textWidth = [label sizeWithAttributes:attrs].width;
		CGFloat tabW = textWidth + kTabPadding * 2;
		if (tabW < kTabMinWidth) tabW = kTabMinWidth;
		if (tabW > kTabMaxWidth) tabW = kTabMaxWidth;

		BOOL isSelected = (i == data.selectedIndex);

		// Tab rect with 2px top margin and 0px bottom (tab sits on the bottom border)
		NSRect tabRect = NSMakeRect(x, 2, tabW, tabH - 2);

		// Tab background
		if (isSelected)
		{
			[[NSColor whiteColor] setFill];
			NSRectFill(tabRect);
		}
		else
		{
			[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] setFill];
			NSRectFill(tabRect);
		}

		// Draw border around each tab
		[[NSColor grayColor] setStroke];
		NSBezierPath* tabBorder = [NSBezierPath bezierPathWithRect:NSInsetRect(tabRect, 0.5, 0.5)];
		[tabBorder setLineWidth:1.0];
		[tabBorder stroke];

		// For selected tab, draw accent line at top
		if (isSelected)
		{
			[[NSColor controlAccentColor] setFill];
			NSRectFill(NSMakeRect(x + 1, 2, tabW - 2, 2));
		}

		// Tab text (centered)
		NSDictionary* textAttrs = @{
			NSFontAttributeName: font,
			NSForegroundColorAttributeName: isSelected
				? [NSColor blackColor]
				: [NSColor darkGrayColor]
		};
		NSSize textSize = [label sizeWithAttributes:textAttrs];
		CGFloat textY = 2 + ((tabH - 2) - textSize.height) / 2.0;
		CGFloat maxTextW = tabW - kTabPadding * 2;
		NSRect textRect = NSMakeRect(x + kTabPadding, textY, maxTextW, textSize.height);

		// Truncate with ellipsis if needed
		NSMutableParagraphStyle* para = [[NSMutableParagraphStyle alloc] init];
		para.lineBreakMode = NSLineBreakByTruncatingTail;
		NSMutableDictionary* drawAttrs = [textAttrs mutableCopy];
		drawAttrs[NSParagraphStyleAttributeName] = para;
		[label drawInRect:textRect withAttributes:drawAttrs];

		x += tabW + 1; // 1px gap between tabs
	}
}

- (void)mouseDown:(NSEvent*)event
{
	NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

	auto key = reinterpret_cast<uintptr_t>(self.hwnd);
	auto it = s_tabControls.find(key);
	if (it == s_tabControls.end())
		return;

	auto& data = it->second;
	NSFont* font = [NSFont systemFontOfSize:12];
	CGFloat x = 1.0;

	for (int i = 0; i < static_cast<int>(data.items.size()); ++i)
	{
		NSString* label = WideToNS(data.items[i].text.c_str());
		NSDictionary* attrs = @{NSFontAttributeName: font};
		CGFloat textWidth = [label sizeWithAttributes:attrs].width;
		CGFloat tabW = textWidth + kTabPadding * 2;
		if (tabW < kTabMinWidth) tabW = kTabMinWidth;
		if (tabW > kTabMaxWidth) tabW = kTabMaxWidth;

		if (loc.x >= x && loc.x < x + tabW)
		{
			if (i == data.selectedIndex)
				return; // Already selected

			// Send TCN_SELCHANGING - parent can veto
			LRESULT result = SendNotifyToParent(self.hwnd, TCN_SELCHANGING);
			if (result)
				return; // Vetoed

			data.selectedIndex = i;
			[self setNeedsDisplay:YES];

			// Send TCN_SELCHANGE
			SendNotifyToParent(self.hwnd, TCN_SELCHANGE);
			return;
		}

		x += tabW;
	}
}

// Helper: compute tab width for a given index
- (CGFloat)tabWidthForIndex:(int)index data:(const TabControlData&)data
{
	if (index < 0 || index >= static_cast<int>(data.items.size()))
		return kTabMinWidth;

	NSString* label = WideToNS(data.items[index].text.c_str());
	NSFont* font = [NSFont systemFontOfSize:12];
	NSDictionary* attrs = @{NSFontAttributeName: font};
	CGFloat textWidth = [label sizeWithAttributes:attrs].width;
	CGFloat tabW = textWidth + kTabPadding * 2;
	if (tabW < kTabMinWidth) tabW = kTabMinWidth;
	if (tabW > kTabMaxWidth) tabW = kTabMaxWidth;
	return tabW;
}

@end

// ============================================================
// ObjC helper: Status bar view
// ============================================================

@interface Win32StatusBarView : NSView
@property (assign) HWND hwnd;
@end

@implementation Win32StatusBarView

- (void)drawRect:(NSRect)dirtyRect
{
	// Draw background
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(dirtyRect);

	// Draw top border
	[[NSColor separatorColor] setStroke];
	NSBezierPath* border = [NSBezierPath bezierPath];
	[border moveToPoint:NSMakePoint(0, self.bounds.size.height - 0.5)];
	[border lineToPoint:NSMakePoint(self.bounds.size.width, self.bounds.size.height - 0.5)];
	[border stroke];

	auto key = reinterpret_cast<uintptr_t>(self.hwnd);
	auto it = s_statusBars.find(key);
	if (it == s_statusBars.end())
		return;

	auto& data = it->second;
	NSDictionary* attrs = @{
		NSFontAttributeName: [NSFont systemFontOfSize:11],
		NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
	};

	CGFloat totalWidth = self.bounds.size.width;
	size_t numParts = data.partWidths.size();

	for (size_t i = 0; i < numParts && i < data.texts.size(); ++i)
	{
		CGFloat left = (i == 0) ? 4 : data.partWidths[i - 1];
		CGFloat right = data.partWidths[i];
		if (right < 0 || right > totalWidth)
			right = totalWidth;

		NSString* text = WideToNS(data.texts[i].c_str());
		NSRect textRect = NSMakeRect(left + 4, 2, right - left - 8, self.bounds.size.height - 4);
		[text drawInRect:textRect withAttributes:attrs];

		// Draw separator
		if (i < numParts - 1 && data.partWidths[i] > 0)
		{
			[[NSColor separatorColor] setStroke];
			NSBezierPath* sep = [NSBezierPath bezierPath];
			[sep moveToPoint:NSMakePoint(right, 2)];
			[sep lineToPoint:NSMakePoint(right, self.bounds.size.height - 2)];
			[sep stroke];
		}
	}
}

@end

// ============================================================
// Tab Control Message Handler
// ============================================================

static LRESULT HandleTabControlMessage(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	auto key = reinterpret_cast<uintptr_t>(hWnd);
	auto it = s_tabControls.find(key);
	if (it == s_tabControls.end())
		return 0;

	auto& data = it->second;
	auto* info = HandleRegistry::getWindowInfo(hWnd);

	switch (msg)
	{
		case TCM_INSERTITEMW:
		{
			int index = static_cast<int>(wParam);
			const TCITEMW* pItem = reinterpret_cast<const TCITEMW*>(lParam);
			if (!pItem)
				return -1;

			TabItem tab;
			if ((pItem->mask & TCIF_TEXT) && pItem->pszText)
				tab.text = pItem->pszText;
			if (pItem->mask & TCIF_PARAM)
				tab.lParam = pItem->lParam;
			if (pItem->mask & TCIF_IMAGE)
				tab.iImage = pItem->iImage;

			if (index < 0 || index > static_cast<int>(data.items.size()))
				index = static_cast<int>(data.items.size());

			data.items.insert(data.items.begin() + index, tab);

			// Select first tab if none selected
			if (data.selectedIndex < 0 && !data.items.empty())
				data.selectedIndex = 0;

			// Redraw tab bar
			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}

			return index;
		}

		case TCM_DELETEITEM:
		{
			int index = static_cast<int>(wParam);
			if (index < 0 || index >= static_cast<int>(data.items.size()))
				return FALSE;

			data.items.erase(data.items.begin() + index);

			if (data.selectedIndex >= static_cast<int>(data.items.size()))
				data.selectedIndex = static_cast<int>(data.items.size()) - 1;

			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}

			return TRUE;
		}

		case TCM_DELETEALLITEMS:
		{
			data.items.clear();
			data.selectedIndex = -1;

			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}

			return TRUE;
		}

		case TCM_GETCURSEL:
			return data.selectedIndex;

		case TCM_SETCURSEL:
		{
			int newIndex = static_cast<int>(wParam);
			if (newIndex < 0 || newIndex >= static_cast<int>(data.items.size()))
				return -1;

			int oldIndex = data.selectedIndex;
			data.selectedIndex = newIndex;

			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}

			return oldIndex;
		}

		case TCM_GETITEMCOUNT:
			return static_cast<LRESULT>(data.items.size());

		case TCM_GETITEMW:
		{
			int index = static_cast<int>(wParam);
			TCITEMW* pItem = reinterpret_cast<TCITEMW*>(lParam);
			if (!pItem || index < 0 || index >= static_cast<int>(data.items.size()))
				return FALSE;

			auto& tab = data.items[index];
			if ((pItem->mask & TCIF_TEXT) && pItem->pszText && pItem->cchTextMax > 0)
			{
				size_t maxLen = static_cast<size_t>(pItem->cchTextMax - 1);
				size_t copyLen = tab.text.size() < maxLen ? tab.text.size() : maxLen;
				wcsncpy(pItem->pszText, tab.text.c_str(), copyLen);
				pItem->pszText[copyLen] = L'\0';
			}
			if (pItem->mask & TCIF_PARAM)
				pItem->lParam = tab.lParam;
			if (pItem->mask & TCIF_IMAGE)
				pItem->iImage = tab.iImage;
			if (pItem->mask & TCIF_STATE)
				pItem->dwState = tab.dwState;

			return TRUE;
		}

		case TCM_SETITEMW:
		{
			int index = static_cast<int>(wParam);
			const TCITEMW* pItem = reinterpret_cast<const TCITEMW*>(lParam);
			if (!pItem || index < 0 || index >= static_cast<int>(data.items.size()))
				return FALSE;

			auto& tab = data.items[index];
			if ((pItem->mask & TCIF_TEXT) && pItem->pszText)
				tab.text = pItem->pszText;
			if (pItem->mask & TCIF_PARAM)
				tab.lParam = pItem->lParam;
			if (pItem->mask & TCIF_IMAGE)
				tab.iImage = pItem->iImage;

			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}

			return TRUE;
		}

		case TCM_GETITEMRECT:
		{
			int index = static_cast<int>(wParam);
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (!pRect || index < 0 || index >= static_cast<int>(data.items.size()))
				return FALSE;

			// Calculate tab positions using same logic as drawRect
			NSFont* font = [NSFont systemFontOfSize:12];
			CGFloat x = 1.0;
			CGFloat tabH = 28;
			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				tabH = view.bounds.size.height;
			}

			for (int i = 0; i <= index; ++i)
			{
				NSString* label = WideToNS(data.items[i].text.c_str());
				NSDictionary* attrs = @{NSFontAttributeName: font};
				CGFloat textW = [label sizeWithAttributes:attrs].width;
				CGFloat tabW = textW + kTabPadding * 2;
				if (tabW < kTabMinWidth) tabW = kTabMinWidth;
				if (tabW > kTabMaxWidth) tabW = kTabMaxWidth;

				if (i == index)
				{
					pRect->left = static_cast<LONG>(x);
					pRect->top = 0;
					pRect->right = static_cast<LONG>(x + tabW);
					pRect->bottom = static_cast<LONG>(tabH);
					return TRUE;
				}
				x += tabW;
			}
			return FALSE;
		}

		case TCM_HITTEST:
		{
			TCHITTESTINFO* pHitTest = reinterpret_cast<TCHITTESTINFO*>(lParam);
			if (!pHitTest)
				return -1;

			int count = static_cast<int>(data.items.size());
			if (count == 0)
				return -1;

			NSFont* font = [NSFont systemFontOfSize:12];
			CGFloat x = 1.0;

			for (int i = 0; i < count; ++i)
			{
				NSString* label = WideToNS(data.items[i].text.c_str());
				NSDictionary* attrs = @{NSFontAttributeName: font};
				CGFloat textW = [label sizeWithAttributes:attrs].width;
				CGFloat tabW = textW + kTabPadding * 2;
				if (tabW < kTabMinWidth) tabW = kTabMinWidth;
				if (tabW > kTabMaxWidth) tabW = kTabMaxWidth;

				if (pHitTest->pt.x >= x && pHitTest->pt.x < x + tabW)
				{
					pHitTest->flags = TCHT_ONITEM;
					return i;
				}
				x += tabW;
			}

			pHitTest->flags = TCHT_NOWHERE;
			return -1;
		}

		case TCM_ADJUSTRECT:
		{
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (!pRect)
				return 0;
			// Adjust client area: if wParam is TRUE, convert display rect to tab rect
			// if FALSE, convert tab rect to display rect
			if (!wParam)
			{
				// Shrink by tab bar height at top
				pRect->top += 28;
			}
			else
			{
				pRect->top -= 28;
			}
			return 0;
		}

		case TCM_SETIMAGELIST:
		{
			HIMAGELIST old = data.imageList;
			data.imageList = reinterpret_cast<HIMAGELIST>(lParam);
			return reinterpret_cast<LRESULT>(old);
		}

		case TCM_GETIMAGELIST:
			return reinterpret_cast<LRESULT>(data.imageList);

		case TCM_SETITEMSIZE:
		case TCM_SETPADDING:
		case TCM_GETROWCOUNT:
		case TCM_SETMINTABWIDTH:
		case TCM_GETCURFOCUS:
		case TCM_SETCURFOCUS:
		case TCM_HIGHLIGHTITEM:
		case TCM_SETEXTENDEDSTYLE:
		case TCM_GETEXTENDEDSTYLE:
		case TCM_REMOVEIMAGE:
			return 0; // Stubs

		case TCM_GETTOOLTIPS:
		case TCM_SETTOOLTIPS:
			return 0;

		case WM_SIZE:
		{
			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				int w = LOWORD(lParam);
				int h = HIWORD(lParam);
				if (w > 0 && h > 0)
				{
					[view setFrame:NSMakeRect(0, 0, w, h)];
					[view setNeedsDisplay:YES];
				}
			}
			return 0;
		}
	}

	return 0;
}

// ============================================================
// Status Bar Message Handler
// ============================================================

static LRESULT HandleStatusBarMessage(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	auto key = reinterpret_cast<uintptr_t>(hWnd);
	auto it = s_statusBars.find(key);
	if (it == s_statusBars.end())
		return 0;

	auto& data = it->second;
	auto* info = HandleRegistry::getWindowInfo(hWnd);

	switch (msg)
	{
		case SB_SETPARTS:
		{
			int numParts = static_cast<int>(wParam);
			const int* widths = reinterpret_cast<const int*>(lParam);
			if (!widths || numParts <= 0)
				return FALSE;

			data.partWidths.assign(widths, widths + numParts);
			data.texts.resize(numParts);

			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}
			return TRUE;
		}

		case SB_SETTEXTW:
		{
			int partIndex = LOWORD(wParam);
			// HIWORD(wParam) contains drawing type (SBT_OWNERDRAW, etc.)
			const wchar_t* text = reinterpret_cast<const wchar_t*>(lParam);

			if (partIndex >= 0 && partIndex < static_cast<int>(data.texts.size()))
			{
				data.texts[partIndex] = text ? text : L"";

				if (info && info->nativeView)
				{
					NSView* view = (__bridge NSView*)info->nativeView;
					[view setNeedsDisplay:YES];
				}
			}
			return TRUE;
		}

		case SB_GETTEXTW:
		{
			int partIndex = LOWORD(wParam);
			wchar_t* buffer = reinterpret_cast<wchar_t*>(lParam);
			if (partIndex >= 0 && partIndex < static_cast<int>(data.texts.size()) && buffer)
			{
				wcscpy(buffer, data.texts[partIndex].c_str());
				return MAKELONG(data.texts[partIndex].size(), 0);
			}
			return 0;
		}

		case SB_GETTEXTLENGTHW:
		{
			int partIndex = LOWORD(wParam);
			if (partIndex >= 0 && partIndex < static_cast<int>(data.texts.size()))
				return MAKELONG(data.texts[partIndex].size(), 0);
			return 0;
		}

		case SB_GETPARTS:
		{
			int maxParts = static_cast<int>(wParam);
			int* pParts = reinterpret_cast<int*>(lParam);
			int count = static_cast<int>(data.partWidths.size());

			if (pParts && maxParts > 0)
			{
				int copy = count < maxParts ? count : maxParts;
				for (int i = 0; i < copy; ++i)
					pParts[i] = data.partWidths[i];
			}
			return count;
		}

		case SB_GETRECT:
		{
			int partIndex = static_cast<int>(wParam);
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (!pRect || partIndex < 0 || partIndex >= static_cast<int>(data.partWidths.size()))
				return FALSE;

			CGFloat height = 22;
			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				height = view.bounds.size.height;
			}

			pRect->left = (partIndex == 0) ? 0 : data.partWidths[partIndex - 1];
			pRect->top = 0;
			pRect->right = data.partWidths[partIndex];
			pRect->bottom = static_cast<LONG>(height);
			return TRUE;
		}

		case SB_GETBORDERS:
		{
			int* borders = reinterpret_cast<int*>(lParam);
			if (borders)
			{
				borders[0] = 1; // horizontal border width
				borders[1] = 1; // vertical border width
				borders[2] = 1; // separator width
			}
			return TRUE;
		}

		case SB_SIMPLE:
			data.simpleMode = static_cast<BOOL>(wParam);
			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				[view setNeedsDisplay:YES];
			}
			return 0;

		case WM_SIZE:
		{
			if (info && info->nativeView)
			{
				NSView* view = (__bridge NSView*)info->nativeView;
				NSView* parent = [view superview];
				if (parent)
				{
					CGFloat height = view.bounds.size.height;
					CGFloat parentW = parent.bounds.size.width;
					// Status bar sticks to bottom, full width
					[view setFrame:NSMakeRect(0, 0, parentW, height)];
					[view setNeedsDisplay:YES];
				}
			}
			return 0;
		}

		case WM_GETTEXT:
		{
			wchar_t* buffer = reinterpret_cast<wchar_t*>(lParam);
			int maxLen = static_cast<int>(wParam);
			if (buffer && maxLen > 0)
			{
				if (!data.texts.empty())
				{
					size_t copyLen = data.texts[0].size() < static_cast<size_t>(maxLen - 1)
					    ? data.texts[0].size() : static_cast<size_t>(maxLen - 1);
					wcsncpy(buffer, data.texts[0].c_str(), copyLen);
					buffer[copyLen] = L'\0';
					return copyLen;
				}
				buffer[0] = L'\0';
			}
			return 0;
		}
	}

	return 0;
}

// ============================================================
// Toolbar Message Handler
// ============================================================

static LRESULT HandleToolBarMessage(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	auto key = reinterpret_cast<uintptr_t>(hWnd);
	auto it = s_toolBars.find(key);
	if (it == s_toolBars.end())
		return 0;

	auto& data = it->second;

	switch (msg)
	{
		case TB_BUTTONCOUNT:
			return static_cast<LRESULT>(data.buttons.size());

		case TB_ADDBUTTONS:
		{
			int count = static_cast<int>(wParam);
			const TBBUTTON* pButtons = reinterpret_cast<const TBBUTTON*>(lParam);
			if (!pButtons)
				return FALSE;

			for (int i = 0; i < count; ++i)
			{
				ToolBarButtonData btn;
				btn.iBitmap = pButtons[i].iBitmap;
				btn.idCommand = pButtons[i].idCommand;
				btn.fsState = pButtons[i].fsState;
				btn.fsStyle = pButtons[i].fsStyle;
				btn.dwData = pButtons[i].dwData;
				btn.iString = pButtons[i].iString;
				data.buttons.push_back(btn);
			}
			return TRUE;
		}

		case TB_INSERTBUTTONW:
		{
			int index = static_cast<int>(wParam);
			const TBBUTTON* pBtn = reinterpret_cast<const TBBUTTON*>(lParam);
			if (!pBtn)
				return FALSE;

			ToolBarButtonData btn;
			btn.iBitmap = pBtn->iBitmap;
			btn.idCommand = pBtn->idCommand;
			btn.fsState = pBtn->fsState;
			btn.fsStyle = pBtn->fsStyle;
			btn.dwData = pBtn->dwData;
			btn.iString = pBtn->iString;

			if (index < 0 || index > static_cast<int>(data.buttons.size()))
				index = static_cast<int>(data.buttons.size());

			data.buttons.insert(data.buttons.begin() + index, btn);
			return TRUE;
		}

		case TB_DELETEBUTTON:
		{
			int index = static_cast<int>(wParam);
			if (index < 0 || index >= static_cast<int>(data.buttons.size()))
				return FALSE;
			data.buttons.erase(data.buttons.begin() + index);
			return TRUE;
		}

		case TB_ENABLEBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			BOOL enable = LOWORD(lParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (enable)
						btn.fsState |= TBSTATE_ENABLED;
					else
						btn.fsState &= ~TBSTATE_ENABLED;
					return TRUE;
				}
			}
			return FALSE;
		}

		case TB_CHECKBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			BOOL check = LOWORD(lParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (check)
						btn.fsState |= TBSTATE_CHECKED;
					else
						btn.fsState &= ~TBSTATE_CHECKED;
					return TRUE;
				}
			}
			return FALSE;
		}

		case TB_GETSTATE:
		{
			int cmdId = static_cast<int>(wParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
					return btn.fsState;
			}
			return -1;
		}

		case TB_SETSTATE:
		{
			int cmdId = static_cast<int>(wParam);
			BYTE newState = LOWORD(lParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					btn.fsState = newState;
					return TRUE;
				}
			}
			return FALSE;
		}

		case TB_COMMANDTOINDEX:
		{
			int cmdId = static_cast<int>(wParam);
			for (size_t i = 0; i < data.buttons.size(); ++i)
			{
				if (data.buttons[i].idCommand == cmdId)
					return static_cast<LRESULT>(i);
			}
			return -1;
		}

		case TB_GETBUTTON:
		{
			int index = static_cast<int>(wParam);
			TBBUTTON* pBtn = reinterpret_cast<TBBUTTON*>(lParam);
			if (!pBtn || index < 0 || index >= static_cast<int>(data.buttons.size()))
				return FALSE;

			auto& btn = data.buttons[index];
			pBtn->iBitmap = btn.iBitmap;
			pBtn->idCommand = btn.idCommand;
			pBtn->fsState = btn.fsState;
			pBtn->fsStyle = btn.fsStyle;
			pBtn->dwData = btn.dwData;
			pBtn->iString = btn.iString;
			return TRUE;
		}

		case TB_SETIMAGELIST:
		{
			HIMAGELIST old = data.imageList;
			data.imageList = reinterpret_cast<HIMAGELIST>(lParam);
			return reinterpret_cast<LRESULT>(old);
		}

		case TB_GETIMAGELIST:
			return reinterpret_cast<LRESULT>(data.imageList);

		case TB_SETDISABLEDIMAGELIST:
		{
			HIMAGELIST old = data.disabledImageList;
			data.disabledImageList = reinterpret_cast<HIMAGELIST>(lParam);
			return reinterpret_cast<LRESULT>(old);
		}

		case TB_SETHOTIMAGELIST:
		{
			HIMAGELIST old = data.hotImageList;
			data.hotImageList = reinterpret_cast<HIMAGELIST>(lParam);
			return reinterpret_cast<LRESULT>(old);
		}

		case TB_SETBUTTONSIZE:
		{
			data.buttonWidth = LOWORD(lParam);
			data.buttonHeight = HIWORD(lParam);
			return TRUE;
		}

		case TB_GETBUTTONSIZE:
			return MAKELONG(data.buttonWidth, data.buttonHeight);

		case TB_GETITEMRECT:
		case TB_GETRECT:
		{
			RECT* pRect = reinterpret_cast<RECT*>(lParam);
			if (pRect)
			{
				int index = static_cast<int>(wParam);
				if (msg == TB_GETRECT)
				{
					// wParam is command ID, find index
					for (size_t i = 0; i < data.buttons.size(); ++i)
					{
						if (data.buttons[i].idCommand == static_cast<int>(wParam))
						{
							index = static_cast<int>(i);
							break;
						}
					}
				}
				pRect->left = index * data.buttonWidth;
				pRect->top = 0;
				pRect->right = (index + 1) * data.buttonWidth;
				pRect->bottom = data.buttonHeight;
			}
			return TRUE;
		}

		case TB_GETBUTTONINFOW:
		{
			int cmdId = static_cast<int>(wParam);
			TBBUTTONINFOW* pInfo = reinterpret_cast<TBBUTTONINFOW*>(lParam);
			if (!pInfo)
				return -1;

			for (size_t i = 0; i < data.buttons.size(); ++i)
			{
				if (data.buttons[i].idCommand == cmdId)
				{
					if (pInfo->dwMask & TBIF_COMMAND)
						pInfo->idCommand = data.buttons[i].idCommand;
					if (pInfo->dwMask & TBIF_STATE)
						pInfo->fsState = data.buttons[i].fsState;
					if (pInfo->dwMask & TBIF_STYLE)
						pInfo->fsStyle = data.buttons[i].fsStyle;
					if (pInfo->dwMask & TBIF_IMAGE)
						pInfo->iImage = data.buttons[i].iBitmap;
					return static_cast<LRESULT>(i);
				}
			}
			return -1;
		}

		case TB_SETBUTTONINFOW:
		{
			int cmdId = static_cast<int>(wParam);
			const TBBUTTONINFOW* pInfo = reinterpret_cast<const TBBUTTONINFOW*>(lParam);
			if (!pInfo)
				return FALSE;

			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (pInfo->dwMask & TBIF_COMMAND)
						btn.idCommand = pInfo->idCommand;
					if (pInfo->dwMask & TBIF_STATE)
						btn.fsState = pInfo->fsState;
					if (pInfo->dwMask & TBIF_STYLE)
						btn.fsStyle = pInfo->fsStyle;
					if (pInfo->dwMask & TBIF_IMAGE)
						btn.iBitmap = pInfo->iImage;
					return TRUE;
				}
			}
			return FALSE;
		}

		// Stubs
		case TB_BUTTONSTRUCTSIZE:
		case TB_AUTOSIZE:
		case TB_SETBITMAPSIZE:
		case TB_SETMAXTEXTROWS:
		case TB_SETPADDING:
		case TB_SETDRAWTEXTFLAGS:
		case TB_SETROWS:
		case TB_SETPARENT:
		case TB_SETCMDID:
		case TB_SAVERESTORE:
		case TB_CUSTOMIZE:
		case TB_ADDBITMAP:
			return 0;

		case TB_GETTOOLTIPS:
		case TB_SETTOOLTIPS:
			return 0;

		case TB_GETROWS:
			return 1;

		case TB_ISBUTTONENABLED:
		{
			int cmdId = static_cast<int>(wParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
					return (btn.fsState & TBSTATE_ENABLED) ? TRUE : FALSE;
			}
			return FALSE;
		}

		case TB_ISBUTTONCHECKED:
		{
			int cmdId = static_cast<int>(wParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
					return (btn.fsState & TBSTATE_CHECKED) ? TRUE : FALSE;
			}
			return FALSE;
		}

		case TB_ISBUTTONHIDDEN:
		{
			int cmdId = static_cast<int>(wParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
					return (btn.fsState & TBSTATE_HIDDEN) ? TRUE : FALSE;
			}
			return FALSE;
		}

		case TB_HIDEBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			BOOL hide = LOWORD(lParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (hide)
						btn.fsState |= TBSTATE_HIDDEN;
					else
						btn.fsState &= ~TBSTATE_HIDDEN;
					return TRUE;
				}
			}
			return FALSE;
		}

		case TB_PRESSBUTTON:
		{
			int cmdId = static_cast<int>(wParam);
			BOOL press = LOWORD(lParam);
			for (auto& btn : data.buttons)
			{
				if (btn.idCommand == cmdId)
				{
					if (press)
						btn.fsState |= TBSTATE_PRESSED;
					else
						btn.fsState &= ~TBSTATE_PRESSED;
					return TRUE;
				}
			}
			return FALSE;
		}

		case TB_GETPADDING:
			return MAKELONG(6, 6);
	}

	return 0;
}

// ============================================================
// ReBar Message Handler
// ============================================================

// Additional RB_* constants not in commctrl.h
#ifndef RB_GETBANDBORDERS
#define RB_GETBANDBORDERS (WM_USER + 34)
#endif
#ifndef RB_GETRECT
#define RB_GETRECT        (WM_USER + 9)
#endif
#ifndef RB_HITTEST
#define RB_HITTEST        (WM_USER + 8)
#endif

static LRESULT HandleReBarMessage(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	auto key = reinterpret_cast<uintptr_t>(hWnd);
	auto it = s_reBars.find(key);
	if (it == s_reBars.end())
		return 0;

	auto& data = it->second;

	switch (msg)
	{
		case RB_INSERTBANDW:
		{
			const REBARBANDINFOW* pInfo = reinterpret_cast<const REBARBANDINFOW*>(lParam);
			if (!pInfo)
				return FALSE;

			ReBarBandData band;
			band.fMask = pInfo->fMask;
			band.fStyle = pInfo->fStyle;
			if (pInfo->fMask & RBBIM_CHILD)
				band.hwndChild = pInfo->hwndChild;
			if (pInfo->fMask & RBBIM_SIZE)
				band.cx = pInfo->cx;
			if (pInfo->fMask & RBBIM_CHILDSIZE)
			{
				band.cxMinChild = pInfo->cxMinChild;
				band.cyMinChild = pInfo->cyMinChild;
			}
			if ((pInfo->fMask & RBBIM_TEXT) && pInfo->lpText)
				band.text = pInfo->lpText;

			int index = static_cast<int>(wParam);
			if (index < 0 || index >= static_cast<int>(data.bands.size()))
				data.bands.push_back(band);
			else
				data.bands.insert(data.bands.begin() + index, band);

			return TRUE;
		}

		case RB_DELETEBAND:
		{
			int index = static_cast<int>(wParam);
			if (index < 0 || index >= static_cast<int>(data.bands.size()))
				return FALSE;
			data.bands.erase(data.bands.begin() + index);
			return TRUE;
		}

		case RB_GETBANDCOUNT:
			return static_cast<LRESULT>(data.bands.size());

		case RB_GETROWCOUNT:
			return 1;

		case RB_GETBARHEIGHT:
		{
			int maxH = 0;
			for (auto& band : data.bands)
			{
				if (band.cyMinChild > maxH)
					maxH = band.cyMinChild;
			}
			return maxH > 0 ? maxH : 28;
		}

		case RB_GETROWHEIGHT:
			return 28;

		case RB_SHOWBAND:
		case RB_SIZETORECT:
		case RB_SETBARINFO:
		case RB_GETBARINFO:
		case RB_SETBANDINFOW:
		case RB_GETBANDINFOW:
		case RB_GETBANDBORDERS:
		case RB_GETRECT:
		case RB_IDTOINDEX:
		case RB_HITTEST:
		case RB_MOVEBAND:
			return 0;
	}

	return 0;
}

// ============================================================
// Public Interface: Control Creation
// ============================================================

// Check if a class name is a known common control
bool Win32Controls_IsControlClass(const wchar_t* className)
{
	if (!className)
		return false;

	std::wstring name(className);
	return name == WC_TABCONTROLW ||
	       name == STATUSCLASSNAMEW ||
	       name == TOOLBARCLASSNAMEW ||
	       name == REBARCLASSNAMEW ||
	       name == TOOLTIPS_CLASSW ||
	       name == PROGRESS_CLASSW;
}

// Create native backing view for a common control
// Returns the native view (void* to NSView*), or nullptr if not a control
void* Win32Controls_CreateControl(HWND hWnd, const wchar_t* className,
                                   void* parentView, int x, int y, int w, int h,
                                   DWORD style)
{
	if (!className)
		return nullptr;

	std::wstring name(className);
	auto key = reinterpret_cast<uintptr_t>(hWnd);

	if (name == WC_TABCONTROLW)
	{
		// Create tab control backed by custom Win32TabBarView
		NSView* parent = (__bridge NSView*)parentView;
		CGFloat parentH = parent ? parent.bounds.size.height : h;
		if (h <= 0) h = 28;
		NSRect frame = NSMakeRect(x, parentH - y - h, w, h);

		Win32TabBarView* tabView = [[Win32TabBarView alloc] initWithFrame:frame];
		tabView.hwnd = hWnd;

		if (parent)
			[parent addSubview:tabView];

		// Initialize control data
		s_tabControls[key] = TabControlData{};

		return (__bridge void*)tabView;
	}

	if (name == STATUSCLASSNAMEW)
	{
		NSView* parent = (__bridge NSView*)parentView;
		int statusHeight = 22;
		NSRect frame;
		if (parent)
			frame = NSMakeRect(0, 0, parent.bounds.size.width, statusHeight);
		else
			frame = NSMakeRect(x, y, w > 0 ? w : 400, statusHeight);

		Win32StatusBarView* sbView = [[Win32StatusBarView alloc] initWithFrame:frame];
		sbView.hwnd = hWnd;

		if (parent)
			[parent addSubview:sbView];

		// Initialize control data
		s_statusBars[key] = StatusBarData{};

		return (__bridge void*)sbView;
	}

	if (name == TOOLBARCLASSNAMEW)
	{
		NSView* parent = (__bridge NSView*)parentView;
		CGFloat parentH = parent ? parent.bounds.size.height : h;
		NSRect frame = NSMakeRect(x, parentH - y - h, w, h > 0 ? h : 28);

		NSView* tbView = [[NSView alloc] initWithFrame:frame];
		if (parent)
			[parent addSubview:tbView];

		s_toolBars[key] = ToolBarData{};

		return (__bridge void*)tbView;
	}

	if (name == REBARCLASSNAMEW)
	{
		NSView* parent = (__bridge NSView*)parentView;
		CGFloat parentH = parent ? parent.bounds.size.height : h;
		NSRect frame = NSMakeRect(x, parentH - y - h, w, h > 0 ? h : 28);

		NSView* rbView = [[NSView alloc] initWithFrame:frame];
		if (parent)
			[parent addSubview:rbView];

		s_reBars[key] = ReBarData{};

		return (__bridge void*)rbView;
	}

	if (name == TOOLTIPS_CLASSW || name == PROGRESS_CLASSW)
	{
		// Create a minimal NSView (mostly stubs for these)
		NSView* parent = (__bridge NSView*)parentView;
		NSRect frame = NSMakeRect(x, y, w > 0 ? w : 100, h > 0 ? h : 20);
		NSView* view = [[NSView alloc] initWithFrame:frame];
		if (parent)
			[parent addSubview:view];
		return (__bridge void*)view;
	}

	return nullptr;
}

// Route a message to the appropriate control handler
// Returns true if the message was handled, false if it should go to default processing
bool Win32Controls_HandleMessage(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam, LRESULT* pResult)
{
	auto* info = HandleRegistry::getWindowInfo(hWnd);
	if (!info)
		return false;

	switch (info->controlType)
	{
		case HandleRegistry::ControlType::TabControl:
		{
			// Check if this is a TCM_* message or a generic window message the tab handles
			if ((msg >= TCM_FIRST && msg <= TCM_FIRST + 100) || msg == WM_SIZE)
			{
				*pResult = HandleTabControlMessage(hWnd, msg, wParam, lParam);
				return true;
			}
			break;
		}

		case HandleRegistry::ControlType::StatusBar:
		{
			// SB_* messages are in WM_USER range
			if ((msg >= WM_USER && msg <= WM_USER + 50) || msg == WM_SIZE || msg == WM_GETTEXT)
			{
				*pResult = HandleStatusBarMessage(hWnd, msg, wParam, lParam);
				return true;
			}
			break;
		}

		case HandleRegistry::ControlType::ToolBar:
		{
			// TB_* messages are in WM_USER range
			if (msg >= WM_USER && msg <= WM_USER + 200)
			{
				*pResult = HandleToolBarMessage(hWnd, msg, wParam, lParam);
				return true;
			}
			break;
		}

		case HandleRegistry::ControlType::ReBar:
		{
			if (msg >= WM_USER && msg <= WM_USER + 50)
			{
				*pResult = HandleReBarMessage(hWnd, msg, wParam, lParam);
				return true;
			}
			break;
		}

		default:
			break;
	}

	return false;
}

// Clean up control data when a window is destroyed
void Win32Controls_DestroyControl(HWND hWnd)
{
	auto key = reinterpret_cast<uintptr_t>(hWnd);
	s_tabControls.erase(key);
	s_statusBars.erase(key);
	s_toolBars.erase(key);
	s_reBars.erase(key);
}

// Map class name to ControlType
HandleRegistry::ControlType Win32Controls_GetControlType(const wchar_t* className)
{
	if (!className)
		return HandleRegistry::ControlType::None;

	std::wstring name(className);
	if (name == WC_TABCONTROLW) return HandleRegistry::ControlType::TabControl;
	if (name == STATUSCLASSNAMEW) return HandleRegistry::ControlType::StatusBar;
	if (name == TOOLBARCLASSNAMEW) return HandleRegistry::ControlType::ToolBar;
	if (name == REBARCLASSNAMEW) return HandleRegistry::ControlType::ReBar;
	if (name == WC_LISTVIEWW) return HandleRegistry::ControlType::ListView;
	if (name == WC_TREEVIEWW) return HandleRegistry::ControlType::TreeView;

	return HandleRegistry::ControlType::None;
}

// ============================================================
// ImageList stubs (used by TabBar, ToolBar, etc.)
// ============================================================

struct ImageListData
{
	int cx = 0;
	int cy = 0;
	UINT flags = 0;
	int capacity = 0;
	int count = 0;
};

static std::vector<ImageListData*> s_imageLists;

HIMAGELIST ImageList_Create(int cx, int cy, UINT flags, int cInitial, int cGrow)
{
	auto* data = new ImageListData;
	data->cx = cx;
	data->cy = cy;
	data->flags = flags;
	data->capacity = cInitial;
	data->count = 0;
	s_imageLists.push_back(data);
	return reinterpret_cast<HIMAGELIST>(data);
}

BOOL ImageList_Destroy(HIMAGELIST himl)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	auto it = std::find(s_imageLists.begin(), s_imageLists.end(), data);
	if (it != s_imageLists.end())
	{
		s_imageLists.erase(it);
		delete data;
		return TRUE;
	}
	return FALSE;
}

int ImageList_Add(HIMAGELIST himl, HBITMAP hbmImage, HBITMAP hbmMask)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	if (data)
		return data->count++;
	return -1;
}

int ImageList_AddMasked(HIMAGELIST himl, HBITMAP hbmImage, COLORREF crMask)
{
	return ImageList_Add(himl, hbmImage, nullptr);
}

int ImageList_ReplaceIcon(HIMAGELIST himl, int i, HICON hicon)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	if (!data)
		return -1;
	if (i < 0)
	{
		// Append
		return data->count++;
	}
	return i;
}

BOOL ImageList_Remove(HIMAGELIST himl, int i)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	if (data && i >= 0 && i < data->count)
	{
		--data->count;
		return TRUE;
	}
	if (data && i == -1)
	{
		// Remove all
		data->count = 0;
		return TRUE;
	}
	return FALSE;
}

int ImageList_GetImageCount(HIMAGELIST himl)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	return data ? data->count : 0;
}

BOOL ImageList_GetIconSize(HIMAGELIST himl, int* cx, int* cy)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	if (data)
	{
		if (cx) *cx = data->cx;
		if (cy) *cy = data->cy;
		return TRUE;
	}
	return FALSE;
}

BOOL ImageList_SetIconSize(HIMAGELIST himl, int cx, int cy)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	if (data)
	{
		data->cx = cx;
		data->cy = cy;
		return TRUE;
	}
	return FALSE;
}

BOOL ImageList_Draw(HIMAGELIST himl, int i, HDC hdcDst, int x, int y, UINT fStyle)
{
	return TRUE; // Stub
}

BOOL ImageList_DrawEx(HIMAGELIST himl, int i, HDC hdcDst, int x, int y, int dx, int dy,
                      COLORREF rgbBk, COLORREF rgbFg, UINT fStyle)
{
	return TRUE; // Stub
}

HIMAGELIST ImageList_Duplicate(HIMAGELIST himl)
{
	auto* src = reinterpret_cast<ImageListData*>(himl);
	if (!src)
		return nullptr;
	return ImageList_Create(src->cx, src->cy, src->flags, src->capacity, 0);
}

HICON ImageList_GetIcon(HIMAGELIST himl, int i, UINT flags)
{
	return nullptr;
}

BOOL ImageList_SetImageCount(HIMAGELIST himl, UINT uNewCount)
{
	auto* data = reinterpret_cast<ImageListData*>(himl);
	if (data)
	{
		data->count = static_cast<int>(uNewCount);
		return TRUE;
	}
	return FALSE;
}
