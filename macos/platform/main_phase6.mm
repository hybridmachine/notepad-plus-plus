// Notepad++ macOS Port — Phase 6 Entry Point
// Demonstrates: Real syntax highlighting via Lexilla lexers, code folding
// with margin markers, per-lexer style tables, and fold/unfold commands.
//
// Builds on Phase 6: Regex search, recent files, bookmarks, auto-completion,
// context menus, preferences dialog, and language selection.

#import <Cocoa/Cocoa.h>
#include <set>
#include <algorithm>
#include "windows.h"
#include "commctrl.h"
#include "commdlg.h"
#include "handle_registry.h"
#include "scintilla_bridge.h"
#include "file_monitor_mac.h"
#include "ILexer.h"
#include "Lexilla.h"

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

// Phase 6 command IDs
#define IDM_SEARCH_BOOKMARK_TOGGLE   43010
#define IDM_SEARCH_BOOKMARK_NEXT     43011
#define IDM_SEARCH_BOOKMARK_PREV     43012
#define IDM_SEARCH_BOOKMARK_CLEARALL 43013
#define IDM_EDIT_AUTOCOMPLETE        42030
#define IDM_FILE_RECENT_BASE         41100  // 41100..41109 for 10 recent files
#define IDM_FILE_RECENT_CLEAR        41110
#define IDM_VIEW_PREFERENCES         42050
#define IDM_VIEW_FOLDALL             42060
#define IDM_VIEW_UNFOLDALL           42061
#define IDM_LANG_BASE                44000  // Base for language menu items

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
#define IDC_USE_REGEX        2014

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
	SCI_GETTABWIDTH = 2121,
	SCI_SETCODEPAGE = 2037,
	SCI_STYLECLEARALL = 2050,
	SCI_STYLESETFORE = 2051,
	SCI_STYLESETBOLD = 2053,
	SCI_STYLESETSIZE = 2055,
	SCI_STYLESETFONT = 2056,
	SCI_STYLESETBACK = 2052,
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
	SCI_SETCARETFORE = 2069,
	SCI_SETPROPERTY = 4004,
	SCI_SETKEYWORDS = 4005,
	SCI_SETILEXER = 4033,
	SCI_COLOURISE = 4003,
	SCI_STYLESETITALIC = 2054,
	SCI_TOGGLEFOLD = 2231,
	SCI_FOLDALL = 2662,
	SCI_GETFOLDLEVEL = 2223,
	SCI_SETFOLDFLAGS = 2233,
	SCI_SETAUTOMATICFOLD = 2663,
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

	// Bookmark / marker messages
	SCI_MARKERADD = 2043,
	SCI_MARKERDELETE = 2044,
	SCI_MARKERGET = 2046,
	SCI_MARKERNEXT = 2047,
	SCI_MARKERPREVIOUS = 2048,
	SCI_MARKERDELETEALL = 2045,
	SCI_MARKERDEFINE = 2040,
	SCI_MARKERSETFORE = 2041,
	SCI_MARKERSETBACK = 2042,

	// Auto-complete messages
	SCI_AUTOCSHOW = 2100,
	SCI_AUTOCCANCEL = 2101,
	SCI_AUTOCACTIVE = 2102,
	SCI_AUTOCSETIGNORECASE = 2115,
	SCI_AUTOCSETORDER = 2660,
	SCI_WORDSTARTPOSITION = 2266,
	SCI_GETCHARAT = 2007,
	SCI_GETCURLINE = 2027,
	SCI_POSITIONFROMLINE = 2167,

	// Edit operations
	SCI_UNDO = 2176,
	SCI_REDO = 2011,
	SCI_CUT = 2177,
	SCI_COPY = 2178,
	SCI_PASTE = 2179,
	SCI_SELECTALL = 2013,

	// Style
	SCI_STYLEGETFONT = 2486,
	SCI_STYLEGETSIZE = 2485,
};

// Scintilla search flags
#define SCFIND_MATCHCASE  4
#define SCFIND_WHOLEWORD  2
#define SCFIND_REGEXP     0x00200000
#define SCFIND_POSIX      0x00400000
#define SCFIND_CXX11REGEX 0x00800000

// Bookmark marker
#define BOOKMARK_MARKER  24
#define BOOKMARK_MASK    (1 << BOOKMARK_MARKER)

// Scintilla marker shapes
#define SC_MARK_CIRCLE      0
#define SC_MARK_ROUNDRECT   1
#define SC_MARK_ARROW       2
#define SC_MARK_SMALLRECT   3
#define SC_MARK_SHORTARROW  4
#define SC_MARK_FULLRECT   26
#define SC_MARK_BOOKMARK   31
#define SC_MARK_BOXPLUS          12
#define SC_MARK_BOXMINUS         14
#define SC_MARK_VLINE            9
#define SC_MARK_LCORNER          10
#define SC_MARK_BOXPLUSCONNECTED  13
#define SC_MARK_BOXMINUSCONNECTED 15
#define SC_MARK_TCORNER          11

// Fold margin constants
#define SC_MARKNUM_FOLDEREND      25
#define SC_MARKNUM_FOLDEROPENMID  26
#define SC_MARKNUM_FOLDERMIDTAIL  27
#define SC_MARKNUM_FOLDERTAIL     28
#define SC_MARKNUM_FOLDERSUB      29
#define SC_MARKNUM_FOLDER         30
#define SC_MARKNUM_FOLDEROPEN     31
#define SC_MASK_FOLDERS           0xFE000000
#define SC_FOLDACTION_CONTRACT    0
#define SC_FOLDACTION_EXPAND      1
#define SC_FOLDACTION_TOGGLE      2
#define SC_FOLDLEVELHEADERFLAG    0x2000
#define SC_AUTOMATICFOLD_CLICK    0x0004

// ============================================================
// Per-lexer syntax style definitions
// ============================================================

struct StyleDef
{
	int styleId;
	int lightFore;  // BGR color
	int darkFore;   // BGR color
	bool bold;
	bool italic;
};

struct LexerStyles
{
	const char* lexerName;
	const StyleDef* styles;
	int numStyles;
};

