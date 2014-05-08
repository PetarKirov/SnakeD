/**
 * Provides simple API for coloring and formatting text in terminal.
 * On Windows OS it uses WinAPI functions, on POSIX systems it uses mainly ANSI codes.
 * 
 * $(B Important notes):
 * $(UL
 *  $(LI Font styles have no effect on windows platform.)
 *  $(LI Light background colors are not supported. Non-light equivalents are used on Posix platforms.)
 * )
 * 
 * License: 
 *  <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License</a>
 * Authors:
 *  <a href="http://github.com/robik">Robert 'Robik' Pasiński</a>
 */
module consoled;

import std.typecons, std.algorithm;
import std.array : replicate;


/// Console output stream
enum ConsoleOutputStream
{
    /// Standard output
    stdout,
    
    /// Standard error output
    stderr
}


/**
 * Console font output style
 * 
 * Does nothing on windows.
 */
enum FontStyle
{
    none          = 0, /// Default
    underline     = 1, /// Underline
    strikethrough = 2  /// Characters legible, but marked for deletion. Not widely supported.
}

alias void delegate(CloseEvent) @system CloseHandler;

/**
 * Represents close event.
 */
struct CloseEvent
{
    /// Close type
    CloseType type;
    
    /// Is close event blockable?
    bool      isBlockable;
}

/**
 * Close type.
 */
enum CloseType
{
    Interrupt, // User pressed Ctrl+C key combination.
    Stop,      // User pressed Ctrl+Break key combination. On posix it is Ctrl+Z.
    Quit,      // Posix only. User pressed Ctrl+\ key combination.
    Other      // Other close reasons. Probably unblockable.
}

/**
 * Console input mode
 */
struct ConsoleInputMode
{
    /// Echo printed characters?
    bool echo = true;
    
    /// Enable line buffering?
    bool line = true;
    
    /**
     * Creates new ConsoleInputMode instance
     * 
     * Params:
     *  echo = Echo printed characters?
     *  line = Use Line buffering?
     */
    this(bool echo, bool line)
    {
        this.echo = echo;
        this.line = line;
    }
    
    /**
     * Console input mode with no feature enabled
     */
    static ConsoleInputMode None = ConsoleInputMode(false, false);
}

/**
 * Represents point in console.
 */
alias Tuple!(int, "x", int, "y") ConsolePoint;

/// Special keys
enum SpecialKey
{
    home = 512, /// Home key
    pageUp,     /// Page Up key
    pageDown,   /// Page Down key
    end,        /// End key
    delete_,    /// Delete key
    insert,     /// Insert key
    up,         /// Arrow up key
    down,       /// Arrow down key
    left,       /// Arrow left key
    right,      /// Arrow right key
    
    escape = 27,/// Escape key
    tab = 9,    /// Tab key
}

