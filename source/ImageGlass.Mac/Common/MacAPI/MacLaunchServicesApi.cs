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
using System;
using System.Runtime.InteropServices;

namespace ImageGlass.Mac.Common;


/// <summary>
/// Launch Services lookups behind the default photo viewer: the type of a file extension and the app that opens it.
/// </summary>
internal static partial class MacLaunchServicesApi
{
    private const string CORE_SERVICES = "/System/Library/Frameworks/CoreServices.framework/CoreServices";
    private const string CORE_FOUNDATION = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private const string TAG_CLASS_FILENAME_EXTENSION = "public.filename-extension";

    // Finder asks as public.data too; the dyn. type it gets without one is a different id, which Launch Services rejects (-50)
    private const string TYPE_DATA = "public.data";
    private const uint ROLES_ALL = 0xFFFFFFFF;


    /// <summary>
    /// Gets the bundle identifier of the running app; <c>null</c> when it does not run from an app bundle.
    /// </summary>
    public static string? GetMainBundleId() => MacCoreFoundation.ReadString(CFBundleGetIdentifier(CFBundleGetMainBundle()));


    /// <summary>
    /// Gets the type identifier of a file extension (no dot), a <c>dyn.</c> one when no app declares the extension.
    /// </summary>
    public static string? GetTypeIdentifier(string extension)
    {
        var tagClass = MacCoreFoundation.CreateString(TAG_CLASS_FILENAME_EXTENSION);
        var tag = MacCoreFoundation.CreateString(extension);
        var conformingTo = MacCoreFoundation.CreateString(TYPE_DATA);
        var typeId = nint.Zero;
        try
        {
            typeId = UTTypeCreatePreferredIdentifierForTag(tagClass, tag, conformingTo);
            return MacCoreFoundation.ReadString(typeId);
        }
        finally
        {
            MacCoreFoundation.Release(typeId);
            MacCoreFoundation.Release(conformingTo);
            MacCoreFoundation.Release(tag);
            MacCoreFoundation.Release(tagClass);
        }
    }


    /// <summary>
    /// Gets the bundle identifier of the app that opens the type; <c>null</c> when none does.
    /// </summary>
    public static string? GetDefaultHandler(string typeId)
    {
        var type = MacCoreFoundation.CreateString(typeId);
        var handler = nint.Zero;
        try
        {
            handler = LSCopyDefaultRoleHandlerForContentType(type, ROLES_ALL);
            return MacCoreFoundation.ReadString(handler);
        }
        finally
        {
            MacCoreFoundation.Release(handler);
            MacCoreFoundation.Release(type);
        }
    }


    /// <summary>
    /// Gets the bundle identifiers of every app that declares it can open the type.
    /// </summary>
    public static string[] GetHandlers(string typeId)
    {
        var type = MacCoreFoundation.CreateString(typeId);
        var handlers = nint.Zero;
        try
        {
            handlers = LSCopyAllRoleHandlersForContentType(type, ROLES_ALL);

            var count = (int)MacCoreFoundation.GetCount(handlers);
            var result = new string[count];
            for (var i = 0; i < count; i++)
            {
                result[i] = MacCoreFoundation.ReadString(MacCoreFoundation.GetItem(handlers, i)) ?? string.Empty;
            }

            return result;
        }
        finally
        {
            MacCoreFoundation.Release(handlers);
            MacCoreFoundation.Release(type);
        }
    }


    /// <summary>
    /// Asks for the type to open with the app; macOS confirms it with the user in its own dialog before it applies.
    /// </summary>
    public static void SetDefaultHandler(string typeId, string bundleId)
    {
        var type = MacCoreFoundation.CreateString(typeId);
        var bundle = MacCoreFoundation.CreateString(bundleId);
        try
        {
            var status = LSSetDefaultRoleHandlerForContentType(type, ROLES_ALL, bundle);
            if (status != 0)
            {
                throw new InvalidOperationException($"IGE: Launch Services refused to open '{typeId}' with '{bundleId}' (OSStatus {status}).");
            }
        }
        finally
        {
            MacCoreFoundation.Release(bundle);
            MacCoreFoundation.Release(type);
        }
    }


    #region Launch Services interop

    [LibraryImport(CORE_FOUNDATION)]
    private static partial nint CFBundleGetMainBundle();

    [LibraryImport(CORE_FOUNDATION)]
    private static partial nint CFBundleGetIdentifier(nint bundle);

    [LibraryImport(CORE_SERVICES)]
    private static partial nint UTTypeCreatePreferredIdentifierForTag(nint tagClass, nint tag, nint conformingToTypeId);

    [LibraryImport(CORE_SERVICES)]
    private static partial nint LSCopyDefaultRoleHandlerForContentType(nint contentType, uint role);

    [LibraryImport(CORE_SERVICES)]
    private static partial nint LSCopyAllRoleHandlersForContentType(nint contentType, uint role);

    [LibraryImport(CORE_SERVICES)]
    private static partial int LSSetDefaultRoleHandlerForContentType(nint contentType, uint role, nint handlerBundleId);

    #endregion // Launch Services interop
}