// C/C++ lexer styles (SCE_C_*)
static const StyleDef s_cppStyles[] = {
	{1,  0x008000, 0x6A9955, false, false},  // COMMENT
	{2,  0x008000, 0x6A9955, false, false},  // COMMENTLINE
	{3,  0x008000, 0x6A9955, false, true},   // COMMENTDOC
	{4,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{5,  0xFF0000, 0x569CD6, true,  false},  // WORD (keywords)
	{6,  0x800080, 0xCE9178, false, false},  // STRING
	{7,  0x800080, 0xCE9178, false, false},  // CHARACTER
	{9,  0x808080, 0xC586C0, false, false},  // PREPROCESSOR
	{10, 0x000000, 0xD4D4D4, false, false},  // OPERATOR
	{16, 0x990000, 0x4EC9B0, false, false},  // WORD2 (types)
};

// Objective-C uses same style IDs as C++
static const StyleDef s_objcStyles[] = {
	{1,  0x008000, 0x6A9955, false, false},
	{2,  0x008000, 0x6A9955, false, false},
	{3,  0x008000, 0x6A9955, false, true},
	{4,  0x008080, 0xB5CEA8, false, false},
	{5,  0xFF0000, 0x569CD6, true,  false},
	{6,  0x800080, 0xCE9178, false, false},
	{7,  0x800080, 0xCE9178, false, false},
	{9,  0x808080, 0xC586C0, false, false},
	{10, 0x000000, 0xD4D4D4, false, false},
	{16, 0x990000, 0x4EC9B0, false, false},
};

// Python lexer styles (SCE_P_*)
static const StyleDef s_pythonStyles[] = {
	{1,  0x008000, 0x6A9955, false, false},  // COMMENTLINE
	{2,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{3,  0x800080, 0xCE9178, false, false},  // STRING
	{4,  0x800080, 0xCE9178, false, false},  // CHARACTER
	{5,  0xFF0000, 0x569CD6, true,  false},  // WORD
	{6,  0x800080, 0xCE9178, false, false},  // TRIPLE
	{7,  0x800080, 0xCE9178, false, false},  // TRIPLEDOUBLE
	{8,  0x990000, 0x4EC9B0, false, false},  // CLASSNAME
	{9,  0x880000, 0xDCDCAA, false, false},  // DEFNAME
	{10, 0x000000, 0xD4D4D4, false, false},  // OPERATOR
	{14, 0x990000, 0x4EC9B0, false, false},  // WORD2 (builtins)
	{15, 0xCC6600, 0xDCDCAA, false, true},   // DECORATOR
};

// HTML/Hypertext lexer styles (SCE_H_*)
static const StyleDef s_htmlStyles[] = {
	{1,  0x800000, 0x569CD6, true,  false},  // TAG
	{2,  0x800000, 0x569CD6, false, false},  // TAGUNKNOWN
	{3,  0xFF0000, 0x9CDCFE, false, false},  // ATTRIBUTE
	{5,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{6,  0x800080, 0xCE9178, false, false},  // DOUBLESTRING
	{7,  0x800080, 0xCE9178, false, false},  // SINGLESTRING
	{9,  0x008000, 0x6A9955, false, false},  // COMMENT
};

// CSS lexer styles (SCE_CSS_*)
static const StyleDef s_cssStyles[] = {
	{1,  0x800000, 0x569CD6, true,  false},  // TAG
	{2,  0x990000, 0xD7BA7D, false, false},  // CLASS
	{4,  0x990000, 0xD7BA7D, false, false},  // ID
	{5,  0x000000, 0xD4D4D4, false, false},  // OPERATOR
	{7,  0x008080, 0xCE9178, false, false},  // VALUE
	{9,  0x008000, 0x6A9955, false, false},  // COMMENT
	{13, 0xFF0000, 0x569CD6, true,  false},  // DIRECTIVE
};

// JSON lexer styles (SCE_JSON_*)
static const StyleDef s_jsonStyles[] = {
	{1,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{2,  0x800080, 0xCE9178, false, false},  // STRING
	{4,  0x990000, 0x9CDCFE, false, false},  // PROPERTYNAME
	{8,  0xFF0000, 0x569CD6, true,  false},  // KEYWORD (true/false/null)
	{9,  0x008080, 0xB5CEA8, false, false},  // LDKEYWORD
	{5,  0x000000, 0xD4D4D4, false, false},  // ESCAPESEQUENCE
};

// SQL lexer styles (SCE_SQL_*)
static const StyleDef s_sqlStyles[] = {
	{1,  0x008000, 0x6A9955, false, false},  // COMMENT
	{2,  0x008000, 0x6A9955, false, false},  // COMMENTLINE
	{4,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{5,  0xFF0000, 0x569CD6, true,  false},  // WORD (keywords)
	{6,  0x800080, 0xCE9178, false, false},  // STRING
	{7,  0x000000, 0xD4D4D4, false, false},  // OPERATOR
	{8,  0x990000, 0x4EC9B0, false, false},  // WORD2 (types)
};

// Bash/Shell lexer styles (SCE_SH_*)
static const StyleDef s_bashStyles[] = {
	{2,  0x008000, 0x6A9955, false, false},  // COMMENTLINE
	{3,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{4,  0xFF0000, 0x569CD6, true,  false},  // WORD (keywords)
	{5,  0x800080, 0xCE9178, false, false},  // STRING (double-quoted)
	{6,  0x800080, 0xCE9178, false, false},  // STRING (single-quoted)
	{7,  0x000000, 0xD4D4D4, false, false},  // OPERATOR
	{8,  0x990000, 0x9CDCFE, false, false},  // SCALAR ($var)
	{9,  0xCC6600, 0xDCDCAA, false, false},  // PARAM
};

// Rust lexer styles (SCE_RUST_*)
static const StyleDef s_rustStyles[] = {
	{1,  0x008000, 0x6A9955, false, false},  // COMMENTBLOCK
	{2,  0x008000, 0x6A9955, false, false},  // COMMENTLINE
	{3,  0x008000, 0x6A9955, false, true},   // COMMENTBLOCKDOC
	{4,  0x008000, 0x6A9955, false, true},   // COMMENTLINEDOC
	{5,  0xFF0000, 0x569CD6, true,  false},  // WORD (keywords)
	{6,  0x800080, 0xCE9178, false, false},  // STRING
	{8,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{10, 0x000000, 0xD4D4D4, false, false},  // OPERATOR
	{12, 0x800080, 0xCE9178, false, false},  // BYTESTRING
	{14, 0x990000, 0x4EC9B0, false, false},  // WORD2 (types)
	{16, 0xCC6600, 0xDCDCAA, false, false},  // LIFETIME
};

// Markdown lexer styles (SCE_MARKDOWN_*)
static const StyleDef s_markdownStyles[] = {
	{4,  0x000000, 0xD4D4D4, true,  false},  // STRONG1
	{5,  0x000000, 0xD4D4D4, true,  false},  // STRONG2
	{6,  0x000000, 0xD4D4D4, false, true},   // EM1
	{7,  0x000000, 0xD4D4D4, false, true},   // EM2
	{8,  0x800000, 0x569CD6, true,  false},  // HEADER1
	{9,  0x800000, 0x569CD6, true,  false},  // HEADER2
	{10, 0x800000, 0x569CD6, true,  false},  // HEADER3
	{11, 0x800000, 0x569CD6, true,  false},  // HEADER4
	{12, 0x800000, 0x569CD6, true,  false},  // HEADER5
	{19, 0x808080, 0xCE9178, false, false},  // CODE
	{20, 0x808080, 0xCE9178, false, false},  // CODE2
	{21, 0x0000FF, 0x569CD6, false, false},  // LINK
};

// XML lexer styles (same IDs as HTML/SCE_H_*)
static const StyleDef s_xmlStyles[] = {
	{1,  0x800000, 0x569CD6, true,  false},  // TAG
	{3,  0xFF0000, 0x9CDCFE, false, false},  // ATTRIBUTE
	{5,  0x008080, 0xB5CEA8, false, false},  // NUMBER
	{6,  0x800080, 0xCE9178, false, false},  // DOUBLESTRING
	{7,  0x800080, 0xCE9178, false, false},  // SINGLESTRING
	{9,  0x008000, 0x6A9955, false, false},  // COMMENT
};

// Lookup table
static const LexerStyles s_allLexerStyles[] = {
	{"cpp",        s_cppStyles,      sizeof(s_cppStyles) / sizeof(s_cppStyles[0])},
	{"objc",       s_objcStyles,     sizeof(s_objcStyles) / sizeof(s_objcStyles[0])},
	{"python",     s_pythonStyles,   sizeof(s_pythonStyles) / sizeof(s_pythonStyles[0])},
	{"hypertext",  s_htmlStyles,     sizeof(s_htmlStyles) / sizeof(s_htmlStyles[0])},
	{"css",        s_cssStyles,      sizeof(s_cssStyles) / sizeof(s_cssStyles[0])},
	{"json",       s_jsonStyles,     sizeof(s_jsonStyles) / sizeof(s_jsonStyles[0])},
	{"sql",        s_sqlStyles,      sizeof(s_sqlStyles) / sizeof(s_sqlStyles[0])},
	{"bash",       s_bashStyles,     sizeof(s_bashStyles) / sizeof(s_bashStyles[0])},
	{"rust",       s_rustStyles,     sizeof(s_rustStyles) / sizeof(s_rustStyles[0])},
	{"markdown",   s_markdownStyles, sizeof(s_markdownStyles) / sizeof(s_markdownStyles[0])},
	{"xml",        s_xmlStyles,      sizeof(s_xmlStyles) / sizeof(s_xmlStyles[0])},
};

static const LexerStyles* findLexerStyles(const char* lexerName)
{
	if (!lexerName) return nullptr;
	for (const auto& ls : s_allLexerStyles)
	{
		if (strcmp(ls.lexerName, lexerName) == 0)
			return &ls;
	}
	return nullptr;
}

// ============================================================
// Language definition
// ============================================================
struct LangDef
{
	const char* name;          // Display name
	const char* lexerName;     // Scintilla lexer name
	const char* keywords;      // Primary keywords (set 0)
	const char* keywords2;     // Secondary keywords (set 1) - types, builtins
	int menuId;                // Menu command ID
};

static const LangDef g_languages[] = {
	{"Normal Text", "null", "", "", IDM_LANG_BASE + 0},
	{"C", "cpp",
	 "auto break case char const continue default do double else enum extern float for goto "
	 "if int long register return short signed sizeof static struct switch typedef union "
	 "unsigned void volatile while",
	 "int long double float char void short unsigned signed size_t ptrdiff_t bool "
	 "int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE",
	 IDM_LANG_BASE + 1},
	{"C++", "cpp",
	 "alignas alignof and and_eq asm auto bitand bitor bool break case catch char char8_t "
	 "char16_t char32_t class compl concept const consteval constexpr constinit const_cast "
	 "continue co_await co_return co_yield decltype default delete do double dynamic_cast "
	 "else enum explicit export extern false float for friend goto if import inline int long "
	 "module mutable namespace new noexcept not not_eq nullptr operator or or_eq private "
	 "protected public register reinterpret_cast requires return short signed sizeof static "
	 "static_assert static_cast struct switch template this thread_local throw true try "
	 "typedef typeid typename union unsigned using virtual void volatile wchar_t while xor xor_eq "
	 "override final include define ifdef ifndef endif pragma",
	 "string wstring vector map set unordered_map unordered_set list deque array "
	 "unique_ptr shared_ptr weak_ptr optional variant any tuple pair size_t "
	 "int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t ptrdiff_t",
	 IDM_LANG_BASE + 2},
	{"Java", "cpp",
	 "abstract assert boolean break byte case catch char class const continue default do double "
	 "else enum extends final finally float for goto if implements import instanceof int "
	 "interface long native new package private protected public return short static strictfp "
	 "super switch synchronized this throw throws transient try void volatile while",
	 "String Integer Long Double Float Boolean Byte Short Character Object Class "
	 "List ArrayList Map HashMap Set HashSet Array Collections Arrays",
	 IDM_LANG_BASE + 3},
	{"Python", "python",
	 "False None True and as assert async await break class continue def del elif else except "
	 "finally for from global if import in is lambda nonlocal not or pass raise return try "
	 "while with yield",
	 "print len range list dict str int float bool type input open isinstance issubclass "
	 "hasattr getattr setattr delattr callable super object enumerate zip map filter sorted "
	 "reversed min max sum abs any all dir vars repr format id hash iter next",
	 IDM_LANG_BASE + 4},
	{"JavaScript", "cpp",
	 "abstract arguments async await boolean break byte case catch char class const continue "
	 "debugger default delete do double else enum eval export extends false final finally float "
	 "for from function goto if implements import in instanceof int interface let long native "
	 "new null of package private protected public return short static super switch synchronized "
	 "this throw throws transient true try typeof undefined var void volatile while with yield",
	 "console document window Math Array Object Promise Map Set WeakMap WeakSet JSON "
	 "Date RegExp Error TypeError RangeError Symbol Proxy Reflect Number String Boolean",
	 IDM_LANG_BASE + 5},
	{"HTML", "hypertext",
	 "a abbr address area article aside audio b base bdi bdo blockquote body br button canvas "
	 "caption cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed "
	 "fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hr html i iframe "
	 "img input ins kbd label legend li link main map mark meta meter nav noscript object ol "
	 "optgroup option output p param picture pre progress q rp rt ruby s samp script section "
	 "select small source span strong style sub summary sup table tbody td template textarea "
	 "tfoot th thead time title tr track u ul var video wbr",
	 "",
	 IDM_LANG_BASE + 6},
	{"CSS", "css",
	 "color background font margin padding border width height display position top left right "
	 "bottom float clear overflow visibility z-index text-align text-decoration line-height "
	 "font-size font-weight font-family content cursor opacity flex grid transition transform "
	 "animation box-shadow border-radius min-width max-width min-height max-height",
	 "",
	 IDM_LANG_BASE + 7},
	{"XML", "xml",
	 "",
	 "",
	 IDM_LANG_BASE + 8},
	{"JSON", "json",
	 "true false null",
	 "",
	 IDM_LANG_BASE + 9},
	{"Markdown", "markdown",
	 "",
	 "",
	 IDM_LANG_BASE + 10},
	{"SQL", "sql",
	 "select from where insert into values update set delete create table alter drop index "
	 "join inner outer left right on and or not null is in between like as order by group "
	 "having count sum avg min max distinct union all exists case when then else end primary "
	 "key foreign references constraint default check unique grant revoke",
	 "integer varchar text boolean date timestamp numeric decimal char real serial "
	 "bigint smallint float double blob clob nvarchar nchar",
	 IDM_LANG_BASE + 11},
	{"Shell", "bash",
	 "if then else elif fi case esac for while until do done in function select time coproc "
	 "echo printf read declare local export readonly typeset shift exit return break continue "
	 "eval exec source test true false",
	 "",
	 IDM_LANG_BASE + 12},
	{"Rust", "rust",
	 "as async await break const continue crate dyn else enum extern false fn for if impl "
	 "in let loop match mod move mut pub ref return self Self static struct super trait true "
	 "type unsafe use where while",
	 "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char "
	 "String Vec Box Rc Arc Option Result Some None Ok Err HashMap HashSet",
	 IDM_LANG_BASE + 13},
	{"Go", "cpp",
	 "break case chan const continue default defer else fallthrough for func go goto if import "
	 "interface map package range return select struct switch type var true false nil",
	 "int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr "
	 "float32 float64 complex64 complex128 byte rune string bool error",
	 IDM_LANG_BASE + 14},
	{"Objective-C", "objc",
	 "auto break case char const continue default do double else enum extern float for goto "
	 "if int long register return short signed sizeof static struct switch typedef union "
	 "unsigned void volatile while id self super nil Nil YES NO "
	 "@interface @implementation @end @protocol @class @selector @property @synthesize "
	 "@dynamic @try @catch @finally @throw @autoreleasepool @encode @synchronized "
	 "instancetype nullable nonnull",
	 "NSObject NSString NSArray NSDictionary NSMutableArray NSMutableDictionary NSNumber "
	 "NSData NSDate NSURL NSError NSSet NSMutableSet NSInteger NSUInteger CGFloat BOOL",
	 IDM_LANG_BASE + 15},
	{"Swift", "cpp",
	 "actor any associatedtype async await break case catch class continue convenience default "
	 "defer deinit do else enum extension fallthrough false fileprivate final for func get "
	 "guard if import in indirect infix init inout internal is lazy let mutating nil nonisolated "
	 "nonmutating open operator optional override postfix precedencegroup prefix private protocol "
	 "public repeat required rethrows return self Self set some static struct subscript super "
	 "switch Task throw throws true try typealias unowned var weak where while",
	 "Int Double Float String Bool Character Array Dictionary Set Optional Result "
	 "Any AnyObject Void Never Error Codable Equatable Hashable Comparable",
	 IDM_LANG_BASE + 16},
};
static const int g_numLanguages = sizeof(g_languages) / sizeof(g_languages[0]);

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
	int languageIndex = 2; // Default: C++
	std::vector<int> bookmarkedLines; // Persisted across tab switches
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
static bool g_useRegex = false;
static bool g_findMode = true; // true = Find, false = Replace

// Recent files
static const int MAX_RECENT_FILES = 10;
static std::vector<std::wstring> g_recentFiles;
static HMENU g_recentMenu = nullptr;

// Preferences state
static int g_fontSize = 13;
static int g_tabWidth = 4;
static std::string g_fontName = "Menlo";

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

static std::wstring NSStringToWide(NSString* str)
{
	if (!str) return L"";
	NSData* data = [str dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
	if (!data || data.length == 0) return L"";
	return std::wstring(reinterpret_cast<const wchar_t*>(data.bytes),
	                    data.length / sizeof(wchar_t));
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

	// Save bookmarked lines
	doc.bookmarkedLines.clear();
	intptr_t lineCount = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLINECOUNT, 0, 0);
	intptr_t line = 0;
	while (line < lineCount)
	{
		line = ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERNEXT, line, BOOKMARK_MASK);
		if (line < 0) break;
		doc.bookmarkedLines.push_back(static_cast<int>(line));
		++line;
	}
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

	// Restore bookmarks
	for (int bkLine : doc.bookmarkedLines)
		ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERADD, bkLine, BOOKMARK_MARKER);
}

// ============================================================
// Language / lexer switching
// ============================================================
static void applyLanguage(int langIndex);

// Forward declarations
static void applyAppearance();

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
	applyLanguage(g_documents[tabIndex].languageIndex);

	const auto& doc = g_documents[tabIndex];
	NSString* title = WideToNSString(doc.title.c_str());
	[g_mainWindow setTitle:[NSString stringWithFormat:@"Notepad++ — %@", title]];
}

static int addNewTab(const std::wstring& title, const std::string& content,
                      const std::wstring& filePath = L"", int langIndex = 2)
{
	saveScintillaState();

	DocumentData doc;
	doc.title = title;
	doc.content = content;
	doc.filePath = filePath;
	doc.languageIndex = langIndex;
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

	applyLanguage(langIndex);

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

	if (tabIndex < g_activeTab)
		--g_activeTab;
	else if (tabIndex == g_activeTab)
	{
		if (g_activeTab >= static_cast<int>(g_documents.size()))
			g_activeTab = static_cast<int>(g_documents.size()) - 1;
	}

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

	// Show language name
	const char* langName = "Normal Text";
	if (g_activeTab >= 0 && g_activeTab < static_cast<int>(g_documents.size()))
	{
		int langIdx = g_documents[g_activeTab].languageIndex;
		if (langIdx >= 0 && langIdx < g_numLanguages)
			langName = g_languages[langIdx].name;
	}
	NSString* nsLang = [NSString stringWithUTF8String:langName];
	std::wstring wLang = NSStringToWide(nsLang);
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 2, reinterpret_cast<LPARAM>(wLang.c_str()));

	swprintf(buf, 128, L"Doc %d/%d", g_activeTab + 1, (int)g_documents.size());
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 3, reinterpret_cast<LPARAM>(buf));
}

// ============================================================
// Recent files management
// ============================================================
static void addRecentFile(const std::wstring& path)
{
	// Remove if already in list
	auto it = std::find(g_recentFiles.begin(), g_recentFiles.end(), path);
	if (it != g_recentFiles.end())
		g_recentFiles.erase(it);

	// Add to front
	g_recentFiles.insert(g_recentFiles.begin(), path);

	// Trim to max
	if (static_cast<int>(g_recentFiles.size()) > MAX_RECENT_FILES)
		g_recentFiles.resize(MAX_RECENT_FILES);
}

static void rebuildRecentMenu()
{
	if (!g_recentMenu) return;

	// Remove all items from the recent menu
	// We use the Win32 API: delete items from position 0 repeatedly
	int itemCount = GetMenuItemCount(g_recentMenu);
	for (int i = itemCount - 1; i >= 0; --i)
		DeleteMenu(g_recentMenu, i, MF_BYPOSITION);

	if (g_recentFiles.empty())
	{
		AppendMenuW(g_recentMenu, MF_STRING | MF_GRAYED, 0, L"(No recent files)");
		return;
	}

	for (int i = 0; i < static_cast<int>(g_recentFiles.size()); ++i)
	{
		// Show just the filename with a number prefix
		std::wstring display = g_recentFiles[i];
		size_t lastSlash = display.rfind(L'/');
		if (lastSlash != std::wstring::npos)
			display = display.substr(lastSlash + 1);

		wchar_t label[300];
		swprintf(label, 300, L"&%d %ls", i + 1, display.c_str());
		AppendMenuW(g_recentMenu, MF_STRING, IDM_FILE_RECENT_BASE + i, label);
	}

	AppendMenuW(g_recentMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(g_recentMenu, MF_STRING, IDM_FILE_RECENT_CLEAR, L"Clear Recent Files List");
}

// ============================================================
// Find/Replace operations using Scintilla
// ============================================================

static void updateFindStatus(const wchar_t* msg)
{
	if (g_findDlgHwnd)
		SetDlgItemTextW(g_findDlgHwnd, IDC_FIND_STATUS, msg);
}

static int buildSearchFlags()
{
	int flags = 0;
	if (g_matchCase) flags |= SCFIND_MATCHCASE;
	if (g_wholeWord) flags |= SCFIND_WHOLEWORD;
	if (g_useRegex)  flags |= SCFIND_REGEXP | SCFIND_CXX11REGEX;
	return flags;
}

static bool doFindNext(bool forward)
{
	if (!g_scintillaView || g_findText.empty()) return false;

	NSString* nsFind = WideToNSString(g_findText.c_str());
	const char* utf8Find = [nsFind UTF8String];

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEARCHFLAGS, buildSearchFlags(), 0);

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
		// Advance past zero-length matches to avoid infinite Find Next loop
		if (targetEnd == pos && pos < docLen)
			targetEnd = pos + 1;
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
			if (targetEnd == pos && pos < docLen)
				targetEnd = pos + 1;
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEL, pos, targetEnd);
			ScintillaBridge_sendMessage(g_scintillaView, SCI_SCROLLCARET, 0, 0);
			updateFindStatus(L"Wrapped around");
			return true;
		}
	}

	if (g_useRegex)
		updateFindStatus(L"Not found (check regex syntax)");
	else
		updateFindStatus(L"Not found");
	return false;
}