////////////////////////////////////////////////////////////////////////
version(Windows)
{ 
    private enum BG_MASK = 0xf0;
    private enum FG_MASK = 0x0f;
    
    import core.sys.windows.windows, std.stdio, std.string;

    ///
    enum Color : ushort
    {        
        black        = 0, /// The black color.
        blue         = 1, /// The blue color.
        green        = 2, /// The green color.
        cyan         = 3, /// The cyan color. (blue-green)
        red          = 4, /// The red color.
        magenta      = 5, /// The magenta color. (dark pink like)
        yellow       = 6, /// The yellow color.
        lightGray    = 7, /// The light gray color. (silver)
        
        gray         = 8,  /// The gray color.
        lightBlue    = 9,  /// The light blue color.
        lightGreen   = 10, /// The light green color.
        lightCyan    = 11, /// The light cyan color. (light blue-green)
        lightRed     = 12, /// The light red color.
        lightMagenta = 13, /// The light magenta color. (pink)
        lightYellow  = 14, /// The light yellow color.
        white        = 15, /// The white color.
        
        bright       = 8,  /// Bright flag. Use with dark colors to make them light equivalents.
        initial      = 256 /// Default color.
    }
    
    
    private __gshared
    {
        CONSOLE_SCREEN_BUFFER_INFO info;
        HANDLE hOutput = null, hInput = null;
        
        Color fg, bg, defFg, defBg;
        CloseHandler[] closeHandlers;
    }
    
    
    shared static this()
    {
        loadDefaultColors(ConsoleOutputStream.stdout);
        SetConsoleCtrlHandler(cast(PHANDLER_ROUTINE)&defaultCloseHandler, true);
    }
    
    private void loadDefaultColors(ConsoleOutputStream cos)
    {
        uint handle;
        
        if(cos == ConsoleOutputStream.stdout) {
            handle = STD_OUTPUT_HANDLE;
        } else if(cos == ConsoleOutputStream.stderr) {
            handle = STD_ERROR_HANDLE;
        } else {
            assert(0, "Invalid console output stream specified");
        }
        
        
        hOutput  = GetStdHandle(handle);
        hInput   = GetStdHandle(STD_INPUT_HANDLE);
        
        // Get current colors
        GetConsoleScreenBufferInfo( hOutput, &info );
        
        // Background are first 4 bits
        defBg = cast(Color)((info.wAttributes & (BG_MASK)) >> 4);
                
        // Rest are foreground
        defFg = cast(Color) (info.wAttributes & (FG_MASK));
        
        fg = Color.initial;
        bg = Color.initial;
    }
    
    private ushort buildColor(Color fg, Color bg)
    {
        if(fg == Color.initial) {
            fg = defFg;
        }
        
        if(bg == Color.initial) {
            bg = defBg;
        }
            
        return cast(ushort)(fg | bg << 4);
    }
    
    private void updateColor()
    {
        stdout.flush();
        SetConsoleTextAttribute(hOutput, buildColor(fg, bg));
    }
    
    
    /**
     * Current console font color
     * 
     * Returns:
     *  Current foreground color set
     */
    Color foreground() @property 
    {
        return fg;
    }
    
    /**
     * Current console background color
     * 
     * Returns:
     *  Current background color set
     */
    Color background() @property
    {
        return bg;
    }
    
    /**
     * Sets console foreground color
     *
     * Flushes stdout.
     *
     * Params:
     *  color = Foreground color to set
     */
    void foreground(Color color) @property 
    {
        fg = color;
        updateColor();
    }
    
    
    /**
     * Sets console background color
     *
     * Flushes stdout.
     *
     * Params:
     *  color = Background color to set
     */
    void background(Color color) @property 
    {
        bg = color;
        updateColor();
    }
    
    /**
     * Sets new console output stream
     * 
     * This function sets default colors 
     * that are used when function is called.
     * 
     * Params:
     *  cos = New console output stream
     */
    void outputStream(ConsoleOutputStream cos) @property
    {
        loadDefaultColors(cos);
    }
    
    /**
     * Sets console font style
     * 
     * Does nothing on windows.
     * 
     * Params:
     *  fs = Font style to set
     */
    void fontStyle(FontStyle fs) @property {}
    
    /**
     * Returns console font style
     * 
     * Returns:
     *  Font style, always none on windows.
     */
    FontStyle fontStyle() @property
    {
        return FontStyle.none;
    }
    
    
    /**
     * Console size
     * 
     * Returns:
     *  Tuple containing console rows and cols.
     */
    ConsolePoint size() @property 
    {
        GetConsoleScreenBufferInfo( hOutput, &info );
        
        int cols, rows;
        
        cols = (info.srWindow.Right  - info.srWindow.Left + 1);
        rows = (info.srWindow.Bottom - info.srWindow.Top  + 1);

        return ConsolePoint(cols, rows);
    }
    
    /**
     * Sets console position
     * 
     * Params:
     *  x = X coordinate of cursor postion
     *  y = Y coordinate of cursor position
     */
    void setCursorPos(int x, int y)
    {
        COORD coord = {
            cast(short)min(width, max(0, x)), 
            cast(short)max(0, y)
        };
        stdout.flush();
        SetConsoleCursorPosition(hOutput, coord);
    }
    
    /**
     * Gets cursor position
     * 
     * Returns:
     *  Cursor position
     */
    ConsolePoint cursorPos() @property
    {
        GetConsoleScreenBufferInfo( hOutput, &info );
        return ConsolePoint(
            info.dwCursorPosition.X, 
            min(info.dwCursorPosition.Y, height) // To keep same behaviour with posix
        );
    }
    
    
    
    /**
     * Sets console title
     * 
     * Params:
     *  title = Title to set
     */
    void title(string title) @property
    {
        SetConsoleTitleA(toStringz(title));
    }
    
    
    /**
     * Adds handler for console close event.
     * 
     * Params:
     *  closeHandler = New close handler
     */
    void addCloseHandler(CloseHandler closeHandler)
    {
        closeHandlers ~= closeHandler;
    }
    
    /**
     * Moves cursor by specified offset
     * 
     * Params:
     *  x = X offset
     *  y = Y offset
     */
    private void moveCursor(int x, int y)
    {
        stdout.flush();
        auto pos = cursorPos();
        setCursorPos(max(pos.x + x, 0), max(0, pos.y + y));
    }

    /**
     * Moves cursor up by n rows
     * 
     * Params:
     *  n = Number of rows to move
     */
    void moveCursorUp(int n = 1)
    {
        moveCursor(0, -n);
    }

    /**
     * Moves cursor down by n rows
     * 
     * Params:
     *  n = Number of rows to move
     */
    void moveCursorDown(int n = 1)
    {
        moveCursor(0, n);
    }

    /**
     * Moves cursor left by n columns
     * 
     * Params:
     *  n = Number of columns to move
     */
    void moveCursorLeft(int n = 1)
    {
        moveCursor(-n, 0);
    }

    /**
     * Moves cursor right by n columns
     * 
     * Params:
     *  n = Number of columns to move
     */
    void moveCursorRight(int n = 1)
    {
        moveCursor(n, 0);
    }
    
    /**
     * Gets console mode
     * 
     * Returns:
     *  Current console mode
     */
    ConsoleInputMode mode() @property
    {
        ConsoleInputMode cim;
        DWORD m;
        GetConsoleMode(hInput, &m);
        
        cim.echo  = !!(m & ENABLE_ECHO_INPUT);
        cim.line  = !!(m & ENABLE_LINE_INPUT);
        
        return cim;
    }
    
    /**
     * Sets console mode
     * 
     * Params:
     *  New console mode
     */
    void mode(ConsoleInputMode cim) @property
    {
        DWORD m;
        
        (cim.echo) ? (m |= ENABLE_ECHO_INPUT) : (m &= ~ENABLE_ECHO_INPUT);
        (cim.line) ? (m |= ENABLE_LINE_INPUT) : (m &= ~ENABLE_LINE_INPUT);
        
        SetConsoleMode(hInput, m);
    }
    
    /**
     * Reads character without line buffering
     * 
     * Params:
     *  echo = Print typed characters
     */
    int getch(bool echo = false)
    {
        INPUT_RECORD ir;
        DWORD count;
        auto m = mode;
        
        mode = ConsoleInputMode.None;
        
        do {
            ReadConsoleInputA(hInput, &ir, 1, &count);
        } while(ir.EventType != KEY_EVENT || !ir.KeyEvent.bKeyDown);
        
        mode = m;
        
        return ir.KeyEvent.wVirtualKeyCode;
    }
    
    /**
     * Checks if any key is pressed.
     * 
     * Shift, Ctrl and Alt keys are not detected.
     * 
     * Returns:
     *  True if any key is pressed, false otherwise.
     */
    bool kbhit()
    {
        return WaitForSingleObject(hInput, 0) == WAIT_OBJECT_0;
    }
    
    /**
     * Sets cursor visibility
     * 
     * Params:
     *  visible = Cursor visibility
     */
    void cursorVisible(bool visible) @property
    {
        CONSOLE_CURSOR_INFO cci;
        GetConsoleCursorInfo(hOutput, &cci);
        cci.bVisible = visible;
        SetConsoleCursorInfo(hOutput, &cci);
    }
    
    private CloseEvent idToCloseEvent(ulong i)
    {
        CloseEvent ce;
        
        switch(i)
        {
            case 0:
                ce.type = CloseType.Interrupt;
            break;
                
            case 1:
                ce.type = CloseType.Stop;
            break;
                
            default:
                ce.type = CloseType.Other;
        }
        
        ce.isBlockable = (ce.type != CloseType.Other);
        
        return ce;
    }
    
    private bool defaultCloseHandler(ulong reason)
    {
        foreach(closeHandler; closeHandlers)
        {
            closeHandler(idToCloseEvent(reason));
        }
        
        return true;
    }

	pure bool IsKeyDownEvent(INPUT_RECORD ir) 
	{
		return ir.EventType == KEY_EVENT && 
			ir.KeyEvent.bKeyDown;
	}

	pure bool IsModKey(INPUT_RECORD ir) 
	{
		// We should also skip over Shift, Control, and Alt, as well as caps lock.
		// Apparently we don't need to check for 0xA0 through 0xA5, which are keys like 
		// Left Control & Right Control. See the ConsoleKey enum for these values.
		ushort keyCode = ir.KeyEvent.wVirtualKeyCode;

		return (keyCode >= VK_SHIFT && keyCode <= VK_MENU) ||
			keyCode == VK_CAPITAL || keyCode == VK_NUMLOCK || keyCode == VK_SCROLL;
	}

	pure bool IsAltKeyDown(INPUT_RECORD ir) 
	{ 
		return ((cast(ControlKeyState) ir.KeyEvent.dwControlKeyState) 
				& (ControlKeyState.LeftAltPressed | ControlKeyState.RightAltPressed)) != 0;
	}

	enum ConsoleKey
    {
        Backspace  = 0x8,
        Tab = 0x9,
        // 0xA,  // Reserved
        // 0xB,  // Reserved
        Clear = 0xC,
        Enter = 0xD,
        // 0E-0F,  // Undefined
        // SHIFT = 0x10,
        // CONTROL = 0x11,
        // Alt = 0x12,
        Pause = 0x13,
        // CAPSLOCK = 0x14,
        // Kana = 0x15,  // Ime Mode
        // Hangul = 0x15,  // Ime Mode
        // 0x16,  // Undefined
        // Junja = 0x17,  // Ime Mode
        // Final = 0x18,  // Ime Mode
        // Hanja = 0x19,  // Ime Mode
        // Kanji = 0x19,  // Ime Mode
        // 0x1A,  // Undefined
        Escape = 0x1B,
        // Convert = 0x1C,  // Ime Mode
        // NonConvert = 0x1D,  // Ime Mode
        // Accept = 0x1E,  // Ime Mode
        // ModeChange = 0x1F,  // Ime Mode
        Spacebar = 0x20,
        PageUp = 0x21,
        PageDown = 0x22,
        End = 0x23,
        Home = 0x24,
        LeftArrow = 0x25,
        UpArrow = 0x26,
        RightArrow = 0x27,
        DownArrow = 0x28,
        Select = 0x29,
        Print = 0x2A,
        Execute = 0x2B,
        PrintScreen = 0x2C,
        Insert = 0x2D,
        Delete = 0x2E,
        Help = 0x2F,
        D0 = 0x30,  // 0 through 9
        D1 = 0x31,
        D2 = 0x32,
        D3 = 0x33,
        D4 = 0x34,
        D5 = 0x35,
        D6 = 0x36,
        D7 = 0x37,
        D8 = 0x38,
        D9 = 0x39,
        // 3A-40 ,  // Undefined
        A = 0x41,
        B = 0x42,
        C = 0x43,
        D = 0x44,
        E = 0x45,
        F = 0x46,
        G = 0x47,
        H = 0x48,
        I = 0x49,
        J = 0x4A,
        K = 0x4B,
        L = 0x4C,
        M = 0x4D,
        N = 0x4E,
        O = 0x4F,
        P = 0x50,
        Q = 0x51,
        R = 0x52,
        S = 0x53,
        T = 0x54,
        U = 0x55,
        V = 0x56,
        W = 0x57,
        X = 0x58,
        Y = 0x59,
        Z = 0x5A,
        LeftWindows = 0x5B,  // Microsoft Natural keyboard
        RightWindows = 0x5C,  // Microsoft Natural keyboard
        Applications = 0x5D,  // Microsoft Natural keyboard
        // 5E ,  // Reserved
        Sleep = 0x5F,  // Computer Sleep Key
        NumPad0 = 0x60,
        NumPad1 = 0x61,
        NumPad2 = 0x62,
        NumPad3 = 0x63,
        NumPad4 = 0x64,
        NumPad5 = 0x65,
        NumPad6 = 0x66,
        NumPad7 = 0x67,
        NumPad8 = 0x68,
        NumPad9 = 0x69,
        Multiply = 0x6A,
        Add = 0x6B,
        Separator = 0x6C,
        Subtract = 0x6D,
        Decimal = 0x6E,
        Divide = 0x6F,
        F1 = 0x70,
        F2 = 0x71,
        F3 = 0x72,
        F4 = 0x73,
        F5 = 0x74,
        F6 = 0x75,
        F7 = 0x76,
        F8 = 0x77,
        F9 = 0x78,
        F10 = 0x79,
        F11 = 0x7A,
        F12 = 0x7B,
        F13 = 0x7C,
        F14 = 0x7D,
        F15 = 0x7E,
        F16 = 0x7F,
        F17 = 0x80,
        F18 = 0x81,
        F19 = 0x82,
        F20 = 0x83,
        F21 = 0x84,
        F22 = 0x85,
        F23 = 0x86,
        F24 = 0x87,
        // 88-8F,  // Undefined
        // NumberLock = 0x90,
        // ScrollLock = 0x91,
        // 0x92,  // OEM Specific
        // 97-9F ,  // Undefined
        // LeftShift = 0xA0,
        // RightShift = 0xA1,
        // LeftControl = 0xA2,
        // RightControl = 0xA3,
        // LeftAlt = 0xA4,
        // RightAlt = 0xA5,
        BrowserBack = 0xA6,  // Windows 2000/XP
        BrowserForward = 0xA7,  // Windows 2000/XP
        BrowserRefresh = 0xA8,  // Windows 2000/XP
        BrowserStop = 0xA9,  // Windows 2000/XP
        BrowserSearch = 0xAA,  // Windows 2000/XP
        BrowserFavorites = 0xAB,  // Windows 2000/XP
        BrowserHome = 0xAC,  // Windows 2000/XP
        VolumeMute = 0xAD,  // Windows 2000/XP
        VolumeDown = 0xAE,  // Windows 2000/XP
        VolumeUp = 0xAF,  // Windows 2000/XP
        MediaNext = 0xB0,  // Windows 2000/XP
        MediaPrevious = 0xB1,  // Windows 2000/XP
        MediaStop = 0xB2,  // Windows 2000/XP
        MediaPlay = 0xB3,  // Windows 2000/XP
        LaunchMail = 0xB4,  // Windows 2000/XP
        LaunchMediaSelect = 0xB5,  // Windows 2000/XP
        LaunchApp1 = 0xB6,  // Windows 2000/XP
        LaunchApp2 = 0xB7,  // Windows 2000/XP
        // B8-B9,  // Reserved
        Oem1 = 0xBA,  // Misc characters, varies by keyboard. For US standard, ;:
        OemPlus = 0xBB,  // Misc characters, varies by keyboard. For US standard, +
        OemComma = 0xBC,  // Misc characters, varies by keyboard. For US standard, ,
        OemMinus = 0xBD,  // Misc characters, varies by keyboard. For US standard, -
        OemPeriod = 0xBE,  // Misc characters, varies by keyboard. For US standard, .
        Oem2 = 0xBF,  // Misc characters, varies by keyboard. For US standard, /?
        Oem3 = 0xC0,  // Misc characters, varies by keyboard. For US standard, `~
        // 0xC1,  // Reserved
        // D8-DA,  // Unassigned
        Oem4 = 0xDB,  // Misc characters, varies by keyboard. For US standard, [{
        Oem5 = 0xDC,  // Misc characters, varies by keyboard. For US standard, \|
        Oem6 = 0xDD,  // Misc characters, varies by keyboard. For US standard, ]}
        Oem7 = 0xDE,  // Misc characters, varies by keyboard. For US standard,
        Oem8 = 0xDF,  // Used for miscellaneous characters; it can vary by keyboard
        // 0xE0,  // Reserved
        // 0xE1,  // OEM specific
        Oem102 = 0xE2,  // Win2K/XP: Either angle or backslash on RT 102-key keyboard
        // 0xE3,  // OEM specific
        Process = 0xE5,  // Windows: IME Process Key
        // 0xE6,  // OEM specific
        Packet = 0xE7,  // Win2K/XP: Used to pass Unicode chars as if keystrokes
        // 0xE8,  // Unassigned
        // 0xE9,  // OEM specific
        Attention = 0xF6,
        CrSel = 0xF7,
        ExSel = 0xF8,
        EraseEndOfFile = 0xF9,
        Play = 0xFA,
        Zoom = 0xFB,
        NoName = 0xFC,  // Reserved
        Pa1 = 0xFD,
        OemClear = 0xFE,
    }

	enum ControlKeyState
	{
		RightAltPressed =  0x0001,
		LeftAltPressed =   0x0002,
		RightCtrlPressed = 0x0004,
		LeftCtrlPressed =  0x0008,
		ShiftPressed =     0x0010,
		NumLockOn =        0x0020,
		ScrollLockOn =     0x0040,
		CapsLockOn =       0x0080,
		EnhancedKey =      0x0100
	}

	enum ConsoleModifiers
    {
        Alt = 1,
		Shift = 2,
		Control = 4
    }

	struct ConsoleKeyInfo {
        wchar KeyChar;
        ConsoleKey Key;
        ConsoleModifiers Modifiers;    

        this(wchar keyChar, ConsoleKey key, bool shift, bool alt, bool control) 
		{
            // Limit ConsoleKey values to 0 to 255, but don't check whether the
            // key is a valid value in our ConsoleKey enum.  There are a few 
            // values in that enum that we didn't define, and reserved keys 
            // that might start showing up on keyboards in a few years.
            if ((cast(int)key) < 0 || (cast(int)key) > 255)
                throw new Error("ArgumentOutOfRange_ConsoleKey");

            KeyChar = keyChar;
            Key = key;
            uint _mods = 0;
            if (shift)
                _mods |= ConsoleModifiers.Shift;
            if (alt)
                _mods |= ConsoleModifiers.Alt;
            if (control)
                _mods |= ConsoleModifiers.Control;

			Modifiers = cast(ConsoleModifiers)_mods;
        }
    }

	INPUT_RECORD _cachedInputRecord;

	bool KeyAvailable()
	{
		if (_cachedInputRecord.EventType == KEY_EVENT)
			return true;

		INPUT_RECORD ir;
		uint numEventsRead;

		while (true) {
			bool r = cast(bool)PeekConsoleInputW(consoled.hInput, &ir, 1, &numEventsRead);
			if (!r) throw new Error("InvalidOperation_ConsoleKeyAvailableOnFile");

			if (numEventsRead == 0)
				return false;

			// Skip non key-down && mod key events.
			if (!IsKeyDownEvent(ir) || IsModKey(ir)) 
			{
				r = cast(bool)ReadConsoleInputA(consoled.hInput, &ir, 1, &numEventsRead);
				if (!r) throw new Error("WIN IO Error");
			}
			else
				return true;
		}
	}

	ConsoleKeyInfo ReadKey(bool intercept)
	{
		INPUT_RECORD ir;
		uint numEventsRead = uint.max;
		bool r;

		//lock (ReadKeySyncObject) {
		if (_cachedInputRecord.EventType == KEY_EVENT) 
		{
			// We had a previous keystroke with repeated characters.
			ir = _cachedInputRecord;
			if (_cachedInputRecord.KeyEvent.wRepeatCount == 0)
				_cachedInputRecord.EventType = ushort.max;
			else {
				_cachedInputRecord.KeyEvent.wRepeatCount--;
			}
			// We will return one key from this method, so we decrement the
			// repeatCount here, leaving the cachedInputRecord in the "queue".

		} 
		else // We did NOT have a previous keystroke with repeated characters:
		{ 
			while (true) 
			{
				r = cast(bool)ReadConsoleInputW(consoled.hInput, &ir, 1, &numEventsRead);
				if (!r || numEventsRead == 0) 
				{
					// This will fail when stdin is redirected from a file or pipe. 
					// We could theoretically call Console.Read here, but I 
					// think we might do some things incorrectly then.
					throw new Error("InvalidOperation_ConsoleReadKeyOnFile");
				}

				short keyCode = ir.KeyEvent.wVirtualKeyCode;

				// First check for non-keyboard events & discard them. Generally we tap into only KeyDown events and ignore the KeyUp events
				// but it is possible that we are dealing with a Alt+NumPad unicode key sequence, the final unicode char is revealed only when 
				// the Alt key is released (i.e when the sequence is complete). To avoid noise, when the Alt key is down, we should eat up 
				// any intermediate key strokes (from NumPad) that collectively forms the Unicode character.  

				if (!IsKeyDownEvent(ir)) 
				{
					// 
					if (keyCode != 0x12 /*AltVKCode*/)
						continue;
				}

				char ch = cast(char) ir.KeyEvent.UnicodeChar;

				// In a Alt+NumPad unicode sequence, when the alt key is released uChar will represent the final unicode character, we need to 
				// surface this. VirtualKeyCode for this event will be Alt from the Alt-Up key event. This is probably not the right code, 
				// especially when we don't expose ConsoleKey.Alt, so this will end up being the hex value (0x12). VK_PACKET comes very 
				// close to being useful and something that we could look into using for this purpose... 

				if (ch == 0) 
				{
					// Skip mod keys.
					if (IsModKey(ir))
						continue;
				}

				// When Alt is down, it is possible that we are in the middle of a Alt+NumPad unicode sequence.
				// Escape any intermediate NumPad keys whether NumLock is on or not (notepad behavior)
				ConsoleKey key = cast(ConsoleKey) keyCode;
				if (IsAltKeyDown(ir) && ((key >= ConsoleKey.NumPad0 && key <= ConsoleKey.NumPad9)
										 || (key == ConsoleKey.Clear) || (key == ConsoleKey.Insert)
										 || (key >= ConsoleKey.PageUp && key <= ConsoleKey.DownArrow))) 
				{
					continue;
				}

				if (ir.KeyEvent.wRepeatCount > 1) 
				{
					ir.KeyEvent.wRepeatCount--;
					_cachedInputRecord = ir;
				}
				break;
			}
		}  // we did NOT have a previous keystroke with repeated characters.
		//}  // lock(ReadKeySyncObject)

		ControlKeyState state = cast(ControlKeyState) ir.KeyEvent.dwControlKeyState;
		bool shift = (state & ControlKeyState.ShiftPressed) != 0;
		bool alt = (state & (ControlKeyState.LeftAltPressed | ControlKeyState.RightAltPressed)) != 0;
		bool control = (state & (ControlKeyState.LeftCtrlPressed | ControlKeyState.RightCtrlPressed)) != 0;

		ConsoleKeyInfo info = ConsoleKeyInfo((cast(wchar)ir.KeyEvent.UnicodeChar),
											 (cast(ConsoleKey) ir.KeyEvent.wVirtualKeyCode),
											 shift, alt, control);

		//if (!intercept)
		//	Console.Write(ir.keyEvent.uChar);
		return info;
	}
}
////////////////////////////////////////////////////////////////////////
else version(Posix)
{
    import std.stdio, 
            std.conv,
            std.string,
            core.sys.posix.unistd,
            core.sys.posix.sys.ioctl,
            core.sys.posix.termios,
            core.sys.posix.fcntl,
            core.sys.posix.sys.time;
    
    enum SIGINT  = 2;
    enum SIGTSTP = 20;
    enum SIGQUIT = 3;
    extern(C) void signal(int, void function(int) @system);
    
    enum
    {
        UNDERLINE_ENABLE  = 4,
        UNDERLINE_DISABLE = 24,
            
        STRIKE_ENABLE     = 9,
        STRIKE_DISABLE    = 29
    }
    
    ///
    enum Color : ushort
    {        
        black        = 30, /// The black color.
        red          = 31, /// The red color.
        green        = 32, /// The green color.
        yellow       = 33, /// The yellow color.
        blue         = 34, /// The blue color.
        magenta      = 35, /// The magenta color. (dark pink like)
        cyan         = 36, /// The cyan color. (blue-green)
        lightGray    = 37, /// The light gray color. (silver)
        
        gray         = 94,  /// The gray color.
        lightRed     = 95,  /// The light red color.
        lightGreen   = 96,  /// The light green color.
        lightYellow  = 97,  /// The light yellow color.
        lightBlue    = 98,  /// The light red color.
        lightMagenta = 99,  /// The light magenta color. (pink)
        lightCyan    = 100, /// The light cyan color.(light blue-green)
        white        = 101, /// The white color.
        
        bright       = 64,  /// Bright flag. Use with dark colors to make them light equivalents.
        initial      = 256  /// Default color
    }
    
    
    private __gshared
    {   
        Color fg = Color.initial;
        Color bg = Color.initial;
        File stream;
        int stdinFd;
        FontStyle currentFontStyle;
        
        CloseHandler[] closeHandlers;
        SpecialKey[string] specialKeys;
    }
    
    shared static this()
    {
        stream = stdout;
        signal(SIGINT,  &defaultCloseHandler);
        signal(SIGTSTP, &defaultCloseHandler);
        signal(SIGQUIT, &defaultCloseHandler);
        stdinFd = fileno(stdin.getFP);
        
        specialKeys = [
            "[A" : SpecialKey.up,
            "[B" : SpecialKey.down,
            "[C" : SpecialKey.right,
            "[D" : SpecialKey.left,
            
            "OH" : SpecialKey.home,
            "[5~": SpecialKey.pageUp,
            "[6~": SpecialKey.pageDown,
            "OF" : SpecialKey.end,
            "[3~": SpecialKey.delete_,
            "[2~": SpecialKey.insert,
            
            "\033":SpecialKey.escape
        ];
    }
    
    
    private bool isRedirected()
    {
        return isatty( fileno(stream.getFP) ) != 1;
    }
    
    private void printAnsi()
    {
        stream.writef("\033[%d;%d;%d;%d;%dm",
            fg &  Color.bright ? 1 : 0,            
            fg & ~Color.bright,
            (bg & ~Color.bright) + 10, // Background colors are normal + 10
            
            currentFontStyle & FontStyle.underline     ? UNDERLINE_ENABLE : UNDERLINE_DISABLE,
            currentFontStyle & FontStyle.strikethrough ? STRIKE_ENABLE    : STRIKE_DISABLE
        );        
    }
    
    /**
     * Sets console foreground color
     *
     * Params:
     *  color = Foreground color to set
     */
    void foreground(Color color) @property
    {
        if(isRedirected()) {
            return;
        }
        
        fg = color;        
        printAnsi();
    }
    
    /**
     * Sets console background color
     *
     * Params:
     *  color = Background color to set
     */
    void background(Color color) @property
    {
        if(isRedirected()) {
            return;
        }
        
        bg = color;
        printAnsi();
    }   
    
    /**
     * Current console background color
     * 
     * Returns:
     *  Current foreground color set
     */
    Color foreground() @property
    {
        return fg;
    }
    
    /**
     * Current console font color
     * 
     * Returns:
     *  Current background color set
     */
    Color background() @property
    {
        return bg;
    }
    
    /**
     * Sets new console output stream
     * 
     * Params:
     *  cos = New console output stream
     */
    void outputStream(ConsoleOutputStream cos) @property
    {
        if(cos == ConsoleOutputStream.stdout) {
            stream = stdout;
        } else if(cos == ConsoleOutputStream.stderr) {
            stream = stderr;
        } else {
            assert(0, "Invalid consone output stream specified");
        }
    }
    
    
    /**
     * Sets console font style
     * 
     * Params:
     *  fs = Font style to set
     */
    void fontStyle(FontStyle fs) @property
    {
        currentFontStyle = fs;
        printAnsi();
    }
    
    /**
     * Console size
     * 
     * Returns:
     *  Tuple containing console rows and cols.
     */
    ConsolePoint size() @property
    {
        winsize w;
        ioctl(STDOUT_FILENO, TIOCGWINSZ, &w);

        return ConsolePoint(cast(int)w.ws_col, cast(int)w.ws_row);
    }
    
    /**
     * Sets console position
     * 
     * Params:
     *  x = X coordinate of cursor postion
     *  y = Y coordinate of cursor position
     */
    void setCursorPos(int x, int y)
    {
        stdout.flush();
        writef("\033[%d;%df", y + 1, x + 1);
    }
    
    /**
     * Gets cursor position
     * 
     * Returns:
     *  Cursor position
     */
    ConsolePoint cursorPos() @property
    {
        termios told, tnew;
        char[] buf;
        
        tcgetattr(0, &told);
        tnew = told;
        tnew.c_lflag &= ~ECHO & ~ICANON;
        tcsetattr(0, TCSANOW, &tnew);
        
        write("\033[6n");
        stdout.flush();
        foreach(i; 0..8)
        {
            char c;
            c = cast(char)getch();
            buf ~= c;
            if(c == 'R')
                break;
        }
        tcsetattr(0, TCSANOW, &told);
        
        buf = buf[2..$-1];
        auto tmp = buf.split(";");
        
        return ConsolePoint(to!int(tmp[1]) - 1, to!int(tmp[0]) - 1);
    }
    
    /**
     * Sets console title
     * 
     * Params:
     *  title = Title to set
     */
    void title(string title) @property
    {
        stdout.flush();
        writef("\033]0;%s\007", title); // TODO: Check if supported
    }
    
    /**
     * Adds handler for console close event.
     * 
     * Params:
     *  closeHandler = New close handler
     */
    void addCloseHandler(CloseHandler closeHandler)
    {
        closeHandlers ~= closeHandler;
    }
    
    /**
     * Moves cursor up by n rows
     * 
     * Params:
     *  n = Number of rows to move
     */
    void moveCursorUp(int n = 1)
    {
        writef("\033[%dA", n);
    }

    /**
     * Moves cursor down by n rows
     * 
     * Params:
     *  n = Number of rows to move
     */
    void moveCursorDown(int n = 1)
    {
        writef("\033[%dB", n);
    }

    /**
     * Moves cursor left by n columns
     * 
     * Params:
     *  n = Number of columns to move
     */
    void moveCursorLeft(int n = 1)
    {
        writef("\033[%dD", n);
    }

    /**
     * Moves cursor right by n columns
     * 
     * Params:
     *  n = Number of columns to move
     */
    void moveCursorRight(int n = 1)
    {
        writef("\033[%dC", n);
    }
    
    /**
     * Gets console mode
     * 
     * Returns:
     *  Current console mode
     */
    ConsoleInputMode mode() @property
    {
        ConsoleInputMode cim;
        termios tio;
	ubyte[100] hack;
        
        tcgetattr(stdinFd, &tio);
        cim.echo = !!(tio.c_lflag & ECHO);
        cim.line = !!(tio.c_lflag & ICANON);
        
        return cim;
    }
    
    /**
     * Sets console mode
     * 
     * Params:
     *  New console mode
     */
    void mode(ConsoleInputMode cim) @property
    {
        termios tio;
	ubyte[100] hack;
        
        tcgetattr(stdinFd, &tio);
        
        (cim.echo) ? (tio.c_lflag |= ECHO) : (tio.c_lflag &= ~ECHO);
        (cim.line) ? (tio.c_lflag |= ICANON) : (tio.c_lflag &= ~ICANON);
        tcsetattr(stdinFd, TCSANOW, &tio);
    }
    
    /**
     * Reads character without line buffering
     * 
     * Params:
     *  echo = Print typed characters
     */
    int getch(bool echo = false)
    {
        int c;
        string buf;
        ConsoleInputMode m;
        
        m = mode;
        mode = ConsoleInputMode(echo, false);
        c = getchar();
        
        if(c == SpecialKey.escape)
        {
            while(kbhit())
            {
                buf ~= getchar();
            }
            writeln(buf);
            if(buf in specialKeys) {
                c = specialKeys[buf];
            } else {
                c = -1;
            }
        }
        
        mode = m;
        
        return c;
    }
    
    /**
     * Checks if anykey is pressed.
     * 
     * Shift, Ctrl and Alt keys are not detected.
     * 
     * Returns:
     *  True if anykey is pressed, false otherwise.
     */
    bool kbhit()
    {
        ConsoleInputMode m;
        int c;
        int old;
        
        m = mode;
        mode = ConsoleInputMode.None;
        
        old = fcntl(STDIN_FILENO, F_GETFL, 0);
        fcntl(STDIN_FILENO, F_SETFL, old | O_NONBLOCK);

        c = getchar();

        fcntl(STDIN_FILENO, F_SETFL, old);
        mode = m;

        if(c != EOF)
        {
            ungetc(c, stdin.getFP);
            return true;
        }

        return false;
    }
    
    /**
     * Sets cursor visibility
     * 
     * Params:
     *  visible = Cursor visibility
     */
    void cursorVisible(bool visible) @property
    {
        char c;
        if(visible)
            c = 'h';
        else
            c = 'l';
           
        writef("\033[?25%c", c);
    }
    
    private CloseEvent idToCloseEvent(ulong i)
    {
        CloseEvent ce;
        
        switch(i)
        {
            case SIGINT:
                ce.type = CloseType.Interrupt;
            break;
            
            case SIGQUIT:
                ce.type = CloseType.Quit;
            break;
            
            case SIGTSTP:
                ce.type = CloseType.Stop;
            break;
            
            default:
                ce.type = CloseType.Other;
        }
        
        ce.isBlockable = (ce.type != CloseType.Other);
        
        return ce;
    }
    
    private extern(C) void defaultCloseHandler(int reason) @system
    {
        foreach(closeHandler; closeHandlers)
        {
            closeHandler(idToCloseEvent(reason));
        }
    }
}

