using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace RichEditRepro;

// RichTextBox that routes WM_GETOBJECT(UiaRootObjectId) to the native richedit
// window procedure, as .NET Framework WinForms does (SupportsUiaProviders is false
// there), so that msftedit's own UIA provider (CTXTPATTERN) answers UIA clients.
// OBJID_CLIENT (MSAA) still goes through WinForms' managed AccessibleObject, as in
// .NET Framework. Pass --managed-uia to let .NET 10 WinForms answer UIA itself
// (same result: RichTextBox has no managed UIA provider, so msftedit answers anyway).
sealed class ReproRtb : RichTextBox
{
    const int WM_GETOBJECT = 0x003D;
    const int UiaRootObjectId = -25;
    public static bool ManagedUia = false;
    public int UiaRootRequests, ClientRequests;

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_GETOBJECT)
        {
            int objId = unchecked((int)(long)m.LParam);
            if (objId == UiaRootObjectId) UiaRootRequests++;
            else if (objId == unchecked((int)0xFFFFFFFC)) ClientRequests++;
            if (!ManagedUia && objId == UiaRootObjectId)
            {
                DefWndProc(ref m);
                return;
            }
        }
        base.WndProc(ref m);
    }
}

static class Program
{
    static Form form;
    static ReproRtb rtb;
    static int[] paraStart, paraLen;
    static long totalEdits;
    static readonly Color[] Fg = { Color.Black, Color.DarkBlue, Color.DarkRed };
    static readonly Color[] Bg = { Color.White, Color.LightYellow, Color.LightCyan };

    [STAThread]
    static void Main(string[] args)
    {
        ReproRtb.ManagedUia = args.Contains("--managed-uia");
        Application.EnableVisualStyles();
        Application.SetHighDpiMode(HighDpiMode.SystemAware);

        form = new Form { Text = "RichEditRepro", Width = 820, Height = 640, StartPosition = FormStartPosition.Manual, Location = new Point(50, 50) };
        rtb = new ReproRtb { Name = "rtbMain", Dock = DockStyle.Fill, Multiline = true, WordWrap = false, DetectUrls = false, Font = new Font("Segoe UI", 10) };
        form.Controls.Add(rtb);

        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < 40; i++)
            sb.Append($"Paragraph {i + 1}: lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod {i}.\n");
        rtb.Text = sb.ToString();
        paraStart = new int[40]; paraLen = new int[40];
        for (int i = 0; i < 40; i++)
        {
            paraStart[i] = rtb.GetFirstCharIndexFromLine(i);
            paraLen[i] = rtb.Lines[i].Length;
        }

        form.Shown += (s, e) =>
        {
            Console.Out.WriteLine($"pid {Environment.ProcessId} hwnd {rtb.Handle.ToInt64()} formhwnd {form.Handle.ToInt64()} managedUia {ReproRtb.ManagedUia}");
            Console.Out.Flush();
            var t = new Thread(StdinLoop) { IsBackground = true };
            t.Start();
        };
        Application.Run(form);
    }

    static void StdinLoop()
    {
        string line;
        while ((line = Console.In.ReadLine()) != null)
        {
            line = line.Trim();
            if (line.Length == 0) continue;
            string result;
            try
            {
                // Marshal to UI thread; the UI thread keeps pumping between commands.
                result = (string)form.Invoke(() => Execute(line));
            }
            catch (Exception ex) { result = "error " + ex.GetType().Name + ": " + ex.Message; }
            Console.Out.WriteLine(result);
            Console.Out.Flush();
            if (line == "quit") break;
        }
    }

    static string Execute(string cmd)
    {
        var parts = cmd.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        switch (parts[0])
        {
            case "quit":
                form.BeginInvoke(() => form.Close());
                return "bye";
            case "gc":
                GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
                return "gc done";
            case "stats":
                return $"edits {totalEdits} uiaRootRequests {rtb.UiaRootRequests} clientRequests {rtb.ClientRequests} privateBytes {Process.GetCurrentProcess().PrivateMemorySize64}";
            case "batch":
                {
                    int n = int.Parse(parts[1]);
                    var sw = Stopwatch.StartNew();
                    for (int i = 0; i < n; i++) DoEdit();
                    sw.Stop();
                    Process.GetCurrentProcess().Refresh();
                    return $"batch {n} ms {sw.Elapsed.TotalMilliseconds:F1} edits {totalEdits} uiaRootRequests {rtb.UiaRootRequests} clientRequests {rtb.ClientRequests} privateBytes {Process.GetCurrentProcess().PrivateMemorySize64}";
                }
            default:
                return "unknown command";
        }
    }

    // One "edit": select a paragraph, set its foreground and background colour
    // (two character-format changes, each a RichEdit change notification), and
    // every 10th edit also replace a word with itself (a text replacement).
    static void DoEdit()
    {
        long k = totalEdits++;
        int p = (int)(k % 40);
        rtb.Select(paraStart[p], paraLen[p]);
        rtb.SelectionColor = Fg[k % 3];
        rtb.SelectionBackColor = Bg[(k / 3) % 3];
        if (k % 10 == 9)
        {
            // replace the word "lorem" (same length) with itself, alternating
            // the SelectedRtf and SelectedText routes
            int idx = rtb.Text.IndexOf("lorem", paraStart[p], StringComparison.Ordinal);
            if (idx >= 0 && idx < paraStart[p] + paraLen[p])
            {
                rtb.Select(idx, 5);
                if ((k / 10) % 2 == 0)
                    rtb.SelectedText = "lorem";
                else
                {
                    string rtf = rtb.SelectedRtf;
                    rtb.SelectedRtf = rtf;
                }
            }
        }
        // collapse the selection so the next edit starts clean
        rtb.Select(paraStart[p], 0);
    }
}
