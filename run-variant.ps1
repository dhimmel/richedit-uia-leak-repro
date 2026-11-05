# Driver: starts a fresh RichEditRepro, runs PreBatches, performs the client touch
# for the chosen variant, runs PostBatches, prints a table and writes <OutDir>\<Variant>.csv.
# With -KeepAlive the app stays running (pid written to <OutDir>\<Variant>.pid) so
# dump-and-count.ps1 can count the native objects.
# Variants: a none, b UIA props, c UIA TextPattern, d UIA event subscription,
# e MSAA, f WM_GETCONTROLNAME, g Win32 focus (GetGUIThreadInfo/AttachThreadInput/SetFocus),
# h WM_GETTEXT. Clients run under Windows PowerShell 5.1.
param(
  [Parameter(Mandatory)][ValidateSet('a','b','c','d','e','f','g','h')][string]$Variant,
  [int]$PreBatches = 10, [int]$PostBatches = 20, [int]$EditsPerBatch = 500,
  [int]$EventBatches = 5,
  [switch]$KeepAlive, [switch]$ManagedUia,
  [string]$OutDir = "$PSScriptRoot\results"
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$exe = "$here\RichEditRepro\bin\Release\net10.0-windows\win-x64\RichEditRepro.exe"
$ps51 = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $exe)) { throw "build first: dotnet build -c Release $here\RichEditRepro" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
if ($ManagedUia) { $psi.Arguments = '--managed-uia' }
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
$app = [System.Diagnostics.Process]::Start($psi)
$hdr = $app.StandardOutput.ReadLine()
"variant $Variant  $hdr"
if ($hdr -notmatch 'pid (\d+) hwnd (\d+) formhwnd (\d+)') { throw "bad header: $hdr" }
$appPid = [int]$Matches[1]; $hwnd = [long]$Matches[2]; $formHwnd = [long]$Matches[3]
if ($KeepAlive) { $appPid | Set-Content "$OutDir\$Variant.pid" }

function Send($cmd) { $app.StandardInput.WriteLine($cmd); $app.StandardOutput.ReadLine() }
function Batch($i, $phase) {
  $r = Send "batch $EditsPerBatch"
  if ($r -notmatch 'ms ([\d.]+) edits (\d+) uiaRootRequests (\d+) clientRequests (\d+)') { throw "bad: $r" }
  $pb = (Get-Process -Id $appPid).PrivateMemorySize64
  [pscustomobject]@{ batch=$i; phase=$phase; ms=[math]::Round([double]$Matches[1],0); msPerEdit=[math]::Round([double]$Matches[1]/$EditsPerBatch,3); edits=[int]$Matches[2]; uiaRoot=[int]$Matches[3]; objidClient=[int]$Matches[4]; privMB=[math]::Round($pb/1MB,1) }
}
function Client($script, $extra = '') {
  $out = & $ps51 -NoProfile -ExecutionPolicy Bypass -Command "& '$here\$script' -Hwnd $hwnd $extra" 2>&1
  "  client [$script]: $($out -join ' | ')"
}

$rows = @()
$n = 0
for ($i = 1; $i -le $PreBatches; $i++) { $n++; $rows += Batch $n 'pre' }

$evtProc = $null; $signal = "$OutDir\$Variant.signal"; $evtLog = "$OutDir\$Variant.evt.txt"
switch ($Variant) {
  'a' { "  no client touch (control)" }
  'b' { Client 'touch-uia-props.ps1' }
  'c' { Client 'touch-uia-textpattern.ps1' }
  'd' {
    if (Test-Path $signal) { Clear-Content $signal; [System.IO.File]::Delete($signal) }
    $epsi = [System.Diagnostics.ProcessStartInfo]::new($ps51, "-NoProfile -ExecutionPolicy Bypass -File `"$here\touch-uia-event.ps1`" -Hwnd $hwnd -SignalFile `"$signal`" -LogFile `"$evtLog`"")
    $epsi.UseShellExecute = $false; $epsi.RedirectStandardOutput = $true
    $evtProc = [System.Diagnostics.Process]::Start($epsi)
    "  event client: $($evtProc.StandardOutput.ReadLine())"
  }
  'e' { Client 'touch-msaa.ps1' }
  'f' { Client 'touch-getcontrolname.ps1' }
  'g' { Client 'touch-win32-focus.ps1' "-FormHwnd $formHwnd" }
  'h' { Client 'touch-gettext.ps1' }
}
"  stats after touch: $(Send 'stats')"

for ($i = 1; $i -le $PostBatches; $i++) {
  $phase = 'post'
  if ($Variant -eq 'd') { $phase = if ($i -le $EventBatches) { 'post-subscribed' } else { 'post-unsubscribed' } }
  $n++; $rows += Batch $n $phase
  if ($Variant -eq 'd' -and $i -eq $EventBatches) {
    'go' | Set-Content $signal
    $evtProc.WaitForExit(15000) | Out-Null
    "  event client exited=$($evtProc.HasExited): $($evtProc.StandardOutput.ReadToEnd().Trim())"
  }
}
"  gc: $(Send 'gc')"
$n++; $rows += Batch $n 'post-gc'
$rows | Format-Table -AutoSize | Out-String -Width 200
$rows | Export-Csv "$OutDir\$Variant.csv" -NoTypeInformation
if (-not $KeepAlive) { Send 'quit' | Out-Null; $app.WaitForExit(5000) | Out-Null } else { "app pid $appPid left running" }
