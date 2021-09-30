using System;
using System.Linq;
using JamSharp.Runtime;
using static JamSharp.Runtime.BuiltinRules;
using NiceIO;
using Unity.BuildSystem;
using Unity.BuildSystem.NativeProgramSupport;
using Unity.BuildTools;

[Help(
    "AllAssemblies",
    "Managed engine assemblies",
    configs: Help.Configs.None,
    category: Help.Category.Other,
    notes: new[] {"Use this to update .api files when changing public scripting APIs"})]
class Jamrules : ConvertedJamFile
{
    static void Setup()
    {
        Projects.Jam.Rules.FastCopyDirectory.TopLevel();
        Configuration.GlobalDefines.TopLevel();

        Vars.DEVELOPMENT_PLAYER.AssignIfEmpty("1");

        if (!Vars.SCRIPTING_BACKEND.IsEmpty)
            Vars.ScriptingBackendSetExplicitly = false;
        else
            Vars.SCRIPTING_BACKEND.Assign("mono");

        Vars.USE_EXPERIMENTAL_MODULARITY.AssignIfEmpty("0");

        if (HostPlatform.IsWindows)
        {
            // The executable may be a GUI app (like the editor) in which case we won't see any of the
            // log output.  So, if the executable supports it, redirect to a log file and dump that to
            // the terminal after all tests have run.
            JamCore.RegisterAction(
                "RunUnitTests",
@"
        cd $(executable:T:D:\)
        ""$(executable:T:\)"" -runNativeTests -logfile ""$(executable:T:\).testLog""
        set EXITCODE=%ERRORLEVEL%
        if exist ""$(executable:T:\).testLog"" type ""$(executable:T:\).testLog""
        exit /b %EXITCODE%

");
        }
        else
        {
            JamCore.RegisterAction("RunUnitTests", @"
        cd $(executable:T:D)
        $(executable:T) -runNativeTests

");
        }

        // Set up global targets to build all needed assemblies for docs, tests or script api analysis
        Depends("AllAssemblies", "AllEngineAssemblies");
        Depends("AllAssemblies", "AllEditorAssemblies");
    }

    public static void SetupUnitTestsForApplication(JamTarget application, JamList name)
    {
        if (ProjectFiles.IsRequested)
            return;

        JamList testTarget = $"{name}Tests";

        // If we want to run unit tests during builds, make the application
        // dependent on the tests.
        if (GlobalVariables.Singleton["UNITY_RUN_NATIVE_TESTS_DURING_BUILD"] == "1")
            Depends(name, testTarget, application);

        "executable".On(testTarget).Assign(application);
        InvokeJamAction("RunUnitTests", testTarget, application, allowUnwrittenOutputFiles: true);
    }

    internal static void EnableUnitTestsIfNotBuildingForInstaller(NativeProgram np)
    {
        if (GlobalVariables.Singleton["UNITY_BUILDING_FOR_INSTALLER"] == "1")
            np.Defines.Add("ENABLE_UNIT_TESTS=0");
        else
            np.Defines.Add("ENABLE_UNIT_TESTS=1");
    }

    internal static bool BuildingAllAssemblies { get; }
        = Vars.JAM_COMMAND_LINE_TARGETS.Contains("AllEngineAssemblies") ||
            Vars.JAM_COMMAND_LINE_TARGETS.Contains("AllAssemblies");

    // Returns true if any build targets passed to jam build contains (as a substring) any of
    // the search strings, case insensitive. So for example querying for "ios"
    // will return true if building "iOSPlayer" too.
    internal static bool CommandLineCouldBeInterestedIn(params string[] searchStrings)
    {
        if (ProjectFiles.IsRequested)
            return true;

        foreach (var str in searchStrings)
        {
            if (Vars.JAM_COMMAND_LINE_TARGETS.Any(target => target.IndexOf(str, StringComparison.InvariantCultureIgnoreCase) >= 0))
                return true;
        }
        return false;
    }

    static bool _rulesDone;

    public static void InitializeCurrentDir()
    {
        var unityRoot = Paths.UnityRoot.ToString(SlashMode.Forward);
        Environment.CurrentDirectory = unityRoot;

        if (!_rulesDone)
        {
            _rulesDone = true;
            Setup();
        }
    }
}