/**
 * Console width
 * 
 * Returns:
 *  Console width as number of columns
 */
int width()
{
    return size.x;
}

/**
 * Console height
 * 
 * Returns:
 *  Console height as number of rows
 */
int height()
{
    return size.y;
}


/**
 * Reads password from user
 * 
 * Params:
 *  mask = Typed character mask
 * 
 * Returns:
 *  Password
 */
string readPassword(char mask = '*')
{
    string pass;
    int c;
    
    version(Windows)
    {
        int backspace = 8;
        int enter = 13;
    }
    version(Posix)
    {
        int backspace = 127;
        int enter = 10;
    }
    
    while((c = getch()) != enter)
    {
        if(c == backspace) {
            if(pass.length > 0) {
                pass = pass[0..$-1];
                write("\b \b");
                stdout.flush();
            }
        } else {
            pass ~= cast(char)c;
            write(mask);
        }
    }
    
    return pass;
}


/**
 * Fills area with specified character
 * 
 * Params:
 *  p1 = Top-Left corner coordinates of area
 *  p2 = Bottom-Right corner coordinates of area
 *  fill = Character to fill area
 */
void fillArea(ConsolePoint p1, ConsolePoint p2, char fill)
{
    foreach(i; p1.y .. p2.y + 1)
    {       
        setCursorPos(p1.x, i);
        write( replicate((&fill)[0..1], p2.x - p1.x));
                                // ^ Converting char to char[]
        stdout.flush();
    }
}