static int doCount()
{
	if (!g_scintillaView || g_findText.empty()) return 0;

	NSString* nsFind = WideToNSString(g_findText.c_str());
	const char* utf8Find = [nsFind UTF8String];

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEARCHFLAGS, buildSearchFlags(), 0);

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
		intptr_t targetEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTARGETEND, 0, 0);
		if (targetEnd <= pos)
		{
			// Zero-length match: advance by 1 to continue counting
			if (pos < docLen)
			{
				searchStart = pos + 1;
				continue;
			}
			break;
		}
		searchStart = targetEnd;
	}

	wchar_t buf[64];
	swprintf(buf, 64, L"%d matches found", count);
	updateFindStatus(buf);
	return count;
}

static void doReplaceOne()
{
	if (!g_scintillaView) return;

	intptr_t selStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONSTART, 0, 0);
	intptr_t selEnd = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETSELECTIONEND, 0, 0);

	if (selStart == selEnd)
	{
		doFindNext(true);
		return;
	}

	NSString* nsReplace = WideToNSString(g_replaceText.c_str());
	const char* utf8Replace = [nsReplace UTF8String];

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETSTART, selStart, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTARGETEND, selEnd, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_REPLACETARGET,
	                            strlen(utf8Replace), (intptr_t)utf8Replace);

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

	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETSEARCHFLAGS, buildSearchFlags(), 0);

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
		// Safety for zero-length replacements: advance at least 1
		if (searchStart <= pos)
		{
			if (searchStart < docLen)
				++searchStart;
			else
				break;
		}
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
	g_useRegex  = (IsDlgButtonChecked(g_findDlgHwnd, IDC_USE_REGEX) == BST_CHECKED);
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

			int dlgHeight = replaceMode ? 270 : 210;
			NSRect contentRect = [win contentRectForFrameRect:win.frame];
			CGFloat heightDiff = dlgHeight - contentRect.size.height;
			NSRect newFrame = win.frame;
			newFrame.origin.y -= heightDiff;
			newFrame.size.height += heightDiff;
			[win setFrame:newFrame display:YES];

			int dlgWidth = 450;
			int cbY = replaceMode ? 75 : 45;
			int regexY = replaceMode ? 100 : 70;
			int btnY = replaceMode ? 135 : 100;
			int rBtnY = 170;
			int statusY = replaceMode ? 240 : 150;
			int btnW = 90;
			int btnH = 28;
			int btnGap = 8;

			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_LABEL), 15, 15, 80, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_EDIT), 100, 12, 230, 24, TRUE);

			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_LABEL), 15, 45, 80, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_EDIT), 100, 42, 230, 24, TRUE);

			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_MATCH_CASE), 15, cbY, 120, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_WHOLE_WORD), 145, cbY, 120, 20, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_USE_REGEX), 15, regexY, 160, 20, TRUE);

			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_NEXT), 15, btnY, btnW, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_PREV), 15 + btnW + btnGap, btnY, btnW, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_COUNT), 15 + 2 * (btnW + btnGap), btnY, 70, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_CLOSE), dlgWidth - 85, btnY, 70, btnH, TRUE);

			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ONE), 15, rBtnY, btnW, btnH, TRUE);
			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ALL), 15 + btnW + btnGap, rBtnY, btnW + 10, btnH, TRUE);

			MoveWindow(GetDlgItem(g_findDlgHwnd, IDC_FIND_STATUS), 15, statusY, dlgWidth - 30, 20, TRUE);

			ShowWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_EDIT), replaceMode ? SW_SHOW : SW_HIDE);
			ShowWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_LABEL), replaceMode ? SW_SHOW : SW_HIDE);
			ShowWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ONE), replaceMode ? SW_SHOW : SW_HIDE);
			ShowWindow(GetDlgItem(g_findDlgHwnd, IDC_REPLACE_ALL), replaceMode ? SW_SHOW : SW_HIDE);

			[win setTitle:replaceMode ? @"Replace" : @"Find"];
			[win makeKeyAndOrderFront:nil];
		}
		return;
	}

	int dlgWidth = 450;
	int dlgHeight = replaceMode ? 270 : 210;

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

	HandleRegistry::WindowInfo dlgInfo;
	dlgInfo.className = L"#32770";
	dlgInfo.windowName = replaceMode ? L"Replace" : L"Find";
	dlgInfo.style = WS_POPUP | WS_CAPTION;
	dlgInfo.parent = g_mainHwnd;
	dlgInfo.nativeWindow = (__bridge void*)panel;
	dlgInfo.nativeView = (__bridge void*)[panel contentView];

	g_findDlgHwnd = HandleRegistry::createWindow(dlgInfo);

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
	CreateWindowExW(0, L"Static", L"Replace:",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | SS_LEFT,
		15, 45, 80, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_LABEL), nullptr, nullptr);

	// Replace text field
	CreateWindowExW(0, L"Edit", L"",
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

	// Regex checkbox (new in Phase 6)
	int regexY = replaceMode ? 100 : 70;
	CreateWindowExW(0, L"Button", L"Regular expression",
		WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
		15, regexY, 160, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_USE_REGEX), nullptr, nullptr);

	// Buttons row
	int btnY = replaceMode ? 135 : 100;
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
	int rBtnY = 170;
	CreateWindowExW(0, L"Button", L"Replace",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | BS_PUSHBUTTON,
		15, rBtnY, btnW, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_ONE), nullptr, nullptr);

	CreateWindowExW(0, L"Button", L"Replace All",
		WS_CHILD | (replaceMode ? WS_VISIBLE : 0) | BS_PUSHBUTTON,
		15 + btnW + btnGap, rBtnY, btnW + 10, btnH,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_REPLACE_ALL), nullptr, nullptr);

	// Status label at bottom
	int statusY = replaceMode ? 240 : 150;
	CreateWindowExW(0, L"Static", L"",
		WS_CHILD | WS_VISIBLE | SS_LEFT,
		15, statusY, dlgWidth - 30, 20,
		g_findDlgHwnd, reinterpret_cast<HMENU>(IDC_FIND_STATUS), nullptr, nullptr);

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
// Bookmarks (Scintilla marker-based)
// ============================================================

