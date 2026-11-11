// Farsight Launcher - stretches the WoW window across the screens you pick and tells the
// Farsight addon where each screen is. Build: see build.bat (uses the C# compiler that ships with Windows).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Farsight
{
    // ------------------------------------------------------------------ native
    static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int L, T, R, B; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool EnumDisplayDevices(string dev, uint i, ref DISPLAY_DEVICE dd, uint flags);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    }

    // ------------------------------------------------------------------ model
    class Mon
    {
        public string Device;      // \\.\DISPLAY1
        public string Model = "";  // GSM5B80
        public string Name = "";   // friendly name
        public Rectangle Bounds;   // physical pixels, virtual desktop coordinates
        public bool Primary;
        public bool Selected;
        public string Key { get { return Bounds.X + "," + Bounds.Y + "," + Bounds.Width + "," + Bounds.Height; } }
        public string Label { get { return Name.Length > 0 ? Name : (Model.Length > 0 ? Model : "Screen"); } }
    }

    class Config
    {
        public string WowRoot = "";
        public string Flavor = "_forever_";
        public string BnetPath = "";
        public bool StartBnet = true;
        public bool SetWindowed = true;
        public bool ExitWithBnet = true;
        public List<string> Selected = new List<string>();
        public string Game = "";
        public string Calibrate = "";      // stamp of the last "Auto-calibrate" press, passed on to the addon

        public static string Dir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Farsight"); } }
        public static string FilePath { get { return Path.Combine(Dir, "config.ini"); } }

        public static Config Load()
        {
            Config c = new Config();
            try
            {
                if (!File.Exists(FilePath)) return c;
                foreach (string line in File.ReadAllLines(FilePath))
                {
                    int i = line.IndexOf('=');
                    if (i <= 0) continue;
                    string k = line.Substring(0, i).Trim(), v = line.Substring(i + 1).Trim();
                    if (k == "wowRoot") c.WowRoot = v;
                    else if (k == "flavor") c.Flavor = v;
                    else if (k == "bnetPath") c.BnetPath = v;
                    else if (k == "startBnet") c.StartBnet = v == "1";
                    else if (k == "setWindowed") c.SetWindowed = v == "1";
                    else if (k == "exitWithBnet") c.ExitWithBnet = v == "1";
                    else if (k == "game") c.Game = v;
                    else if (k == "calibrate") c.Calibrate = v;
                    else if (k == "selected") { c.Selected.Clear(); foreach (string s in v.Split(';')) if (s.Length > 0) c.Selected.Add(s); }
                }
            }
            catch { }
            return c;
        }

        public void Save()
        {
            Directory.CreateDirectory(Dir);
            List<string> l = new List<string>();
            l.Add("wowRoot=" + WowRoot);
            l.Add("flavor=" + Flavor);
            l.Add("bnetPath=" + BnetPath);
            l.Add("startBnet=" + (StartBnet ? "1" : "0"));
            l.Add("setWindowed=" + (SetWindowed ? "1" : "0"));
            l.Add("exitWithBnet=" + (ExitWithBnet ? "1" : "0"));
            l.Add("calibrate=" + Calibrate);
            l.Add("game=" + Game);
            l.Add("selected=" + string.Join(";", Selected.ToArray()));
            File.WriteAllLines(FilePath, l.ToArray());
        }
    }

    // ------------------------------------------------------------------ logic
    static class Core
    {
        public const string AddonName = "Farsight";

        public static List<Mon> Detect()
        {
            Dictionary<string, string> friendly = FriendlyNames();
            List<Mon> list = new List<Mon>();
            foreach (Screen s in Screen.AllScreens)
            {
                Mon m = new Mon();
                m.Device = s.DeviceName;
                m.Bounds = s.Bounds;
                m.Primary = s.Primary;
                try
                {
                    Native.DISPLAY_DEVICE dd = new Native.DISPLAY_DEVICE();
                    dd.cb = Marshal.SizeOf(dd);
                    if (Native.EnumDisplayDevices(s.DeviceName, 0, ref dd, 0) && dd.DeviceID != null)
                    {
                        string[] parts = dd.DeviceID.Split('\\');   // MONITOR\GSM5B80\{guid}\0001
                        if (parts.Length > 1) m.Model = parts[1];
                    }
                }
                catch { }
                string fn;
                if (m.Model.Length > 0 && friendly.TryGetValue(m.Model.ToUpperInvariant(), out fn)) m.Name = fn;
                list.Add(m);
            }
            // stable numbering: top to bottom, then left to right
            list.Sort(delegate(Mon a, Mon b)
            {
                if (a.Bounds.Y != b.Bounds.Y) return a.Bounds.Y.CompareTo(b.Bounds.Y);
                return a.Bounds.X.CompareTo(b.Bounds.X);
            });
            return list;
        }

        // model code (GSM5B80) -> "LG ULTRAGEAR"
        static Dictionary<string, string> FriendlyNames()
        {
            Dictionary<string, string> d = new Dictionary<string, string>();
            try
            {
                using (System.Management.ManagementObjectSearcher q =
                    new System.Management.ManagementObjectSearcher(@"root\wmi", "SELECT InstanceName, UserFriendlyName FROM WmiMonitorID"))
                {
                    foreach (System.Management.ManagementObject o in q.Get())
                    {
                        string inst = Convert.ToString(o["InstanceName"]);       // DISPLAY\GSM5B80\5&...
                        ushort[] raw = o["UserFriendlyName"] as ushort[];
                        if (raw == null) continue;
                        StringBuilder sb = new StringBuilder();
                        foreach (ushort ch in raw) if (ch != 0) sb.Append((char)ch);
                        string[] parts = inst.Split('\\');
                        if (parts.Length > 1 && sb.Length > 0) d[parts[1].ToUpperInvariant()] = sb.ToString().Trim();
                    }
                }
            }
            catch { }
            return d;
        }

        public static Rectangle BoundingBox(List<Mon> mons)
        {
            bool any = false; Rectangle r = Rectangle.Empty;
            foreach (Mon m in mons)
            {
                if (!m.Selected) continue;
                r = any ? Rectangle.Union(r, m.Bounds) : m.Bounds;
                any = true;
            }
            return r;
        }

        // pixels of the bounding box not covered by any selected screen (0 = perfect rectangle)
        public static long DeadPixels(List<Mon> mons)
        {
            Rectangle bb = BoundingBox(mons);
            long covered = 0;
            foreach (Mon m in mons) if (m.Selected) covered += (long)m.Bounds.Width * m.Bounds.Height;
            return (long)bb.Width * bb.Height - covered;
        }

        public static string AddonDir(Config c)
        {
            return Path.Combine(Path.Combine(Path.Combine(Path.Combine(c.WowRoot, c.Flavor), "Interface"), "AddOns"), AddonName);
        }

        static string LuaStr(string s)
        {
            return "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        }

        public static string BuildMonitorsLua(List<Mon> mons, string gameKey, string calibrate)
        {
            Rectangle bb = BoundingBox(mons);
            StringBuilder sb = new StringBuilder();
            sb.Append("-- Written by Farsight Launcher. Do not edit: this file is overwritten every time the launcher starts.\n");
            sb.Append("-- Positions are in pixels, measured from the top-left corner of the WoW window.\n");
            sb.Append("FarsightMonitors = {\n");
            sb.Append("\tversion = 1,\n");
            sb.Append("\tstamp = " + LuaStr(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)) + ",\n");
            sb.Append("\twindow = { w = " + bb.Width + ", h = " + bb.Height + " },\n");
            int id = 0, game = 0;
            StringBuilder sc = new StringBuilder();
            int first = 0;
            foreach (Mon m in mons)
            {
                id++;                      // same number as shown in the launcher and by "Identify screens"
                if (!m.Selected) continue;
                if (first == 0) first = id;
                if (m.Key == gameKey) game = id;
                sc.Append("\t\t{ id = " + id + ", name = " + LuaStr(m.Label) + ", x = " + (m.Bounds.X - bb.X) + ", y = " + (m.Bounds.Y - bb.Y)
                    + ", w = " + m.Bounds.Width + ", h = " + m.Bounds.Height + " },\n");
            }
            if (game == 0) game = first;
            sb.Append("\tgame = " + game + ",\n");
            if (!string.IsNullOrEmpty(calibrate)) sb.Append("\tcalibrate = " + LuaStr(calibrate) + ",\n");
            sb.Append("\tscreens = {\n");
            sb.Append(sc.ToString());
            sb.Append("\t},\n}\n");
            return sb.ToString();
        }

        public const string EmptyMonitorsLua =
            "-- Written by Farsight Launcher. The launcher is not active, so the addon stays passive.\nFarsightMonitors = nil\n";

        public static void WriteMonitorsLua(Config c, string content)
        {
            string dir = AddonDir(c);
            if (!Directory.Exists(dir)) throw new IOException("The Farsight addon is not installed in:\n" + dir);
            File.WriteAllText(Path.Combine(dir, "Monitors.lua"), content, new UTF8Encoding(false));
        }

        // Copies the addon that ships next to the launcher into the AddOns folder.
        public static bool InstallAddon(Config c, out string message)
        {
            string src = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, AddonName);
            if (!File.Exists(Path.Combine(src, AddonName + ".toc")))
            {
                message = "Could not find the addon folder next to the launcher:\n" + src;
                return false;
            }
            string dst = AddonDir(c);
            Directory.CreateDirectory(dst);
            foreach (string f in Directory.GetFiles(src))
                File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), true);
            message = "Addon installed in:\n" + dst;
            return true;
        }

        // WoW must run in plain windowed mode for the window to be stretched.
        public static void SetConfigWtf(Config c, bool windowed, int w, int h)
        {
            string path = Path.Combine(Path.Combine(Path.Combine(c.WowRoot, c.Flavor), "WTF"), "Config.wtf");
            if (!File.Exists(path)) return;
            string bak = path + ".farsight-backup";
            if (!File.Exists(bak)) File.Copy(path, bak);
            List<string> lines = new List<string>(File.ReadAllLines(path));
            Dictionary<string, string> want = new Dictionary<string, string>();
            if (windowed)
            {
                want["gxMaximize"] = "0";
                want["gxWindow"] = "1";
                want["gxWindowedResolution"] = w + "x" + h;
            }
            else
            {
                want["gxMaximize"] = "1";
            }
            foreach (KeyValuePair<string, string> kv in want)
            {
                string newLine = "SET " + kv.Key + " \"" + kv.Value + "\"";
                bool found = false;
                for (int i = 0; i < lines.Count; i++)
                {
                    if (lines[i].StartsWith("SET " + kv.Key + " ", StringComparison.OrdinalIgnoreCase)) { lines[i] = newLine; found = true; }
                }
                if (!found) lines.Add(newLine);
            }
            File.WriteAllLines(path, lines.ToArray(), new UTF8Encoding(false));
        }

        static readonly Regex WowName = new Regex("^(Wow|WowClassic|Wow-64|WowT|WowB)$", RegexOptions.IgnoreCase);

        public static Process FindWow(Config c)
        {
            string flavorDir = Path.Combine(c.WowRoot, c.Flavor).TrimEnd('\\') + "\\";
            Process fallback = null;
            foreach (Process p in Process.GetProcesses())
            {
                try
                {
                    if (!WowName.IsMatch(p.ProcessName) || p.MainWindowHandle == IntPtr.Zero) continue;
                    string exe = null;
                    try { exe = p.MainModule.FileName; } catch { }
                    if (exe == null) { if (fallback == null) fallback = p; continue; }
                    if (exe.StartsWith(flavorDir, StringComparison.OrdinalIgnoreCase)) return p;
                }
                catch { }
            }
            return fallback;
        }

        public static bool AnyWowRunning()
        {
            foreach (Process p in Process.GetProcesses())
                if (WowName.IsMatch(p.ProcessName)) return true;
            return false;
        }

        public static bool BnetRunning()
        {
            return Process.GetProcessesByName("Battle.net").Length > 0;
        }

        public static bool NeedsSpan(IntPtr hwnd, Rectangle target)
        {
            Native.RECT r;
            if (!Native.GetWindowRect(hwnd, out r)) return false;
            return r.L != target.X || r.T != target.Y || (r.R - r.L) != target.Width || (r.B - r.T) != target.Height;
        }

        public static bool Span(IntPtr hwnd, Rectangle target)
        {
            const int GWL_STYLE = -16;
            Native.ShowWindow(hwnd, 9);   // SW_RESTORE
            long style = Native.GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
            long remove = 0x00C00000L | 0x00040000L | 0x00080000L | 0x00020000L | 0x00010000L;  // caption, frame, sysmenu, min/max
            style = (style & ~remove) | 0x80000000L;                                             // WS_POPUP
            Native.SetWindowLongPtr(hwnd, GWL_STYLE, new IntPtr(style));
            // SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOZORDER
            return Native.SetWindowPos(hwnd, IntPtr.Zero, target.X, target.Y, target.Width, target.Height, 0x0020 | 0x0040 | 0x0004);
        }

        public static string GuessWowRoot()
        {
            try
            {
                foreach (Process p in Process.GetProcesses())
                {
                    if (!WowName.IsMatch(p.ProcessName)) continue;
                    try
                    {
                        DirectoryInfo d = Directory.GetParent(p.MainModule.FileName);   // ...\_forever_
                        if (d != null && d.Parent != null) return d.Parent.FullName;
                    }
                    catch { }
                }
            }
            catch { }
            foreach (string key in new string[] {
                @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
            {
                try
                {
                    using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(key))
                    {
                        if (k == null) continue;
                        string v = k.GetValue("InstallPath") as string;
                        if (string.IsNullOrEmpty(v)) continue;
                        DirectoryInfo d = new DirectoryInfo(v.TrimEnd('\\'));
                        if (d.Name.StartsWith("_") && d.Parent != null) return d.Parent.FullName;
                        return d.FullName;
                    }
                }
                catch { }
            }
            string[] rel = { @"World of Warcraft", @"WoW\World of Warcraft", @"Games\World of Warcraft",
                @"Program Files (x86)\World of Warcraft", @"Program Files\World of Warcraft", @"Blizzard\World of Warcraft" };
            try
            {
                foreach (DriveInfo dr in DriveInfo.GetDrives())
                {
                    if (dr.DriveType != DriveType.Fixed || !dr.IsReady) continue;
                    foreach (string r in rel)
                    {
                        string p = Path.Combine(dr.RootDirectory.FullName, r);
                        if (Flavors(p).Count > 0) return p;
                    }
                }
            }
            catch { }
            return "";
        }

        public static List<string> Flavors(string root)
        {
            List<string> l = new List<string>();
            try
            {
                if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return l;
                foreach (string d in Directory.GetDirectories(root, "_*_"))
                    if (Directory.Exists(Path.Combine(d, "Interface")) || Directory.Exists(Path.Combine(d, "WTF")))
                        l.Add(Path.GetFileName(d));
            }
            catch { }
            return l;
        }

        public static string GuessBnet()
        {
            foreach (string key in new string[] {
                @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net",
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net" })
            {
                try
                {
                    using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(key))
                    {
                        if (k == null) continue;
                        string v = k.GetValue("InstallLocation") as string;
                        if (string.IsNullOrEmpty(v)) continue;
                        string exe = Path.Combine(v, "Battle.net Launcher.exe");
                        if (File.Exists(exe)) return exe;
                    }
                }
                catch { }
            }
            string def = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Battle.net\Battle.net Launcher.exe");
            return File.Exists(def) ? def : "";
        }

        public static void CreateShortcut(string lnkPath, string target, string args, string description)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(t);
            object sc = t.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
            Type st = sc.GetType();
            st.InvokeMember("TargetPath", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { target });
            st.InvokeMember("Arguments", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { args });
            st.InvokeMember("WorkingDirectory", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { Path.GetDirectoryName(target) });
            st.InvokeMember("Description", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { description });
            st.InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, sc, null);
        }
    }

    // ------------------------------------------------------------------ screen map control
    class ScreenMap : Control
    {
        public List<Mon> Mons = new List<Mon>();
        public string GameKey = "";
        public event EventHandler Changed;

        public ScreenMap()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Color.FromArgb(24, 26, 32);
        }

        RectangleF Map(Rectangle b)
        {
            Rectangle all = Rectangle.Empty; bool any = false;
            foreach (Mon m in Mons) { all = any ? Rectangle.Union(all, m.Bounds) : m.Bounds; any = true; }
            if (!any || all.Width == 0 || all.Height == 0) return RectangleF.Empty;
            float pad = 14f;
            float s = Math.Min((Width - 2 * pad) / all.Width, (Height - 2 * pad) / all.Height);
            float ox = (Width - all.Width * s) / 2f, oy = (Height - all.Height * s) / 2f;
            return new RectangleF(ox + (b.X - all.X) * s, oy + (b.Y - all.Y) * s, b.Width * s, b.Height * s);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            int n = 0;
            foreach (Mon m in Mons)
            {
                n++;
                RectangleF r = Map(m.Bounds);
                r.Inflate(-3, -3);
                bool game = m.Selected && m.Key == GameKey;
                Color fill = game ? Color.FromArgb(46, 125, 70) : (m.Selected ? Color.FromArgb(44, 98, 168) : Color.FromArgb(58, 61, 70));
                using (Brush b = new SolidBrush(fill)) g.FillRectangle(b, r);
                using (Pen p = new Pen(m.Selected ? Color.White : Color.FromArgb(110, 114, 126), m.Selected ? 2f : 1f)) g.DrawRectangle(p, r.X, r.Y, r.Width, r.Height);
                StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                float big = Math.Max(12f, Math.Min(r.Height * 0.30f, r.Width * 0.22f));
                using (Font f1 = new Font("Segoe UI", big, FontStyle.Bold, GraphicsUnit.Pixel))
                using (Font f2 = new Font("Segoe UI", Math.Max(10f, Math.Min(22f, r.Height * 0.085f)), FontStyle.Regular, GraphicsUnit.Pixel))
                using (Brush w = new SolidBrush(m.Selected ? Color.White : Color.FromArgb(170, 174, 186)))
                {
                    RectangleF top = new RectangleF(r.X, r.Y, r.Width, r.Height * 0.62f);
                    g.DrawString(n.ToString(), f1, w, top, sf);
                    RectangleF bot = new RectangleF(r.X + 2, r.Y + r.Height * 0.55f, r.Width - 4, r.Height * 0.42f);
                    string txt = m.Label + "\n" + m.Bounds.Width + " x " + m.Bounds.Height + (game ? "\nGAME SCREEN" : (m.Selected ? "" : "\nnot used"));
                    g.DrawString(txt, f2, w, bot, sf);
                }
            }
        }

        Mon Hit(Point p)
        {
            foreach (Mon m in Mons) if (Map(m.Bounds).Contains(p)) return m;
            return null;
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            Mon m = Hit(e.Location);
            if (m == null) return;
            if (e.Button == MouseButtons.Right)
            {
                m.Selected = true;
                GameKey = m.Key;
            }
            else if (e.Button == MouseButtons.Left)
            {
                m.Selected = !m.Selected;
                if (!m.Selected && GameKey == m.Key) GameKey = "";
            }
            if (GameKey == "") foreach (Mon x in Mons) if (x.Selected) { GameKey = x.Key; break; }
            Invalidate();
            if (Changed != null) Changed(this, EventArgs.Empty);
        }
    }

    // ------------------------------------------------------------------ main window
    class MainForm : Form
    {
        Config cfg;
        List<Mon> mons;
        ScreenMap map;
        Label info, status;
        TextBox wowBox, bnetBox;
        ComboBox flavorBox;
        CheckBox bnetCheck, windowedCheck, exitCheck;
        Button startBtn;
        NotifyIcon tray;
        System.Windows.Forms.Timer timer;
        bool running, reallyExit, sawBnetOrWow;
        Rectangle target;
        DateTime firstSeen = DateTime.MinValue;
        int lastPid = -1;
        bool autoStart;
        float dpi = 1f;

        int S(int v) { return (int)Math.Round(v * dpi); }
        void SB(Control c, int x, int y, int w, int h) { c.SetBounds(S(x), S(y), S(w), S(h)); }
        Font F(float px, FontStyle st) { return new Font("Segoe UI", px * dpi, st, GraphicsUnit.Pixel); }

        public MainForm(bool autoStart)
        {
            this.autoStart = autoStart;
            try { dpi = Math.Max(1f, Native.GetDpiForSystem() / 96f); } catch { dpi = 1f; }
            cfg = Config.Load();
            mons = Core.Detect();
            if (cfg.WowRoot == "") cfg.WowRoot = Core.GuessWowRoot();
            if (cfg.BnetPath == "") cfg.BnetPath = Core.GuessBnet();

            bool anySel = false;
            foreach (Mon m in mons) { m.Selected = cfg.Selected.Contains(m.Key); if (m.Selected) anySel = true; }
            if (!anySel) foreach (Mon m in mons) { m.Selected = true; }      // first run: use every screen
            string gameKey = cfg.Game;
            bool gameOk = false;
            foreach (Mon m in mons) if (m.Selected && m.Key == gameKey) gameOk = true;
            if (!gameOk)
            {
                gameKey = "";
                foreach (Mon m in mons) if (m.Selected && m.Primary) gameKey = m.Key;
                if (gameKey == "") foreach (Mon m in mons) if (m.Selected) { gameKey = m.Key; break; }
            }

            Text = "Farsight Launcher";
            AutoScaleMode = AutoScaleMode.None;
            Font = F(12f, FontStyle.Regular);
            ClientSize = new Size(S(720), S(610));
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Icon = SystemIcons.Application;

            Label head = new Label();
            head.Text = "Click the screens WoW should cover. Right-click a screen to make it the game screen (the 3D world).";
            SB(head, 16, 12, 688, 20);
            Controls.Add(head);

            map = new ScreenMap();
            map.Mons = mons; map.GameKey = gameKey;
            SB(map, 16, 38, 688, 270);
            map.Changed += delegate { UpdateInfo(); };
            Controls.Add(map);

            info = new Label();
            SB(info, 16, 314, 688, 36);
            Controls.Add(info);

            Label l1 = new Label(); l1.Text = "WoW folder"; SB(l1, 16, 360, 110, 20); Controls.Add(l1);
            wowBox = new TextBox(); SB(wowBox, 130, 357, 380, 23); wowBox.Text = cfg.WowRoot; Controls.Add(wowBox);
            wowBox.Leave += delegate { FillFlavors(); };
            Button b1 = new Button(); b1.Text = "Browse..."; SB(b1, 516, 356, 80, 25); Controls.Add(b1);
            b1.Click += delegate
            {
                using (FolderBrowserDialog d = new FolderBrowserDialog())
                {
                    d.Description = "Pick your World of Warcraft folder (the one that contains _forever_ / _retail_).";
                    if (Directory.Exists(wowBox.Text)) d.SelectedPath = wowBox.Text;
                    if (d.ShowDialog(this) == DialogResult.OK) { wowBox.Text = d.SelectedPath; FillFlavors(); }
                }
            };
            flavorBox = new ComboBox(); flavorBox.DropDownStyle = ComboBoxStyle.DropDownList; SB(flavorBox, 602, 357, 102, 23); Controls.Add(flavorBox);
            FillFlavors();

            bnetCheck = new CheckBox(); bnetCheck.Text = "Start Battle.net"; SB(bnetCheck, 16, 392, 112, 22); bnetCheck.Checked = cfg.StartBnet; Controls.Add(bnetCheck);
            bnetBox = new TextBox(); SB(bnetBox, 130, 391, 380, 23); bnetBox.Text = cfg.BnetPath; Controls.Add(bnetBox);
            Button b2 = new Button(); b2.Text = "Browse..."; SB(b2, 516, 390, 80, 25); Controls.Add(b2);
            b2.Click += delegate
            {
                using (OpenFileDialog d = new OpenFileDialog())
                {
                    d.Filter = "Battle.net Launcher|Battle.net Launcher.exe;Battle.net.exe|Programs|*.exe";
                    if (d.ShowDialog(this) == DialogResult.OK) bnetBox.Text = d.FileName;
                }
            };

            windowedCheck = new CheckBox();
            windowedCheck.Text = "Put WoW in windowed mode automatically (needed for the window to be stretched)";
            SB(windowedCheck, 16, 424, 688, 22); windowedCheck.Checked = cfg.SetWindowed; Controls.Add(windowedCheck);

            exitCheck = new CheckBox();
            exitCheck.Text = "Close the launcher when Battle.net and WoW are closed";
            SB(exitCheck, 16, 448, 688, 22); exitCheck.Checked = cfg.ExitWithBnet; Controls.Add(exitCheck);

            Button idBtn = new Button(); idBtn.Text = "Identify screens"; SB(idBtn, 16, 486, 110, 32); Controls.Add(idBtn);
            idBtn.Click += delegate { Identify(); };
            Button scBtn = new Button(); scBtn.Text = "Create desktop shortcut"; SB(scBtn, 132, 486, 150, 32); Controls.Add(scBtn);
            scBtn.Click += delegate { MakeShortcut(); };
            Button adBtn = new Button(); adBtn.Text = "Install addon"; SB(adBtn, 288, 486, 96, 32); Controls.Add(adBtn);
            adBtn.Click += delegate
            {
                ReadUi();
                string msg; Core.InstallAddon(cfg, out msg);
                MessageBox.Show(this, msg, "Farsight");
            };
            Button reBtn = new Button(); reBtn.Text = "Restore normal WoW"; SB(reBtn, 390, 486, 130, 32); Controls.Add(reBtn);
            reBtn.Click += delegate { Restore(); };
            Button caBtn = new Button(); caBtn.Text = "Auto-calibrate"; SB(caBtn, 526, 486, 100, 32); Controls.Add(caBtn);
            caBtn.Click += delegate { Calibrate(); };
            startBtn = new Button(); startBtn.Text = "Start"; SB(startBtn, 632, 486, 72, 32);
            startBtn.Font = F(12f, FontStyle.Bold); Controls.Add(startBtn);
            startBtn.Click += delegate { if (running) StopWatching(); else StartWatching(true); };

            status = new Label();
            SB(status, 16, 530, 688, 64);
            status.ForeColor = Color.FromArgb(70, 70, 70);
            Controls.Add(status);

            tray = new NotifyIcon();
            tray.Icon = SystemIcons.Application;
            tray.Text = "Farsight Launcher";
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add("Open Farsight Launcher", null, delegate { ShowFromTray(); });
            menu.Items.Add("Exit", null, delegate { reallyExit = true; Close(); });
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += delegate { ShowFromTray(); };

            timer = new System.Windows.Forms.Timer();
            timer.Interval = 2000;
            timer.Tick += delegate { Tick(); };

            UpdateInfo();
            SetStatus("Not started. Pick your screens and press Start.");
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (autoStart) StartWatching(false);
        }

        void FillFlavors()
        {
            string want = flavorBox.SelectedItem != null ? flavorBox.SelectedItem.ToString() : cfg.Flavor;
            flavorBox.Items.Clear();
            foreach (string f in Core.Flavors(wowBox.Text)) flavorBox.Items.Add(f);
            if (flavorBox.Items.Count == 0) return;
            int i = flavorBox.Items.IndexOf(want);
            if (i < 0) i = flavorBox.Items.IndexOf("_forever_");
            flavorBox.SelectedIndex = i < 0 ? 0 : i;
        }

        void UpdateInfo()
        {
            int n = 0; foreach (Mon m in mons) if (m.Selected) n++;
            if (n == 0) { info.Text = "No screen selected."; info.ForeColor = Color.Firebrick; return; }
            Rectangle bb = Core.BoundingBox(mons);
            string t = "WoW window: " + bb.Width + " x " + bb.Height + " pixels across " + n + (n == 1 ? " screen." : " screens.");
            long dead = Core.DeadPixels(mons);
            if (dead > 0)
            {
                t += "\nThe screens do not form a full rectangle. Part of the window ends up outside the screens; the addon keeps windows away from it.";
                info.ForeColor = Color.FromArgb(160, 100, 0);
            }
            else info.ForeColor = SystemColors.ControlText;
            info.Text = t;
        }

        void SetStatus(string s) { status.Text = s; }

        void ReadUi()
        {
            cfg.WowRoot = wowBox.Text.Trim();
            cfg.Flavor = flavorBox.SelectedItem != null ? flavorBox.SelectedItem.ToString() : cfg.Flavor;
            cfg.BnetPath = bnetBox.Text.Trim();
            cfg.StartBnet = bnetCheck.Checked;
            cfg.SetWindowed = windowedCheck.Checked;
            cfg.ExitWithBnet = exitCheck.Checked;
            cfg.Selected.Clear();
            foreach (Mon m in mons) if (m.Selected) cfg.Selected.Add(m.Key);
            cfg.Game = map.GameKey;
        }

        void StartWatching(bool interactive)
        {
            ReadUi();
            int n = 0; foreach (Mon m in mons) if (m.Selected) n++;
            if (n == 0) { Fail("Select at least one screen.", interactive); return; }
            if (Core.Flavors(cfg.WowRoot).Count == 0) { Fail("Pick your World of Warcraft folder first.", interactive); return; }
            if (!Directory.Exists(Core.AddonDir(cfg)))
            {
                string msg;
                if (!Core.InstallAddon(cfg, out msg))
                {
                    Fail("The Farsight addon is not installed for " + cfg.Flavor + ".\nInstall it (for example with the CurseForge app) and press Start again.", interactive);
                    return;
                }
            }
            try { cfg.Save(); } catch { }
            target = Core.BoundingBox(mons);
            try { Core.WriteMonitorsLua(cfg, Core.BuildMonitorsLua(mons, cfg.Game, cfg.Calibrate)); }
            catch (Exception ex) { Fail("Could not write the screen layout for the addon:\n" + ex.Message, interactive); return; }

            bool wowUp = Core.AnyWowRunning();
            if (cfg.SetWindowed && !wowUp)
            {
                try { Core.SetConfigWtf(cfg, true, target.Width, target.Height); } catch { }
            }
            if (cfg.StartBnet && !wowUp && !Core.BnetRunning() && File.Exists(cfg.BnetPath))
            {
                try { Process.Start(cfg.BnetPath); } catch { }
            }
            running = true; sawBnetOrWow = false; lastPid = -1; firstSeen = DateTime.MinValue;
            startBtn.Text = "Stop";
            timer.Start();
            SetStatus(wowUp
                ? "WoW is already running. Stretching the window now. Type /reload in game so the addon reads the new screen layout."
                : "Waiting for WoW. Press Play in Battle.net.");
            tray.Visible = true;
            if (!interactive) HideToTray();
            Tick();
        }

        // Re-reads the screens, rewrites the layout for the addon and tells it to go back to automatic
        // values (game area, UI scale, UI placement). The addon picks this up when the UI is loaded.
        void Calibrate()
        {
            ReadUi();
            int n = 0; foreach (Mon m in mons) if (m.Selected) n++;
            if (n == 0) { Fail("Select at least one screen.", true); return; }
            if (!Directory.Exists(Core.AddonDir(cfg))) { Fail("The Farsight addon is not installed yet. Press \"Install addon\" first.", true); return; }
            cfg.Calibrate = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
            try { cfg.Save(); } catch { }
            target = Core.BoundingBox(mons);
            try { Core.WriteMonitorsLua(cfg, Core.BuildMonitorsLua(mons, cfg.Game, cfg.Calibrate)); }
            catch (Exception ex) { Fail("Could not write the screen layout for the addon:\n" + ex.Message, true); return; }
            Process p = null;
            try { p = Core.FindWow(cfg); } catch { }
            if (p != null && p.MainWindowHandle != IntPtr.Zero)
            {
                Core.Span(p.MainWindowHandle, target);
                string msg = "Calibrated for a " + target.Width + " x " + target.Height + " window.\nType /reload in WoW to apply it.";
                SetStatus(msg.Replace("\n", " "));
                MessageBox.Show(this, msg, "Farsight");
            }
            else
            {
                string msg = "Calibrated for a " + target.Width + " x " + target.Height + " window.\nIt is applied the next time WoW starts.";
                SetStatus(msg.Replace("\n", " "));
                MessageBox.Show(this, msg, "Farsight");
            }
        }

        void Fail(string msg, bool interactive)
        {
            SetStatus(msg);
            if (interactive) MessageBox.Show(this, msg, "Farsight", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            else { Show(); WindowState = FormWindowState.Normal; }
        }

        void StopWatching()
        {
            running = false;
            timer.Stop();
            startBtn.Text = "Start";
            SetStatus("Stopped. The WoW window is no longer kept in place.");
        }

        void Tick()
        {
            if (!running) return;
            Process p = null;
            try { p = Core.FindWow(cfg); } catch { }
            bool bnet = Core.BnetRunning();
            if (p != null || bnet) sawBnetOrWow = true;
            if (p == null)
            {
                if (lastPid != -1) { lastPid = -1; SetStatus("WoW was closed. Waiting for it to start again."); }
                if (cfg.ExitWithBnet && sawBnetOrWow && !bnet && !Core.AnyWowRunning()) { reallyExit = true; Close(); }
                return;
            }
            if (p.Id != lastPid) { lastPid = p.Id; firstSeen = DateTime.Now; return; }
            if ((DateTime.Now - firstSeen).TotalSeconds < 3) return;      // let the window finish creating
            IntPtr h = p.MainWindowHandle;
            if (h == IntPtr.Zero) return;
            if (Core.NeedsSpan(h, target))
            {
                if (Core.Span(h, target))
                    SetStatus(DateTime.Now.ToString("HH:mm:ss") + "  WoW stretched to " + target.Width + " x " + target.Height + ". Keeping it in place.");
                else
                    SetStatus("Could not move the WoW window. If WoW runs as administrator, start this launcher as administrator too.");
            }
        }

        void Identify()
        {
            int n = 0;
            foreach (Mon m in mons)
            {
                n++;
                Form f = new Form();
                f.FormBorderStyle = FormBorderStyle.None; f.StartPosition = FormStartPosition.Manual; f.TopMost = true; f.ShowInTaskbar = false;
                f.BackColor = Color.FromArgb(20, 60, 120);
                int w = Math.Min(360, m.Bounds.Width / 3), h = Math.Min(300, m.Bounds.Height / 3);
                Label l = new Label();
                l.Dock = DockStyle.Fill; l.TextAlign = ContentAlignment.MiddleCenter; l.ForeColor = Color.White;
                l.Font = new Font("Segoe UI", h * 0.45f, FontStyle.Bold, GraphicsUnit.Pixel);
                l.Text = n.ToString();
                f.Controls.Add(l);
                f.Show();
                f.SetBounds(m.Bounds.X + (m.Bounds.Width - w) / 2, m.Bounds.Y + (m.Bounds.Height - h) / 2, w, h);
                System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
                t.Interval = 2500;
                Form cap = f;
                t.Tick += delegate { t.Stop(); t.Dispose(); cap.Close(); };
                t.Start();
            }
        }

        void MakeShortcut()
        {
            try
            {
                ReadUi(); cfg.Save();
                string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "WoW (Farsight).lnk");
                Core.CreateShortcut(lnk, Application.ExecutablePath, "--start", "Start WoW stretched across your screens");
                MessageBox.Show(this, "Created \"WoW (Farsight)\" on your desktop.\nIt starts Battle.net and stretches WoW with the screens you picked here.", "Farsight");
            }
            catch (Exception ex) { MessageBox.Show(this, "Could not create the shortcut:\n" + ex.Message, "Farsight"); }
        }

        void Restore()
        {
            ReadUi();
            if (Core.AnyWowRunning())
            {
                MessageBox.Show(this, "Close WoW first, then press this button again.", "Farsight");
                return;
            }
            StopWatching();
            try { Core.WriteMonitorsLua(cfg, Core.EmptyMonitorsLua); } catch { }
            try { Core.SetConfigWtf(cfg, false, 0, 0); } catch { }
            SetStatus("Restored. WoW starts in normal fullscreen-windowed mode and the addon stays passive until you press Start again.");
        }

        void HideToTray()
        {
            Hide();
            tray.Visible = true;
            try { tray.ShowBalloonTip(3000, "Farsight Launcher", "Running in the background. WoW is stretched when it starts.", ToolTipIcon.Info); } catch { }
        }

        void ShowFromTray()
        {
            Show();
            WindowState = FormWindowState.Normal;
            Activate();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (running && !reallyExit && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;     // keep stretching in the background
                HideToTray();
                return;
            }
            try { ReadUi(); cfg.Save(); } catch { }
            tray.Visible = false;
            base.OnFormClosing(e);
        }
    }

    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            try { if (!Native.SetProcessDpiAwarenessContext(new IntPtr(-4))) Native.SetProcessDPIAware(); }
            catch { try { Native.SetProcessDPIAware(); } catch { } }

            bool start = false, write = false; string dump = null;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--start") start = true;
                else if (args[i] == "--write") write = true;
                else if (args[i] == "--dump" && i + 1 < args.Length) dump = args[++i];
            }

            if (dump != null)
            {
                // diagnostics: write what the launcher detects, and the layout file it would produce
                List<Mon> mons = Core.Detect();
                Config c = Config.Load();
                StringBuilder sb = new StringBuilder();
                foreach (Mon m in mons)
                {
                    m.Selected = c.Selected.Count == 0 || c.Selected.Contains(m.Key);
                    sb.AppendLine(m.Device + " | " + m.Model + " | " + m.Label + " | " + m.Key + " | primary=" + m.Primary + " | selected=" + m.Selected);
                }
                sb.AppendLine("wowRoot=" + (c.WowRoot == "" ? Core.GuessWowRoot() : c.WowRoot));
                sb.AppendLine("bnet=" + (c.BnetPath == "" ? Core.GuessBnet() : c.BnetPath));
                sb.AppendLine("box=" + Core.BoundingBox(mons) + " dead=" + Core.DeadPixels(mons));
                sb.AppendLine(Core.BuildMonitorsLua(mons, c.Game, c.Calibrate));
                File.WriteAllText(dump, sb.ToString());
                return 0;
            }

            if (write)
            {
                // writes the screen layout for the addon from the saved settings, without opening the window
                try
                {
                    List<Mon> mons = Core.Detect();
                    Config c = Config.Load();
                    foreach (Mon m in mons) m.Selected = c.Selected.Contains(m.Key);
                    Core.WriteMonitorsLua(c, Core.BuildMonitorsLua(mons, c.Game, c.Calibrate));
                    return 0;
                }
                catch { return 1; }
            }

            bool created;
            using (Mutex mx = new Mutex(true, "Local\\FarsightLauncher", out created))
            {
                if (!created)
                {
                    if (!start) MessageBox.Show("Farsight Launcher is already running. Look for its icon next to the clock.", "Farsight");
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(start));
            }
            return 0;
        }
    }
}
