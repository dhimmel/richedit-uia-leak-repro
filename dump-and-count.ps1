# Counts msftedit's native UIA objects in a process: takes a full memory dump
# (non-invasive cdb attach, .dump /ma) and scans the dump for the vtable pointers
# of CTXTPATTERNRANGE, CTxtRange and CTXTPATTERN using Microsoft's public symbols.
# A class with several vtables (multiple inheritance) gets one hit per vtable per
# object, so objects = hits / vtables. Pass -Dump to scan an existing dump instead.
# Needs cdb.exe from the Windows SDK Debugging Tools. Do not scan a live 64-bit
# process with "s -q" over the full address space: that takes hours; a dump takes seconds.
param([int]$TargetPid, [string]$Dump, [string]$OutDir = "$PSScriptRoot\results")
$ErrorActionPreference = 'Stop'
$cdb = "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
if (-not (Test-Path $cdb)) { throw "cdb.exe not found at $cdb (install the Windows SDK Debugging Tools)" }
$env:_NT_SYMBOL_PATH = "srv*$env:LOCALAPPDATA\Temp\symcache*https://msdl.microsoft.com/download/symbols"

if (-not $Dump) {
  if (-not $TargetPid) { throw "give -TargetPid or -Dump" }
  New-Item -ItemType Directory -Force $OutDir | Out-Null
  $Dump = "$OutDir\pid$TargetPid.dmp"
  & $cdb -pv -p $TargetPid -c ".dump /ma `"$Dump`"; qd" 2>&1 | Out-Null
  if (-not (Test-Path $Dump)) { throw "dump failed" }
  "dump: $Dump ($([math]::Round((Get-Item $Dump).Length/1MB)) MB)"
}
function Cdb($cmd) { & $cdb -z "$Dump" -c "$cmd; q" 2>&1 | Out-String }

$sym = Cdb '.reload /f msftedit.dll; lmv m msftedit; x msftedit!CTXTPATTERNRANGE::*vftable*; x msftedit!CTxtRange::*vftable*; x msftedit!CTXTPATTERN::*vftable*'
$img = [regex]::Match($sym, '(?im)^([0-9a-f`]{17})\s+([0-9a-f`]{17})\s+msftedit')
if (-not $img.Success) { throw "msftedit.dll not found in dump or symbols not loaded:`n$sym" }
$imgStart = [Convert]::ToUInt64($img.Groups[1].Value.Replace('`',''), 16)
$imgEnd   = [Convert]::ToUInt64($img.Groups[2].Value.Replace('`',''), 16)
$ver = [regex]::Match($sym, '(?im)^\s+File version:\s+(\S+)').Groups[1].Value
"msftedit image {0:x}-{1:x} version $ver" -f $imgStart, $imgEnd
$vt = [regex]::Matches($sym, "(?im)^([0-9a-f``]{17})\s+(msftedit!\S+``vftable')")
if ($vt.Count -eq 0) { throw "no vtable symbols found; check symbol access:`n$sym" }
$hitsByClass = @{}; $vtByClass = @{}
foreach ($m in $vt) {
  $addr = $m.Groups[1].Value; $name = $m.Groups[2].Value
  $out = Cdb "s -q 0 L?7fffffffffff $addr"
  $hits = [regex]::Matches($out, '(?m)^([0-9a-f]{8}`[0-9a-f]{8})\s') | ForEach-Object { [Convert]::ToUInt64($_.Groups[1].Value.Replace('`',''), 16) }
  $heap = @($hits | Where-Object { $_ -lt $imgStart -or $_ -ge $imgEnd }).Count
  $hitsByClass[$name] = [int]$hitsByClass[$name] + $heap
  $vtByClass[$name] = [int]$vtByClass[$name] + 1
}
$rows = foreach ($name in $hitsByClass.Keys | Sort-Object) {
  [pscustomobject]@{ class = $name -replace "``vftable'$", ''; vtables = $vtByClass[$name]; hits = $hitsByClass[$name]; objects = [int][math]::Floor($hitsByClass[$name] / $vtByClass[$name]) }
}
$rows | Format-Table -AutoSize | Out-String -Width 200