static void toggleBookmark()
{
	if (!g_scintillaView) return;

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t line = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, pos, 0);

	intptr_t markers = ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERGET, line, 0);
	if (markers & BOOKMARK_MASK)
		ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERDELETE, line, BOOKMARK_MARKER);
	else
		ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERADD, line, BOOKMARK_MARKER);
}

static void nextBookmark()
{
	if (!g_scintillaView) return;

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t curLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, pos, 0);

	intptr_t nextLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERNEXT, curLine + 1, BOOKMARK_MASK);
	if (nextLine < 0)
	{
		// Wrap around
		nextLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERNEXT, 0, BOOKMARK_MASK);
	}

	if (nextLine >= 0)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOLINE, nextLine, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SCROLLCARET, 0, 0);
	}
}

static void prevBookmark()
{
	if (!g_scintillaView) return;

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t curLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_LINEFROMPOSITION, pos, 0);

	intptr_t prevLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERPREVIOUS, curLine - 1, BOOKMARK_MASK);
	if (prevLine < 0)
	{
		// Wrap around from end
		intptr_t lineCount = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLINECOUNT, 0, 0);
		prevLine = ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERPREVIOUS, lineCount - 1, BOOKMARK_MASK);
	}

	if (prevLine >= 0)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_GOTOLINE, prevLine, 0);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SCROLLCARET, 0, 0);
	}
}

