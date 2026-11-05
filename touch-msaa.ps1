# MSAA-only client (Windows PowerShell 5.1): oleacc!AccessibleObjectFromWindow OBJID_CLIENT, read accName/accRole/accValue. No UIA.
param([Parameter(Mandatory)][long]$Hwnd)
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Accessibility;
public static class MsaaTouch {
  [DllImport("oleacc.dll")]
  static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint dwObjectID, ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppvObject);
  public static string Touch(long hwnd) {
    Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
    object o;
    int hr = AccessibleObjectFromWindow(new IntPtr(hwnd), 0xFFFFFFFCu, ref iid, out o);
    if (hr != 0 || o == null) return "hr=0x" + hr.ToString("x") + " obj=" + (o == null ? "null" : "ok");
    IAccessible acc = (IAccessible)o;
    object self = 0;
    string name = acc.get_accName(self);
    object role = acc.get_accRole(self);
    string val = null; try { val = acc.get_accValue(self); } catch (Exception ex) { val = "n/a(" + ex.GetType().Name + ")"; }
    Marshal.ReleaseComObject(o);
    return "hr=0 accName=" + name + " accRole=" + role + " accValueLength=" + (val == null ? "null" : val.Length.ToString());
  }
}
"@
[MsaaTouch]::Touch($Hwnd)
