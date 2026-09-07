using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

class Program {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile
    );

    static int Main(string[] args) {
        if (args.Length == 0) {
            return RunOriginal(args);
        }

        string rawArg = args[0];
        // Clean launch URL if needed
        string url = rawArg;
        if (url.Contains("&attach=1")) {
            url = url.Replace("&attach=1", "");
        }

        try {
            var handle = CreateFile(
                @"\\.\pipe\VRChatURLLaunchPipe",
                0xC0000000, // GENERIC_READ | GENERIC_WRITE
                0,
                IntPtr.Zero,
                3, // OPEN_EXISTING
                0,
                IntPtr.Zero
            );

            if (!handle.IsInvalid) {
                using (var fs = new FileStream(handle, FileAccess.ReadWrite)) {
                    byte[] data = Encoding.UTF8.GetBytes(url);
                    fs.Write(data, 0, data.Length);
                    fs.Flush();
                    byte[] resp = new byte[1];
                    int read = fs.Read(resp, 0, 1);
                    if (read > 0 && resp[0] == 1) {
                        return 0; // successfully delivered to running game
                    }
                }
            }
        } catch {
            // Ignore and fall back to original
        }

        return RunOriginal(args);
    }

    static int RunOriginal(string[] args) {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string origExe = Path.Combine(dir, "launch.org.exe");
        if (File.Exists(origExe)) {
            try {
                var psi = new ProcessStartInfo {
                    FileName = origExe,
                    Arguments = string.Join(" ", args),
                    UseShellExecute = false
                };
                using (var p = Process.Start(psi)) {
                    p.WaitForExit();
                    return p.ExitCode;
                }
            } catch {
                return 1;
            }
        }
        return 0;
    }
}