static void clearAllBookmarks()
{
	if (!g_scintillaView) return;
	ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERDELETEALL, BOOKMARK_MARKER, 0);
}

// ============================================================
// Auto-completion (word completion)
// ============================================================

static void showAutoComplete()
{
	if (!g_scintillaView) return;

	intptr_t pos = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCURRENTPOS, 0, 0);
	intptr_t wordStart = ScintillaBridge_sendMessage(g_scintillaView, SCI_WORDSTARTPOSITION, pos, 1);
	intptr_t wordLen = pos - wordStart;

	if (wordLen < 1) return;

	// Get the partial word
	char partial[256] = {};
	for (intptr_t i = 0; i < wordLen && i < 255; ++i)
		partial[i] = static_cast<char>(ScintillaBridge_sendMessage(g_scintillaView, SCI_GETCHARAT, wordStart + i, 0));
	partial[wordLen] = '\0';

	// Collect all words in the document that match the prefix
	intptr_t docLen = ScintillaBridge_sendMessage(g_scintillaView, SCI_GETLENGTH, 0, 0);
	if (docLen <= 0) return;

	std::string docText;
	docText.resize(docLen + 1);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_GETTEXT, docLen + 1, (intptr_t)docText.data());

	// Extract unique words
	std::set<std::string> words;
	std::string currentWord;
	for (intptr_t i = 0; i < docLen; ++i)
	{
		unsigned char ch = static_cast<unsigned char>(docText[i]);
		if (isalnum(ch) || ch == '_')
		{
			currentWord += ch;
		}
		else
		{
			if (!currentWord.empty() && currentWord.length() >= 3)
				words.insert(currentWord);
			currentWord.clear();
		}
	}
	if (!currentWord.empty() && currentWord.length() >= 3)
		words.insert(currentWord);

	// Filter words that start with the partial text (case-insensitive prefix match)
	std::string partialLower(partial);
	std::transform(partialLower.begin(), partialLower.end(), partialLower.begin(),
	               [](unsigned char c){ return std::tolower(c); });

	std::vector<std::string> matches;
	for (const auto& w : words)
	{
		if (static_cast<intptr_t>(w.length()) <= wordLen) continue;
		// Case-insensitive prefix compare
		std::string wLower = w.substr(0, wordLen);
		std::transform(wLower.begin(), wLower.end(), wLower.begin(),
		               [](unsigned char c){ return std::tolower(c); });
		if (wLower == partialLower)
			matches.push_back(w);
	}

	if (matches.empty()) return;

	// Build space-separated list (Scintilla expects this)
	std::string wordList;
	for (size_t i = 0; i < matches.size(); ++i)
	{
		if (i > 0) wordList += ' ';
		wordList += matches[i];
	}

	ScintillaBridge_sendMessage(g_scintillaView, SCI_AUTOCSETIGNORECASE, 1, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_AUTOCSETORDER, 1, 0); // SC_ORDER_PERFORMSORT
	ScintillaBridge_sendMessage(g_scintillaView, SCI_AUTOCSHOW, wordLen, (intptr_t)wordList.c_str());
}

// ============================================================
// Context menu
// ============================================================

static void showContextMenu(NSPoint screenPoint)
{
	NSMenu* contextMenu = [[NSMenu alloc] initWithTitle:@"Context"];

	NSMenuItem* undoItem = [[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(performContextAction:) keyEquivalent:@""];
	undoItem.tag = IDM_EDIT_UNDO;

	NSMenuItem* redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(performContextAction:) keyEquivalent:@""];
	redoItem.tag = IDM_EDIT_REDO;

	NSMenuItem* cutItem = [[NSMenuItem alloc] initWithTitle:@"Cut" action:@selector(performContextAction:) keyEquivalent:@""];
	cutItem.tag = IDM_EDIT_CUT;

	NSMenuItem* copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(performContextAction:) keyEquivalent:@""];
	copyItem.tag = IDM_EDIT_COPY;

	NSMenuItem* pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(performContextAction:) keyEquivalent:@""];
	pasteItem.tag = IDM_EDIT_PASTE;

	NSMenuItem* selectAllItem = [[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(performContextAction:) keyEquivalent:@""];
	selectAllItem.tag = IDM_EDIT_SELECTALL;

	NSMenuItem* bookmarkItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Bookmark" action:@selector(performContextAction:) keyEquivalent:@""];
	bookmarkItem.tag = IDM_SEARCH_BOOKMARK_TOGGLE;

	[contextMenu addItem:undoItem];
	[contextMenu addItem:redoItem];
	[contextMenu addItem:[NSMenuItem separatorItem]];
	[contextMenu addItem:cutItem];
	[contextMenu addItem:copyItem];
	[contextMenu addItem:pasteItem];
	[contextMenu addItem:[NSMenuItem separatorItem]];
	[contextMenu addItem:selectAllItem];
	[contextMenu addItem:[NSMenuItem separatorItem]];
	[contextMenu addItem:bookmarkItem];

	[NSMenu popUpContextMenu:contextMenu withEvent:[NSApp currentEvent] forView:g_mainWindow.contentView];
}

// ============================================================
// Preferences dialog (modal)
// ============================================================

