# UIA client (Windows PowerShell 5.1): FromHandle + property reads only.
param([Parameter(Mandatory)][long]$Hwnd)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$e = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
"AutomationId=$($e.Current.AutomationId) Name=$($e.Current.Name) ClassName=$($e.Current.ClassName) FrameworkId=$($e.Current.FrameworkId)"
