# Win32-only client (Windows PowerShell 5.1): read the WinForms control name with the
# registered WM_GETCONTROLNAME message, which is how UIA's WinForms proxy derives
# AutomationId. Needs a buffer inside the target process (VirtualAllocEx +
# ReadProcessMemory). No UIA, no MSAA.
param([Parameter(Mandatory)][long]$Hwnd)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CtlName {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, UIntPtr size, uint type, uint protect);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr hp, IntPtr addr, UIntPtr size, uint type);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] buf, UIntPtr size, out UIntPtr read);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static string Read(long hwnd) {
    IntPtr h = new IntPtr(hwnd);
    uint msg = RegisterWindowMessage("WM_GETCONTROLNAME");
    uint pid; GetWindowThreadProcessId(h, out pid);
    IntPtr hp = OpenProcess(0x0008 | 0x0010 | 0x0400, false, pid); // VM_OPERATION | VM_READ | QUERY_INFORMATION
    if (hp == IntPtr.Zero) return "OpenProcess failed " + Marshal.GetLastWin32Error();
    const int chars = 256;
    IntPtr buf = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)(chars * 2), 0x3000, 0x04);
    if (buf == IntPtr.Zero) { CloseHandle(hp); return "VirtualAllocEx failed " + Marshal.GetLastWin32Error(); }
    IntPtr res;
    IntPtr ok = SendMessageTimeout(h, msg, (IntPtr)chars, buf, 0x0002 /*ABORTIFHUNG*/, 250, out res);
    byte[] bytes = new byte[chars * 2]; UIntPtr read;
    ReadProcessMemory(hp, buf, bytes, (UIntPtr)bytes.Length, out read);
    VirtualFreeEx(hp, buf, UIntPtr.Zero, 0x8000); CloseHandle(hp);
    if (ok == IntPtr.Zero) return "SendMessageTimeout failed/timeout";
    string s = Encoding.Unicode.GetString(bytes); int z = s.IndexOf('\0'); if (z >= 0) s = s.Substring(0, z);
    return "WM_GETCONTROLNAME result=" + res.ToInt64() + " name=" + s;
  }
}
"@
[CtlName]::Read($Hwnd)