/**
 * Draws box with specified border character
 * 
 * Params:
 *  p1 = Top-Left corner coordinates of box
 *  p2 = Bottom-Right corner coordinates of box
 *  fill = Border character
 */
void drawBox(ConsolePoint p1, ConsolePoint p2, char border)
{
    drawHorizontalLine(p1, p2.x - p1.x, border);
    foreach(i; p1.y + 1 .. p2.y)
    {       
        setCursorPos(p1.x, i);
        write(border);
        setCursorPos(p2.x - 1, i);
        write(border);
    }
    drawHorizontalLine(ConsolePoint(p1.x, p2.y), p2.x - p1.x, border);
}

/**
 * Draws horizontal line with specified fill character
 * 
 * Params:
 *  pos = Start coordinates
 *  length = Line width
 *  border = Border character
 */
void drawHorizontalLine(ConsolePoint pos, int length, char border)
{
    setCursorPos(pos.x, pos.y);
    write(replicate((&border)[0..1], length));
}

/**
 * Draws horizontal line with specified fill character
 * 
 * Params:
 *  pos = Start coordinates
 *  length = Line height
 *  border = Border character
 */
void drawVerticalLine(ConsolePoint pos, int length, char border)
{
    foreach(i; pos.y .. length)
    {
        setCursorPos(pos.x, i);
        write(border);
    }
}