static void showPreferencesDlg()
{
	@autoreleasepool {
		NSPanel* panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 240)
		                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
		                                    backing:NSBackingStoreBuffered
		                                    defer:NO];
		[panel setTitle:@"Preferences"];
		[panel center];

		NSView* content = panel.contentView;

		// Font name
		NSTextField* fontLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 195, 100, 20)];
		fontLabel.stringValue = @"Font:";
		fontLabel.bezeled = NO;
		fontLabel.drawsBackground = NO;
		fontLabel.editable = NO;
		fontLabel.selectable = NO;
		[content addSubview:fontLabel];

		NSPopUpButton* fontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 192, 200, 26) pullsDown:NO];
		NSArray* fonts = @[@"Menlo", @"Monaco", @"SF Mono", @"Courier New", @"Consolas",
		                   @"Fira Code", @"JetBrains Mono", @"Source Code Pro"];
		for (NSString* f in fonts)
			[fontPopup addItemWithTitle:f];
		NSString* currentFont = [NSString stringWithUTF8String:g_fontName.c_str()];
		[fontPopup selectItemWithTitle:currentFont];
		if (fontPopup.indexOfSelectedItem < 0)
			[fontPopup selectItemAtIndex:0];
		[content addSubview:fontPopup];

		// Font size
		NSTextField* sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 160, 100, 20)];
		sizeLabel.stringValue = @"Font Size:";
		sizeLabel.bezeled = NO;
		sizeLabel.drawsBackground = NO;
		sizeLabel.editable = NO;
		sizeLabel.selectable = NO;
		[content addSubview:sizeLabel];

		NSPopUpButton* sizePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 157, 80, 26) pullsDown:NO];
		NSArray* sizes = @[@"9", @"10", @"11", @"12", @"13", @"14", @"16", @"18", @"20", @"24"];
		for (NSString* s in sizes)
			[sizePopup addItemWithTitle:s];
		[sizePopup selectItemWithTitle:[NSString stringWithFormat:@"%d", g_fontSize]];
		if (sizePopup.indexOfSelectedItem < 0)
			[sizePopup selectItemAtIndex:4]; // Default 13
		[content addSubview:sizePopup];

		// Tab width
		NSTextField* tabLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 125, 100, 20)];
		tabLabel.stringValue = @"Tab Width:";
		tabLabel.bezeled = NO;
		tabLabel.drawsBackground = NO;
		tabLabel.editable = NO;
		tabLabel.selectable = NO;
		[content addSubview:tabLabel];

		NSPopUpButton* tabPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 122, 80, 26) pullsDown:NO];
		NSArray* tabSizes = @[@"2", @"3", @"4", @"5", @"6", @"7", @"8"];
		for (NSString* t in tabSizes)
			[tabPopup addItemWithTitle:t];
		[tabPopup selectItemWithTitle:[NSString stringWithFormat:@"%d", g_tabWidth]];
		if (tabPopup.indexOfSelectedItem < 0)
			[tabPopup selectItemAtIndex:2]; // Default 4
		[content addSubview:tabPopup];

		// Dark mode toggle info
		NSTextField* darkLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 85, 340, 20)];
		darkLabel.stringValue = @"Dark mode follows system preferences.";
		darkLabel.bezeled = NO;
		darkLabel.drawsBackground = NO;
		darkLabel.editable = NO;
		darkLabel.selectable = NO;
		darkLabel.textColor = [NSColor secondaryLabelColor];
		[content addSubview:darkLabel];

		// OK / Cancel buttons
		NSButton* okButton = [[NSButton alloc] initWithFrame:NSMakeRect(270, 15, 90, 32)];
		okButton.title = @"OK";
		okButton.bezelStyle = NSBezelStyleRounded;
		okButton.keyEquivalent = @"\r"; // Enter
		okButton.target = panel;
		okButton.action = @selector(performClose:);
		okButton.tag = 1;
		[content addSubview:okButton];

		NSButton* cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(170, 15, 90, 32)];
		cancelButton.title = @"Cancel";
		cancelButton.bezelStyle = NSBezelStyleRounded;
		cancelButton.keyEquivalent = @"\033"; // Escape
		cancelButton.target = panel;
		cancelButton.action = @selector(performClose:);
		cancelButton.tag = 0;
		[content addSubview:cancelButton];

		// Run as modal
		okButton.target = NSApp;
		okButton.action = @selector(stopModal);
		cancelButton.target = NSApp;
		cancelButton.action = @selector(abortModal);

		NSModalResponse result = [NSApp runModalForWindow:panel];

		if (result == NSModalResponseStop)
		{
			// OK pressed - apply settings
			NSString* selFont = fontPopup.titleOfSelectedItem;
			g_fontName = [selFont UTF8String];
			g_fontSize = sizePopup.titleOfSelectedItem.intValue;
			g_tabWidth = tabPopup.titleOfSelectedItem.intValue;

			if (g_scintillaView)
			{
				ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFONT, 32, (intptr_t)g_fontName.c_str());
				ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETSIZE, 32, g_fontSize);
				ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLECLEARALL, 0, 0);
				ScintillaBridge_sendMessage(g_scintillaView, SCI_SETTABWIDTH, g_tabWidth, 0);

				// Reapply appearance (colors)
				applyAppearance();

				// Reapply language keywords/highlighting
				if (g_activeTab >= 0 && g_activeTab < static_cast<int>(g_documents.size()))
					applyLanguage(g_documents[g_activeTab].languageIndex);
			}
		}

		[panel orderOut:nil];
	}
}

// ============================================================
// File operations
// ============================================================

// Guess language from file extension
static int guessLanguage(const std::wstring& filePath)
{
	NSString* path = WideToNSString(filePath.c_str());
	NSString* ext = [path.pathExtension lowercaseString];

	if ([ext isEqualToString:@"c"] || [ext isEqualToString:@"h"])
		return 1; // C
	if ([ext isEqualToString:@"cpp"] || [ext isEqualToString:@"cc"] ||
	    [ext isEqualToString:@"cxx"] || [ext isEqualToString:@"hpp"] ||
	    [ext isEqualToString:@"hh"] || [ext isEqualToString:@"hxx"] ||
	    [ext isEqualToString:@"mm"])
		return 2; // C++
	if ([ext isEqualToString:@"java"])
		return 3; // Java
	if ([ext isEqualToString:@"py"] || [ext isEqualToString:@"pyw"])
		return 4; // Python
	if ([ext isEqualToString:@"js"] || [ext isEqualToString:@"jsx"] ||
	    [ext isEqualToString:@"ts"] || [ext isEqualToString:@"tsx"])
		return 5; // JavaScript
	if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"])
		return 6; // HTML
	if ([ext isEqualToString:@"css"] || [ext isEqualToString:@"scss"] ||
	    [ext isEqualToString:@"less"])
		return 7; // CSS
	if ([ext isEqualToString:@"xml"] || [ext isEqualToString:@"xsl"] ||
	    [ext isEqualToString:@"xslt"] || [ext isEqualToString:@"plist"])
		return 8; // XML
	if ([ext isEqualToString:@"json"])
		return 9; // JSON
	if ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"])
		return 10; // Markdown
	if ([ext isEqualToString:@"sql"])
		return 11; // SQL
	if ([ext isEqualToString:@"sh"] || [ext isEqualToString:@"bash"] ||
	    [ext isEqualToString:@"zsh"])
		return 12; // Shell
	if ([ext isEqualToString:@"rs"])
		return 13; // Rust
	if ([ext isEqualToString:@"go"])
		return 14; // Go
	if ([ext isEqualToString:@"m"])
		return 15; // Objective-C
	if ([ext isEqualToString:@"swift"])
		return 16; // Swift

	return 0; // Normal text
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
			size_t lastSlash = title.rfind(L'/');
			if (lastSlash != std::wstring::npos)
				title = title.substr(lastSlash + 1);

			int langIdx = guessLanguage(wpath);
			addNewTab(title, std::string([content UTF8String]), wpath, langIdx);

			if (g_fileMonitor)
			{
				std::wstring dir = wpath.substr(0, wpath.rfind(L'/'));
				g_fileMonitor->addDirectory(dir);
			}

			// Add to recent files
			addRecentFile(wpath);
			rebuildRecentMenu();
		}
		else if (error)
		{
			NSLog(@"Error opening file: %@", error);
		}
	}
}

static void openRecentFile(int index)
{
	if (index < 0 || index >= static_cast<int>(g_recentFiles.size()))
		return;

	std::wstring wpath = g_recentFiles[index];
	NSString* path = WideToNSString(wpath.c_str());
	NSError* error = nil;
	NSString* content = [NSString stringWithContentsOfFile:path
	                                             encoding:NSUTF8StringEncoding
	                                                error:&error];
	if (content)
	{
		std::wstring title = wpath;
		size_t lastSlash = title.rfind(L'/');
		if (lastSlash != std::wstring::npos)
			title = title.substr(lastSlash + 1);

		int langIdx = guessLanguage(wpath);
		addNewTab(title, std::string([content UTF8String]), wpath, langIdx);

		if (g_fileMonitor)
		{
			std::wstring dir = wpath.substr(0, wpath.rfind(L'/'));
			g_fileMonitor->addDirectory(dir);
		}

		// Move to front of recent list
		addRecentFile(wpath);
		rebuildRecentMenu();
	}
	else if (error)
	{
		NSLog(@"Error opening recent file: %@", error);
		// Remove from recent list if file no longer exists
		g_recentFiles.erase(g_recentFiles.begin() + index);
		rebuildRecentMenu();
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

		// Update tab title
		TCITEMW tcItem = {};
		tcItem.mask = TCIF_TEXT;
		wchar_t titleBuf[256];
		wcsncpy(titleBuf, doc.title.c_str(), 255);
		titleBuf[255] = L'\0';
		tcItem.pszText = titleBuf;
		SendMessageW(g_tabHwnd, TCM_SETITEMW, g_activeTab, reinterpret_cast<LPARAM>(&tcItem));

		// Detect language from extension
		doc.languageIndex = guessLanguage(doc.filePath);
		applyLanguage(doc.languageIndex);
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

			// Add to recent files
			addRecentFile(doc.filePath);
			rebuildRecentMenu();
		}

		delete[] buf;
	}
}

// ============================================================
// Language switching
// ============================================================

