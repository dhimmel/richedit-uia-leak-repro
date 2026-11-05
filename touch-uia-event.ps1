# UIA client (Windows PowerShell 5.1): subscribe to TextPattern.TextChangedEvent,
# stay alive until $SignalFile exists, then remove the handler and exit.
param([Parameter(Mandatory)][long]$Hwnd, [Parameter(Mandatory)][string]$SignalFile, [string]$LogFile)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$e = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
$script:count = 0
$handler = [System.Windows.Automation.AutomationEventHandler]{ param($src, $args) $script:count++ }
[System.Windows.Automation.Automation]::AddAutomationEventHandler([System.Windows.Automation.TextPattern]::TextChangedEvent, $e, [System.Windows.Automation.TreeScope]::Element, $handler)
"subscribed TextChangedEvent on ClassName=$($e.Current.ClassName)"
while (-not (Test-Path $SignalFile)) { Start-Sleep -Milliseconds 200 }
[System.Windows.Automation.Automation]::RemoveAutomationEventHandler([System.Windows.Automation.TextPattern]::TextChangedEvent, $e, $handler)
"unsubscribed; events received=$($script:count)"
if ($LogFile) { "events received=$($script:count)" | Set-Content $LogFile }