/**
 * Writes at specified position
 * 
 * Params:
 *  point = Where to write
 *  data = Data to write
 */
void writeAt(T)(ConsolePoint point, T data)
{
    setConsoleCursor(point.x, point.y);
    write(data);
    stdout.flush();
}

/**
 * Clears console screen
 */
void clearScreen()
{
    auto size = size;
    short length = cast(short)(size.x * size.y); // Number of all characters to write
    setCursorPos(0, 0);
    
    write( std.array.replicate(" ", length));
    stdout.flush();
}


/**
 * Brings default colors back
 */
void resetColors()
{
    foreground = Color.initial;
    background = Color.initial;
}


/**
 * Brings font formatting to default
 */
void resetFontStyle()
{
    fontStyle = FontStyle.none;
}


struct EnumTypedef(T, string _name) if(is(T == enum))
{
    public T val = T.init;
    
    this(T v) { val = v; }
    
    static EnumTypedef!(T, _name) opDispatch(string n)()
    {
        return EnumTypedef!(T, _name)(__traits(getMember, val, n));
    }
}

/// Alias for color enum
alias EnumTypedef!(Color, "fg") Fg;

/// ditto
alias EnumTypedef!(Color, "bg") Bg;


/**
 * Represents color theme.
 * 
 * Examples:
 * ----
 * alias ThError = ColorTheme(Color.red, Color.black);
 * writeln(ThError("string to write using Error theme(red foreground on black background)"));
 * ----
 */
struct ColorTheme(Color fg, Color bg)
{
    string s;
    this(string s)
    {
        this.s = s;
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        auto _fg = foreground;
        auto _bg = background;
        foreground = fg;
        background = bg;
        sink(s.dup);
        foreground = _fg;
        background = _bg;
    }
}


/**
 * Writes text to console and colorizes text
 * 
 * Params:
 *  params = Text to write
 */
void writec(T...)(T params)
{
    foreach(param; params)
    {
        static if(is(typeof(param) == Fg)) {
            foreground = param.val;
        } else static if(is(typeof(param) == Bg)) {
            background = param.val;
        } else {
            write(param);
        }
    }
}

/**
 * Writes line to console and goes to newline
 * 
 * Params:
 *  params = Text to write
 */
void writecln(T...)(T params)
{
    writec(params);
    writeln();
}