static void applyLanguage(int langIndex)
{
	if (!g_scintillaView) return;
	if (langIndex < 0 || langIndex >= g_numLanguages) return;

	const auto& lang = g_languages[langIndex];

	// Create lexer via Lexilla and send to Scintilla
	ILexer5* lexer = CreateLexer(lang.lexerName);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETILEXER, 0, (intptr_t)lexer);

	// Set keyword lists
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETKEYWORDS, 0, (intptr_t)lang.keywords);
	if (lang.keywords2 && lang.keywords2[0])
		ScintillaBridge_sendMessage(g_scintillaView, SCI_SETKEYWORDS, 1, (intptr_t)lang.keywords2);

	// Set fold properties
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETPROPERTY, (uintptr_t)"fold", (intptr_t)"1");
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETPROPERTY, (uintptr_t)"fold.compact", (intptr_t)"0");
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETPROPERTY, (uintptr_t)"fold.comment", (intptr_t)"1");
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETPROPERTY, (uintptr_t)"fold.preprocessor", (intptr_t)"1");

	// Set font on STYLE_DEFAULT
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFONT, 32, (intptr_t)g_fontName.c_str());
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETSIZE, 32, g_fontSize);

	// Apply syntax-aware colors
	applyAppearance();

	// Trigger re-coloring
	ScintillaBridge_sendMessage(g_scintillaView, SCI_COLOURISE, 0, -1);
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

			// Check for recent file commands
			if (cmdId >= IDM_FILE_RECENT_BASE && cmdId < IDM_FILE_RECENT_BASE + MAX_RECENT_FILES)
			{
				openRecentFile(cmdId - IDM_FILE_RECENT_BASE);
				return 0;
			}

			// Check for language commands
			if (cmdId >= IDM_LANG_BASE && cmdId < IDM_LANG_BASE + g_numLanguages)
			{
				int langIdx = cmdId - IDM_LANG_BASE;
				if (g_activeTab >= 0 && g_activeTab < static_cast<int>(g_documents.size()))
					g_documents[g_activeTab].languageIndex = langIdx;
				applyLanguage(langIdx);
				return 0;
			}

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
				case IDM_FILE_SAVEAS:
				{
					// Force Save As by temporarily clearing the file path
					if (g_activeTab >= 0 && g_activeTab < static_cast<int>(g_documents.size()))
					{
						std::wstring origPath = g_documents[g_activeTab].filePath;
						g_documents[g_activeTab].filePath.clear();
						saveCurrentFile();
						// If user cancelled, restore original path
						if (g_documents[g_activeTab].filePath.empty())
							g_documents[g_activeTab].filePath = origPath;
					}
					return 0;
				}
				case IDM_FILE_CLOSE:
					closeTab(g_activeTab);
					return 0;
				case IDM_FILE_CLOSEALL:
					while (g_documents.size() > 1)
						closeTab(static_cast<int>(g_documents.size()) - 1);
					closeTab(0);
					return 0;
				case IDM_FILE_RECENT_CLEAR:
					g_recentFiles.clear();
					rebuildRecentMenu();
					return 0;

				case IDM_EDIT_UNDO:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_UNDO, 0, 0);
					return 0;
				case IDM_EDIT_REDO:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_REDO, 0, 0);
					return 0;
				case IDM_EDIT_CUT:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_CUT, 0, 0);
					return 0;
				case IDM_EDIT_COPY:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_COPY, 0, 0);
					return 0;
				case IDM_EDIT_PASTE:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_PASTE, 0, 0);
					return 0;
				case IDM_EDIT_SELECTALL:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_SELECTALL, 0, 0);
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
				case IDM_VIEW_FOLDALL:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_FOLDALL, SC_FOLDACTION_CONTRACT, 0);
					return 0;
				case IDM_VIEW_UNFOLDALL:
					if (g_scintillaView)
						ScintillaBridge_sendMessage(g_scintillaView, SCI_FOLDALL, SC_FOLDACTION_EXPAND, 0);
					return 0;
				case IDM_VIEW_PREFERENCES:
					showPreferencesDlg();
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

				case IDM_SEARCH_BOOKMARK_TOGGLE:
					toggleBookmark();
					return 0;
				case IDM_SEARCH_BOOKMARK_NEXT:
					nextBookmark();
					return 0;
				case IDM_SEARCH_BOOKMARK_PREV:
					prevBookmark();
					return 0;
				case IDM_SEARCH_BOOKMARK_CLEARALL:
					clearAllBookmarks();
					return 0;

				case IDM_EDIT_AUTOCOMPLETE:
					showAutoComplete();
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

	// File menu
	HMENU hFileMenu = CreatePopupMenu();
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_NEW, L"&New\tCtrl+N");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_OPEN, L"&Open...\tCtrl+O");
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);

	// Recent files submenu
	g_recentMenu = CreatePopupMenu();
	AppendMenuW(g_recentMenu, MF_STRING | MF_GRAYED, 0, L"(No recent files)");
	AppendMenuW(hFileMenu, MF_POPUP, reinterpret_cast<UINT_PTR>(g_recentMenu), L"Recent &Files");

	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_SAVE, L"&Save\tCtrl+S");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_SAVEAS, L"Save &As...\tCtrl+Shift+S");
	AppendMenuW(hFileMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSE, L"&Close\tCtrl+W");
	AppendMenuW(hFileMenu, MF_STRING, IDM_FILE_CLOSEALL, L"Close &All");
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
	AppendMenuW(hEditMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hEditMenu, MF_STRING, IDM_EDIT_AUTOCOMPLETE, L"Auto-&Complete\tCtrl+Space");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hEditMenu), L"&Edit");

	// Search menu
	HMENU hSearchMenu = CreatePopupMenu();
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_FIND, L"&Find...\tCtrl+F");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_REPLACE, L"&Replace...\tCtrl+H");
	AppendMenuW(hSearchMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_FINDNEXT, L"Find &Next\tF3");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_FINDPREV, L"Find &Previous\tShift+F3");
	AppendMenuW(hSearchMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_GOTOLINE, L"&Go to Line...\tCtrl+G");
	AppendMenuW(hSearchMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_BOOKMARK_TOGGLE, L"Toggle &Bookmark\tCtrl+F2");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_BOOKMARK_NEXT, L"Ne&xt Bookmark\tF2");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_BOOKMARK_PREV, L"Pre&vious Bookmark\tShift+F2");
	AppendMenuW(hSearchMenu, MF_STRING, IDM_SEARCH_BOOKMARK_CLEARALL, L"Clear All Book&marks");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hSearchMenu), L"&Search");

	// View menu
	HMENU hViewMenu = CreatePopupMenu();
	AppendMenuW(hViewMenu, MF_STRING, IDM_VIEW_WORDWRAP, L"&Word Wrap");
	AppendMenuW(hViewMenu, MF_STRING | MF_CHECKED, IDM_VIEW_LINENUMBER, L"&Line Numbers");
	AppendMenuW(hViewMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hViewMenu, MF_STRING, IDM_VIEW_FOLDALL, L"&Fold All");
	AppendMenuW(hViewMenu, MF_STRING, IDM_VIEW_UNFOLDALL, L"&Unfold All");
	AppendMenuW(hViewMenu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(hViewMenu, MF_STRING, IDM_VIEW_PREFERENCES, L"&Preferences...\tCtrl+,");
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hViewMenu), L"&View");

	// Language menu
	HMENU hLangMenu = CreatePopupMenu();
	for (int i = 0; i < g_numLanguages; ++i)
	{
		NSString* name = [NSString stringWithUTF8String:g_languages[i].name];
		std::wstring wname = NSStringToWide(name);
		AppendMenuW(hLangMenu, MF_STRING, g_languages[i].menuId, wname.c_str());
	}
	AppendMenuW(hMenuBar, MF_POPUP, reinterpret_cast<UINT_PTR>(hLangMenu), L"&Language");

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
	ScintillaBridge_sendMessage(sci, SCI_SETTABWIDTH, g_tabWidth, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETUSETABS, 0, 0);

	// Line number margin
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 0, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 0, 50);

	// Bookmark margin (margin 1)
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 1, 0); // SC_MARGIN_SYMBOL
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 1, 16);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINMASKN, 1, BOOKMARK_MASK);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINSENSITIVEN, 1, 1);

	// Configure bookmark marker appearance
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, BOOKMARK_MARKER, SC_MARK_BOOKMARK);
	ScintillaBridge_sendMessage(sci, SCI_MARKERSETFORE, BOOKMARK_MARKER, 0xFFFFFF);
	ScintillaBridge_sendMessage(sci, SCI_MARKERSETBACK, BOOKMARK_MARKER, 0xFF8000);

	// Code folding margin (margin 2) — SC_MARGIN_SYMBOL (0), not SC_MARGIN_TEXT (4)
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINTYPEN, 2, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINMASKN, 2, SC_MASK_FOLDERS);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINWIDTHN, 2, 16);
	ScintillaBridge_sendMessage(sci, SCI_SETMARGINSENSITIVEN, 2, 1);

	// Define fold marker symbols (box tree style)
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPEN,    SC_MARK_BOXMINUS);
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDER,        SC_MARK_BOXPLUS);
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERSUB,     SC_MARK_VLINE);
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERTAIL,    SC_MARK_LCORNER);
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEREND,     SC_MARK_BOXPLUSCONNECTED);
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED);
	ScintillaBridge_sendMessage(sci, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER);

	// Fold flags and automatic fold on margin click
	ScintillaBridge_sendMessage(sci, SCI_SETFOLDFLAGS, 16, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETAUTOMATICFOLD, SC_AUTOMATICFOLD_CLICK, 0);

	ScintillaBridge_sendMessage(sci, SCI_SETCARETLINEVISIBLE, 1, 0);
	ScintillaBridge_sendMessage(sci, SCI_SETCARETLINEBACK, 0xF0F0F0, 0);
}

// ============================================================
// Dark mode support
// ============================================================

