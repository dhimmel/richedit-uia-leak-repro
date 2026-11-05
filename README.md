# RichEdit gets slower with every edit after a UI Automation client touches it

Standalone reproduction of a leak in `msftedit.dll` (the Windows RichEdit control) on Windows 11. Reported at [dotnet/winforms#15367](https://github.com/dotnet/winforms/issues/15367).

Once any UI Automation client has read a property from a RichEdit control, msftedit keeps one text-range object for every subsequent change notification and never frees them. Each later edit walks the whole list, so the cost of an edit grows in proportion to the number of edits made since the touch. The client exiting does not stop it. GC does not help (the objects are native). Only restarting the process resets it.

Reproduced on Windows 11 builds 26100 and 26300, `msftedit.dll` 10.0.26100.9711, x64. Not run on Windows 10.

## Reproduce

Requirements: Windows 11, .NET 10 SDK, Windows PowerShell 5.1 (for the client scripts; the driver runs under either PowerShell), and for the object counts `cdb.exe` from the Windows SDK Debugging Tools.

```powershell
dotnet build -c Release .\RichEditRepro
.\run-variant.ps1 -Variant a   # control: no client touch
.\run-variant.ps1 -Variant b   # one UIA AutomationElement.FromHandle + property read, client exits
```

Each run starts a fresh app with one `RichTextBox` holding 40 short paragraphs, runs 10 batches of 500 edits, performs the variant's client touch from a separate process, then runs 20 more batches, forces a GC, and runs one last batch. It prints a table and writes `results\<variant>.csv`. An edit selects a paragraph, sets `SelectionColor` and `SelectionBackColor`, and every tenth edit also replaces a word with itself.

Expected: variant a stays at the same ms per edit for all 31 batches. Variant b rises steadily from the first batch after the touch and is at about 2.5 times the baseline 10,000 edits later. The absolute baseline depends on the machine (it is mostly repaint); keep the window visible and uncovered while measuring, or the per-edit time collapses and the curve is meaningless.

## Variants

| Variant | Client touch from a separate process | Result |
|---|---|---|
| a | none | flat |
| b | UIA `AutomationElement.FromHandle` + read `AutomationId`, `Name`, `ClassName`; client exits | grows |
| c | UIA `TextPattern.DocumentRange.GetText` once; client exits | grows |
| d | UIA `TextChangedEvent` subscription for 5 batches, then unsubscribe and exit | grows, and keeps growing after unsubscribe |
| e | MSAA only: `AccessibleObjectFromWindow(OBJID_CLIENT)`, read `accName`/`accRole`/`accValue` | flat |
| f | `WM_GETCONTROLNAME` registered message (how the UIA WinForms proxy derives `AutomationId`) | flat |
| g | `GetGUIThreadInfo`, `SetForegroundWindow`, `AttachThreadInput` + `SetFocus` | flat |
| h | `WM_GETTEXTLENGTH` + `WM_GETTEXT` | flat |

Only a `WM_GETOBJECT(UiaRootObjectId)` request starts it. The app counts those requests (`uiaRoot` column) and `OBJID_CLIENT` requests (`objidClient`), so each run shows which path the client took.

## Counting the leaked objects

Timing is noisy; the object count is the clean signal. Run a variant with `-KeepAlive`, then take a full dump and scan it for the vtables of msftedit's UIA objects using Microsoft's public symbols:

```powershell
.\run-variant.ps1 -Variant b -KeepAlive
.\dump-and-count.ps1 -TargetPid (Get-Content .\results\b.pid)
```

Sample output after 300 post-touch edits (300 × 2 colour changes + 30 replacements):

```
class                       vtables hits objects
msftedit!CTXTPATTERN::            9   24       2
msftedit!CTXTPATTERNRANGE::       4 2524     631
msftedit!CTxtRange::              2 1264     632
```

Variant a after 15,500 edits: zero `CTXTPATTERNRANGE`, zero `CTxtRange`, zero `CTXTPATTERN`. Variant b after the same 15,500 edits (10,500 after the touch): 22,050 `CTXTPATTERNRANGE`, which is 10,500 × 2 + 1,050, one per change notification since the touch. Each `CTXTPATTERNRANGE` owns one `CTxtRange`. Variants f, g and h: zero of each, and msftedit never even created its `CTXTPATTERN` provider.

Scan the dump, not the live process: `s -q` over the full 64-bit address space of a live process takes hours, the same scan of a `.dump /ma` file takes seconds.

## Observed timing (one machine, Windows 11 26300)

ms per edit, 500-edit batches, from `results\*.csv`:

| Variant | last batch before touch | first batch after | 20 batches after (10,000 edits) | after forced GC |
|---|---:|---:|---:|---:|
| a | 4.8 | 5.4 | 5.2 | 4.8 |
| b | 4.8 | 6.3 | 11.0 | 12.5 |
| c | 5.1 | 6.2 | 11.9 | 13.0 |
| d | 5.0 | 7.8 (subscribed) | 11.7 | 11.7 |
| e | 5.6 | 5.8 | 5.4 | 5.3 |

The growth in b and c is about 0.3 ms per edit for every 500 edits since the touch, i.e. roughly 0.6 µs per edit per leaked range. In d the extra cost of cross-process event delivery disappears when the client unsubscribes, but the linear growth continues at the same slope. Private bytes grow slowly (about 25 MB to 31 MB over 15,000 edits in b); the symptom is CPU time per edit, not memory. Variants f, g and h were measured with the window partly covered, so their curves are not comparable; their object counts are the result.

## Where the objects come from

From Microsoft's public symbols for `msftedit.dll`:

- Allocation: `CCallMgrCenter::ExitContext` → `SendAllNotifications` → `CTXTPATTERN::SendUiaEvent` → `CTXTPATTERN::get_Value` → `new CTXTPATTERNRANGE`. The range created as the payload of each UIA change event stays registered in the provider's object list and is never released, including when no client is subscribed to the event.
- Per-edit cost: `CNotifyMgr::NotifyPreReplaceRange` / `NotifyPostReplaceRange` → `CUiaObjectList::ApplyChanges` → `CTXTPATTERNRANGE::NotifyOfChange`, which iterates every registered range on every change.

`CTXTPATTERN` is created on the first `WM_GETOBJECT(UiaRootObjectId)` the control answers, and from then on the event payload appears to be created unconditionally. CPU sampling of a process in this state with 90,000 ranges showed over 90% of the UI thread in those two paths, and no release or destructor frame for `CTXTPATTERNRANGE`.

## Notes

- The app routes `WM_GETOBJECT(UiaRootObjectId)` to the native window procedure, as .NET Framework WinForms does, so msftedit's own provider answers. `--managed-uia` lets .NET 10 WinForms handle it instead; the result is identical, because `RichTextBox` has no managed UIA provider and the request reaches msftedit either way. The bug is below WinForms.
- Version check: `msftedit.dll` reports 10.0.26100.9711 in `dump-and-count.ps1` output and in `FileVersionRaw`; the version *string* in the file properties still reads 10.0.26100.8117, so compare binary versions.
- After the single touch in variant b the control receives no further `WM_GETOBJECT` requests, yet the cost keeps climbing. The state is per process and permanent.
- The variant d client's event handler never runs (PowerShell scriptblock on a non-runspace thread), but the subscription is registered server-side (`uiaRoot` requests climb while subscribed), which is what matters for the provider.

## Files

- `RichEditRepro/`: the WinForms app (stdin commands `batch N`, `stats`, `gc`, `quit`; prints `pid`, control `hwnd` and form `hwnd` on start).
- `run-variant.ps1`: driver (`-Variant a..h`, `-PreBatches`, `-PostBatches`, `-EditsPerBatch`, `-KeepAlive`, `-ManagedUia`, `-OutDir`).
- `touch-uia-props.ps1`, `touch-uia-textpattern.ps1`, `touch-uia-event.ps1`, `touch-msaa.ps1`, `touch-getcontrolname.ps1`, `touch-win32-focus.ps1`, `touch-gettext.ps1`: the client touches, one per variant.
- `dump-and-count.ps1`: full dump of a pid plus vtable scan with public symbols (`-Dump` to scan an existing dump).
- `results/*.csv`: the runs behind the tables above.
