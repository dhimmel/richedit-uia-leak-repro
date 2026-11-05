# UIA client (Windows PowerShell 5.1): FromHandle + TextPattern DocumentRange.GetText once.
param([Parameter(Mandatory)][long]$Hwnd)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$e = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
"ClassName=$($e.Current.ClassName) FrameworkId=$($e.Current.FrameworkId)"
$tp = $null
if ($e.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
  $txt = $tp.DocumentRange.GetText(-1)
  "TextPattern ok, DocumentRange text length=$($txt.Length)"
} else { "TextPattern NOT available" }
