// Les tests lisent les textes en français (comme ceux du Mac), quelle que soit la langue de la machine qui les lance.
using System.Runtime.CompilerServices;

namespace FLShortcut.Core.Tests;

internal static class TestSetup
{
    [ModuleInitializer]
    internal static void French() => Loc.English = false;
}
