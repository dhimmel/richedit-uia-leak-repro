# Win32-only client (Windows PowerShell 5.1): read the focused control with
# GetGUIThreadInfo, bring the owning window forward, AttachThreadInput + SetFocus
# on the control, read focus again. No UIA, no MSAA.
param([Parameter(Mandatory)][long]$Hwnd, [long]$FormHwnd = 0)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32Focus {
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] struct GUITHREADINFO { public int cbSize; public int flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
  [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gui);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  public static string Run(long hwnd, long formHwnd) {
    IntPtr h = new IntPtr(hwnd); uint pid; uint tid = GetWindowThreadProcessId(h, out pid);
    GUITHREADINFO g = new GUITHREADINFO(); g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
    GetGUIThreadInfo(tid, ref g); long before = g.hwndFocus.ToInt64();
    if (formHwnd != 0) SetForegroundWindow(new IntPtr(formHwnd));
    bool att = AttachThreadInput(GetCurrentThreadId(), tid, true);
    IntPtr prev = SetFocus(h);
    if (att) AttachThreadInput(GetCurrentThreadId(), tid, false);
    g = new GUITHREADINFO(); g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
    GetGUIThreadInfo(tid, ref g);
    return "focus before=" + before + " attached=" + att + " SetFocus prev=" + prev.ToInt64() + " focus after=" + g.hwndFocus.ToInt64() + " isControl=" + (g.hwndFocus == h);
  }
}
"@
[Win32Focus]::Run($Hwnd, $FormHwnd)
