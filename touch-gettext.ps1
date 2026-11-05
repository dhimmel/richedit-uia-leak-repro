# Win32-only client (Windows PowerShell 5.1): read the control text with
# WM_GETTEXTLENGTH + WM_GETTEXT. No UIA, no MSAA.
param([Parameter(Mandatory)][long]$Hwnd)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GetText {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, StringBuilder l);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public static string Read(long hwnd) {
    IntPtr h = new IntPtr(hwnd);
    int len = (int)SendMessage(h, 0x000E, IntPtr.Zero, IntPtr.Zero); // WM_GETTEXTLENGTH
    StringBuilder sb = new StringBuilder(len + 1);
    int got = (int)SendMessage(h, 0x000D, (IntPtr)(len + 1), sb);      // WM_GETTEXT
    return "WM_GETTEXTLENGTH=" + len + " WM_GETTEXT copied=" + got;
  }
}
"@
[GetText]::Read($Hwnd)
