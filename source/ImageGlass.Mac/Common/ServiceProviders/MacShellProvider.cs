/*
ImageGlass - A Fast, Seamless Photo Viewer
Copyright (C) 2010 - 2026 DUONG DIEU PHAP
Project homepage: https://imageglass.org

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
using ImageGlass.Common;
using ImageGlass.Common.ServiceProviders;
using ImageGlass.Common.Types;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace ImageGlass.Mac.Common.ServiceProviders;

internal class MacShellProvider : PhDisposable, IShellProvider
{
    private const string PREVIEW_BUNDLE_ID = "com.apple.Preview";

    // the app each type had before this one took it, so removing the default gives it back
    private const string PREVIOUS_HANDLERS_FILE = "igdefaultviewer_previous.txt";


    public object? ForegroundShell { get; set; }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public string InstallChannelId => "dmg";


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    protected override void OnDisposing()
    {
        base.OnDisposing();
        AllowSleep();
        ForegroundShell = null;
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public bool CanUseForegroundShell()
    {
        // macOS does not support foreground shell integration
        return false;
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void DeleteFile(string filePath, bool moveToRecycleBin = true)
    {
        if (moveToRecycleBin)
        {
            // use AppleScript to move the file to Trash via Finder
            RunAppleScript(
                $"tell application \"Finder\" to delete POSIX file \"{filePath}\"");
        }
        else
        {
            File.Delete(filePath);
        }
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public object? GetForegroundWindowView()
    {
        // macOS does not have a foreground shell object
        return null;
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public string? GetTargetPathFromShortcut(string? lnkFilePath)
    {
        if (string.IsNullOrWhiteSpace(lnkFilePath)) return null;

        // resolve symlinks
        try
        {
            var fileInfo = new FileInfo(lnkFilePath);
            if (fileInfo.LinkTarget is string target)
            {
                var resolvedPath = Path.IsPathRooted(target)
                    ? target
                    : Path.GetFullPath(target, Path.GetDirectoryName(lnkFilePath)!);

                return resolvedPath;
            }
        }
        catch { }

        // resolve macOS Finder aliases via AppleScript
        try
        {
            var script = $"tell application \"Finder\" to get POSIX path of " +
                         $"(original item of alias (POSIX file \"{lnkFilePath}\" as text))";
            var result = RunAppleScriptAndReadOutput(script);

            if (!string.IsNullOrWhiteSpace(result))
            {
                return result.Trim();
            }
        }
        catch { }

        return null;
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public Task OpenDefaultEditingAppAsync(string filePath, Action? callbackFn = null)
    {
        // 'open' launches the file in its default associated application
        BHelper.RunProcess("open", $"\"{filePath}\"");
        callbackFn?.Invoke();

        return Task.CompletedTask;
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void OpenFilePath(string? filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath)) return;

        // 'open -R' reveals and selects the file in Finder
        BHelper.RunProcess("open", $"-R \"{filePath}\"");
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void OpenFolderPath(string? dirPath)
    {
        if (string.IsNullOrWhiteSpace(dirPath)) return;

        try
        {
            Directory.CreateDirectory(dirPath);
        }
        catch { }

        BHelper.RunProcess("open", $"\"{dirPath}\"");
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    /// <exception cref="InvalidOperationException"></exception>
    public async Task<DefaultAppScope?> SetDefaultPhotoViewerAsync(string[] extensions, bool enable)
    {
        var appId = MacLaunchServicesApi.GetMainBundleId()
            ?? throw new InvalidOperationException("IGE: Start the app from its .app bundle to change the default photo viewer.");

        // macOS confirms each type in a dialog, and one type often covers several extensions (.jpg, .jpeg, .jpe)
        var typeIds = extensions
            .Select(ext => MacLaunchServicesApi.GetTypeIdentifier(ext.TrimStart('.')))
            .OfType<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var previousPath = BHelper.ConfigDir(PREVIOUS_HANDLERS_FILE);
        var previous = ReadPreviousHandlers(previousPath);
        var errors = new List<string>();

        // one refused type must not stop the rest, nor lose the record of what the others had
        foreach (var typeId in typeIds)
        {
            try
            {
                var current = MacLaunchServicesApi.GetDefaultHandler(typeId);
                var isOurs = string.Equals(current, appId, StringComparison.OrdinalIgnoreCase);

                if (enable)
                {
                    // setting a type that is already ours would still show the user a dialog
                    if (isOurs) continue;

                    if (current is not null) previous[typeId] = current;
                    MacLaunchServicesApi.SetDefaultHandler(typeId, appId);
                }
                else if (isOurs)
                {
                    var target = FindHandlerToRestore(MacLaunchServicesApi.GetHandlers(typeId), previous.GetValueOrDefault(typeId), appId);
                    if (target is not null) MacLaunchServicesApi.SetDefaultHandler(typeId, target);

                    previous.Remove(typeId);
                }
            }
            catch (Exception ex)
            {
                errors.Add(ex.Message);
            }
        }

        await BHelper.WriteAllTextSharedAsync(previousPath,
            string.Join('\n', previous.Select(p => $"{p.Key}={p.Value}"))).ConfigureAwait(false);

        if (errors.Count > 0) throw new InvalidOperationException(string.Join(Environment.NewLine, errors));

        return DefaultAppScope.CurrentUser;
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public Task SetLockScreenAsync(string filePath)
    {
        throw new NotSupportedException("IGE: This feature is not supported on macOS.");
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void SetWallpaper(string filePath)
    {
        // use AppleScript via System Events (works on macOS Ventura+)
        RunAppleScript(
            "tell application \"System Events\" to tell every desktop " +
            $"to set picture to \"{filePath}\"");
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void ShowOpenWith(string filePath)
    {
        throw new NotSupportedException("IGE: This feature is not supported on macOS.");
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void ShowFileProperties(string filePath, nint windowHandle)
    {
        // use AppleScript to open the Finder "Get Info" window for the file
        RunAppleScript(
            "tell application \"Finder\" to open information window of " +
            $"(POSIX file \"{filePath}\" as alias)");
    }


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void ShowShare(nint windowHandle, string[] filePaths)
    {
        ArgumentNullException.ThrowIfNull(filePaths);
        if (filePaths.Length == 0) return;

        // build a comma-separated list of POSIX file references for AppleScript
        var fileList = string.Join(", ",
            filePaths.Select(f => $"(POSIX file \"{f}\" as alias)"));

        // reveal and select the files in Finder, then trigger the Share menu
        RunAppleScript(
            "tell application \"Finder\"\n" +
            $"select {{{fileList}}}\n" +
            "activate\n" +
            "end tell\n" +
            "tell application \"System Events\"\n" +
            "tell process \"Finder\"\n" +
            "click menu item \"Share…\" of menu \"File\" of menu bar 1\n" +
            "end tell\n" +
            "end tell");
    }



    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public bool HasPreciseScrollingDeltas() => MacEventApi.HasPreciseScrollingDeltas();


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void PreventSleep(string reason) => MacPowerApi.PreventSleep(reason);


    /// <summary>
    /// <inheritdoc/>
    /// </summary>
    public void AllowSleep() => MacPowerApi.AllowSleep();


    #region Private helpers

    /// <summary>
    /// Reads the app each type had before this app took it over, one <c>type=bundle id</c> per line.
    /// </summary>
    private static Dictionary<string, string> ReadPreviousHandlers(string filePath)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(filePath)) return result;

        using var reader = new StreamReader(BHelper.OpenReadShared(filePath));
        while (reader.ReadLine() is { } line)
        {
            var parts = line.Split('=', 2, StringSplitOptions.TrimEntries);
            if (parts.Length == 2 && parts[0].Length > 0 && parts[1].Length > 0) result[parts[0]] = parts[1];
        }

        return result;
    }


    /// <summary>
    /// Picks the app a type goes back to: the one it had before, else Preview, else any other app that opens it.
    /// </summary>
    private static string? FindHandlerToRestore(string[] handlers, string? previous, string appId)
    {
        bool CanOpen(string? bundleId) => bundleId is not null && handlers.Contains(bundleId, StringComparer.OrdinalIgnoreCase);

        if (CanOpen(previous)) return previous;
        if (CanOpen(PREVIEW_BUNDLE_ID)) return PREVIEW_BUNDLE_ID;

        return handlers.FirstOrDefault(h => !string.Equals(h, appId, StringComparison.OrdinalIgnoreCase));
    }


    /// <summary>
    /// Executes an AppleScript expression via <c>osascript</c>.
    /// Uses <see cref="ProcessStartInfo.ArgumentList"/> to avoid
    /// shell-quoting issues with .NET on Unix.
    /// </summary>
    internal static void RunAppleScript(string script)
    {
        using var proc = new Process();
        proc.StartInfo.FileName = "osascript";
        proc.StartInfo.UseShellExecute = false;
        proc.StartInfo.CreateNoWindow = true;
        proc.StartInfo.ArgumentList.Add("-e");
        proc.StartInfo.ArgumentList.Add(script);
        proc.Start();
    }


    /// <summary>
    /// Executes an AppleScript expression and returns its output.
    /// </summary>
    internal static string RunAppleScriptAndReadOutput(string script)
    {
        try
        {
            using var proc = new Process();
            proc.StartInfo.FileName = "osascript";
            proc.StartInfo.UseShellExecute = false;
            proc.StartInfo.CreateNoWindow = true;
            proc.StartInfo.RedirectStandardOutput = true;
            proc.StartInfo.ArgumentList.Add("-e");
            proc.StartInfo.ArgumentList.Add(script);
            proc.Start();

            var output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();

            return output;
        }
        catch
        {
            return string.Empty;
        }
    }

    #endregion // Private helpers

}