static void applyFoldMarkerColors(bool isDark)
{
	if (!g_scintillaView) return;
	int fgColor = isDark ? 0xD4D4D4 : 0x808080;
	int bgColor = isDark ? 0x2D2D2D : 0xF0F0F0;
	for (int m = SC_MARKNUM_FOLDEREND; m <= SC_MARKNUM_FOLDEROPEN; ++m)
	{
		ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERSETFORE, m, fgColor);
		ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERSETBACK, m, bgColor);
	}
}

static void applyAppearance()
{
	if (!g_scintillaView) return;

	NSAppearanceName appearanceName = [NSApp.effectiveAppearance
		bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	bool isDark = [appearanceName isEqualToString:NSAppearanceNameDarkAqua];

	// Set STYLE_DEFAULT colors
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 32, isDark ? 0xD4D4D4 : 0x000000);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETBACK, 32, isDark ? 0x1E1E1E : 0xFFFFFF);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLECLEARALL, 0, 0); // propagate to all

	// Apply per-lexer syntax styles
	int langIdx = 0;
	if (g_activeTab >= 0 && g_activeTab < static_cast<int>(g_documents.size()))
		langIdx = g_documents[g_activeTab].languageIndex;
	if (langIdx >= 0 && langIdx < g_numLanguages)
	{
		const LexerStyles* ls = findLexerStyles(g_languages[langIdx].lexerName);
		if (ls)
		{
			for (int i = 0; i < ls->numStyles; ++i)
			{
				const auto& s = ls->styles[i];
				ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, s.styleId,
					isDark ? s.darkFore : s.lightFore);
				if (s.bold)
					ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETBOLD, s.styleId, 1);
				if (s.italic)
					ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETITALIC, s.styleId, 1);
			}
		}
	}

	// Caret, caret line
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETCARETFORE, isDark ? 0xAEAFAD : 0x000000, 0);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_SETCARETLINEBACK, isDark ? 0x2A2A2A : 0xF0F0F0, 0);

	// Line number margin
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETFORE, 33, isDark ? 0x858585 : 0x808080);
	ScintillaBridge_sendMessage(g_scintillaView, SCI_STYLESETBACK, 33, isDark ? 0x1E1E1E : 0xF0F0F0);

	// Bookmark marker
	ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERSETBACK, BOOKMARK_MARKER,
		isDark ? 0xFFA050 : 0xFF8000);

	// Fold marker colors
	applyFoldMarkerColors(isDark);
}

// ============================================================
// Application Delegate
// ============================================================

@interface NppPhase6Delegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
- (void)performContextAction:(NSMenuItem*)sender;
@end

@implementation NppPhase6Delegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
	// Register window class
	WNDCLASSEXW wc = {};
	wc.cbSize = sizeof(wc);
	wc.lpfnWndProc = MainWndProc;
	wc.lpszClassName = L"Notepad++Phase6";
	RegisterClassExW(&wc);

	// Build menu bar
	HMENU hMenuBar = buildMenuBar();

	// Create main window
	g_mainHwnd = CreateWindowExW(
		0, L"Notepad++Phase6", L"Notepad++ (macOS) — Phase 6",
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

	int parts[] = {200, 400, 550, -1};
	SendMessageW(g_statusBarHwnd, SB_SETPARTS, 4, reinterpret_cast<LPARAM>(parts));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 0, reinterpret_cast<LPARAM>(L"Ln 1, Col 1"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 1, reinterpret_cast<LPARAM>(L"0 lines"));
	SendMessageW(g_statusBarHwnd, SB_SETTEXTW, 2, reinterpret_cast<LPARAM>(L"C++"));
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
	applyAppearance();

	// Register Scintilla notification callback for margin clicks
	ScintillaBridge_setNotifyCallback(g_scintillaView, (intptr_t)g_mainHwnd,
		[](intptr_t windowid, unsigned int iMessage, uintptr_t wParam, uintptr_t lParam) {
			// iMessage 1002 = WM_NOTIFY in Cocoa Scintilla convention
			if (iMessage == 1002 && lParam)
			{
				// lParam points to a Cocoa Scintilla notification struct
				// The notification code is at offset of nmhdr.code
				struct SciNotifyHeader {
					void* hwndFrom;
					uintptr_t idFrom;
					unsigned int code;
				};
				struct SciNotify {
					SciNotifyHeader nmhdr;
					intptr_t position;
					int ch;
					int modifiers;
					int modificationType;
					const char* text;
					intptr_t length;
					intptr_t linesAdded;
					int message;
					uintptr_t wParam;
					intptr_t sLParam;
					intptr_t line;
					int foldLevelNow;
					int foldLevelPrev;
					int margin;
				};
				auto* scn = reinterpret_cast<const SciNotify*>(lParam);

				if (scn->nmhdr.code == 2010) // SCN_MARGINCLICK
				{
					if (scn->margin == 1 && g_scintillaView) // Bookmark margin
					{
						intptr_t line = ScintillaBridge_sendMessage(g_scintillaView,
							SCI_LINEFROMPOSITION, scn->position, 0);
						intptr_t markers = ScintillaBridge_sendMessage(g_scintillaView,
							SCI_MARKERGET, line, 0);
						if (markers & BOOKMARK_MASK)
							ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERDELETE, line, BOOKMARK_MARKER);
						else
							ScintillaBridge_sendMessage(g_scintillaView, SCI_MARKERADD, line, BOOKMARK_MARKER);
					}
					// Fold margin (margin 2) is handled automatically by SC_AUTOMATICFOLD_CLICK
				}
			}
		});

	// Create first document
		const char* welcomeText =
		"// Welcome to Notepad++ on macOS \xe2\x80\x94 Phase 6!\n"
		"//\n"
		"// What's new in Phase 6:\n"
		"//   - Real syntax highlighting via Lexilla lexers\n"
		"//   - Per-lexer color schemes (VS Code-inspired)\n"
		"//   - Code folding with box-style margin markers\n"
		"//   - Click fold margin or use View > Fold All / Unfold All\n"
		"//   - Secondary keyword highlighting (types, builtins)\n"
		"//\n"
		"// Also includes all Phase 5 features:\n"
		"//   Regex search, bookmarks, auto-completion, recent files,\n"
		"//   context menu, preferences, language selection\n"
		"\n"
		"#include <iostream>\n"
		"#include <string>\n"
		"#include <vector>\n"
		"#include <memory>\n"
		"\n"
		"namespace demo {\n"
		"\n"
		"// A template class to demonstrate syntax highlighting\n"
		"template <typename T>\n"
		"class Container {\n"
		"public:\n"
		"    explicit Container(size_t capacity)\n"
		"        : _data(std::make_unique<T[]>(capacity))\n"
		"        , _capacity(capacity)\n"
		"        , _size(0) {}\n"
		"\n"
		"    void push_back(const T& value) {\n"
		"        if (_size < _capacity) {\n"
		"            _data[_size++] = value;\n"
		"        }\n"
		"    }\n"
		"\n"
		"    T& operator[](size_t index) {\n"
		"        return _data[index];\n"
		"    }\n"
		"\n"
		"    size_t size() const { return _size; }\n"
		"\n"
		"private:\n"
		"    std::unique_ptr<T[]> _data;\n"
		"    size_t _capacity;\n"
		"    size_t _size;\n"
		"};\n"
		"\n"
		"} // namespace demo\n"
		"\n"
		"/* Multi-line comment:\n"
		"   Demonstrates comment folding and styling */\n"
		"\n"
		"int main() {\n"
		"    demo::Container<std::string> names(10);\n"
		"    names.push_back(\"Hello\");\n"
		"    names.push_back(\"World\");\n"
		"\n"
		"    for (size_t i = 0; i < names.size(); ++i) {\n"
		"        std::cout << \"Item \" << i << \": \" << names[i] << std::endl;\n"
		"    }\n"
		"\n"
		"    constexpr double pi = 3.14159;\n"
		"    int count = 42;\n"
		"    bool found = true;\n"
		"\n"
		"    #ifdef DEBUG\n"
		"    std::cout << \"Debug mode\" << std::endl;\n"
		"    #endif\n"
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

	NSLog(@"=== Notepad++ macOS Port — Phase 6 ===");
	NSLog(@"Syntax highlighting, code folding, and all Phase 5 features!");
}

- (void)appearanceChanged:(NSNotification*)notification
{
	dispatch_async(dispatch_get_main_queue(), ^{
		applyAppearance();
		if (g_scintillaView)
			ScintillaBridge_sendMessage(g_scintillaView, SCI_COLOURISE, 0, -1);
	});
}

- (void)performContextAction:(NSMenuItem*)sender
{
	if (g_mainHwnd)
		SendMessageW(g_mainHwnd, WM_COMMAND, MAKEWPARAM(static_cast<WORD>(sender.tag), 0), 0);
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

		NppPhase6Delegate* delegate = [[NppPhase6Delegate alloc] init];
		app.delegate = delegate;

		[app run];
	}
	return 0;
}
