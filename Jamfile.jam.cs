using System;
using JamSharp.Runtime;
using System.Linq;
using Bee.Core;
using Bee.NativeProgramSupport.Building;
using Bee.Toolchain.GNU;
using Bee.Tools;
using Editor.Graphs;
using Extensions.UnityVR;
#if PLATFORM_IN_SOURCESTREE_WEBGL
using PlatformDependent.WebGL.Jam;
#endif
#if PLATFORM_IN_SOURCESTREE_PS4
using PlatformDependent.PS4.Jam;
#endif
#if PLATFORM_IN_SOURCESTREE_SWITCH
using PlatformDependent.Switch.Jam;
#endif
using PlatformDependent.Win.Etw;
using Projects.Jam;
using Projects.TestInfrastructure;
using Unity.BuildSystem;
using Unity.BuildSystem.NativeProgramSupport;
using Unity.BuildSystem.V2;
using Unity.BuildTools;
using Unity.TinyProfiling;
#if PLATFORM_IN_SOURCESTREE_LINUX
using LinuxEditor = Unity.BuildSystem.V2.LinuxEditor;
#endif
using MacEditor = Unity.BuildSystem.V2.MacEditor;
using UnpackBuildsZip = Projects.Jam.UnpackBuildsZip;

class Jamfile : ConvertedJamFile
{
    internal static void TopLevel()
    {
        CheckBuildHostCompatibleWithTarget();
        GccLikeCompiler.CCachePath = Paths.CCache;
        CLikeCompiler.VerbosePerfOutput = GlobalVariables.Singleton["OUTPUT_COMPILER_PERF"] == "1";
        NativeProgramFormat.VerbosePerfOutput = GlobalVariables.Singleton["OUTPUT_LINKER_PERF"] == "1";

        Jamrules.InitializeCurrentDir();
        using (new ColorScope(ColorCode.Light))
            Console.WriteLine($"Running build setup code for {Vars.JAM_COMMAND_LINE_TARGETS}...");

        Vars.USE_EXPERIMENTAL_MODULARITY.AssignIfEmpty("0");

        RuntimeFiles.Initialize();
        CgBatch.Initialize();
        UnityCrashHandler.Initialize();
        UnwrapCL.Initialize();

        UnpackBuildsZip.Initialize();

        if (Configuration.GlobalDefines.IsGlobalEnabled("ENABLE_UNET") && Jamrules.CommandLineCouldBeInterestedIn("UNET") && !ProjectFiles.IsRequested)
        {
            UNETServer.SetupBuild();
        }

        JobProcess.Initialize();
        if (Jamrules.CommandLineCouldBeInterestedIn("DocCombiner"))
            DocCombiner.Initialize();

        if (Jamrules.CommandLineCouldBeInterestedIn(nameof(VisualStudioInstallChecker)))
            VisualStudioInstallChecker.Initialize();

        if (!Jamrules.CommandLineCouldBeInterestedIn("UWP", "Metro", "Switch"))
            External.il2cpp.MapFileParser.SetupBuild();

        if (Jamrules.CommandLineCouldBeInterestedIn("IL2CPPAll"))
            External.il2cpp.IL2CPP.SetupBuild();

        if (Jamrules.CommandLineCouldBeInterestedIn("LiveReloadableEditorAssemblies"))
            EditorSupport.SetupEditorMonolithicDllsIfNeeded();

        // Windows specific targets
        if (HostPlatform.IsWindows || Jamrules.BuildingAllAssemblies)
        {
            if (Jamrules.BuildingAllAssemblies && HostPlatform.IsWindows ||
                Jamrules.CommandLineCouldBeInterestedIn("Editor") && !Jamrules.BuildingAllAssemblies)
            {
                using (TinyProfiler.Section("WinEditor.Setup"))
                    WinEditor.SetupInstance();
            }

            if ((Jamrules.BuildingAllAssemblies ||
                 Jamrules.CommandLineCouldBeInterestedIn("StandalonePlayer", "WinPlayer", "WinStandalone")) &&
                !(!HostPlatform.IsWindows && ProjectFiles.IsRequested))
            {
                using (TinyProfiler.Section("WinPlayer.Setup"))
                    new WinStandaloneSupport().Setup();
            }

            if (Jamrules.CommandLineCouldBeInterestedIn("WindowsStandaloneAutomation"))
                Backend.Current.AddAliasDependency("WindowsStandaloneAutomation", AutomationPlayersWindowsStandalone.ProgramPair.Program.Path);
        }

        // Mac specific targets
        if (HostPlatform.IsOSX || Jamrules.BuildingAllAssemblies)
        {
            // Editor
            if ((Jamrules.BuildingAllAssemblies && HostPlatform.IsOSX) || Jamrules.CommandLineCouldBeInterestedIn("MacEditor"))
            {
                using (TinyProfiler.Section("MacEditor.Setup"))
                    MacEditor.SetupInstance();
            }
            // Player
            var s = new MacStandaloneSupport();
            if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn(s.CommandLinesOfInterest))
            {
                using (TinyProfiler.Section("MacStandaloneSupport.Setup"))
                    s.Setup();
            }

            if (Jamrules.CommandLineCouldBeInterestedIn("OSXStandaloneAutomation"))
                Backend.Current.AddAliasDependency("OSXStandaloneAutomation", AutomationPlayersOsxStandalone.ProgramPair.Program.Path);
        }

#if PLATFORM_IN_SOURCESTREE_WEBGL
        {
            var s = new WebGLSupport();
            if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn(s.CommandLinesOfInterest))
            {
                using (TinyProfiler.Section("WebGLSupport.Setup"))
                    s.Setup();
            }
            if (Jamrules.CommandLineCouldBeInterestedIn("WebGLAutomation"))
                Backend.Current.AddAliasDependency("WebGLAutomation", AutomationPlayersWebgl.ProgramPair.Program.Path);
        }
#endif

#if PLATFORM_IN_SOURCESTREE_UNIVERSALWINDOWS
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("UWP", "Metro"))
        {
            new UWPSupport().Setup();
        }
        if (Jamrules.CommandLineCouldBeInterestedIn("MetroAutomation"))
            Backend.Current.AddAliasDependency("MetroAutomation", AutomationPlayersMetro.ProgramPair.Program.Path);
#endif

#if PLATFORM_IN_SOURCESTREE_BJM
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("BJM"))
        {
            var s = new Unity.BuildSystem.BJM.BJMSupport();
            using (TinyProfiler.Section("BJM.Setup"))
                s.Setup();
        }
#endif // PLATFORM_SOURCESTREE_BJM

#if PLATFORM_IN_SOURCESTREE_LINUX
        // Linux specific targets
        if (HostPlatform.IsLinux || Jamrules.BuildingAllAssemblies)
        {
            var s = new LinuxStandaloneSupport();
            if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn(s.CommandLinesOfInterest))
            {
                using (TinyProfiler.Section("LinuxStandaloneSupport.Setup"))
                    s.Setup();
            }

            if (Jamrules.CommandLineCouldBeInterestedIn("LinuxStandaloneAutomation"))
                Backend.Current.AddAliasDependency("LinuxStandaloneAutomation", AutomationPlayersLinuxStandalone.ProgramPair.Program.Path);

            if (Jamrules.CommandLineCouldBeInterestedIn("LinuxEditor"))
            {
                using (TinyProfiler.Section("LinuxEditor.Setup"))
                    LinuxEditor.SetupInstance();
            }

            if (HostPlatform.IsLinux && Jamrules.CommandLineCouldBeInterestedIn("LinuxBootstrapper") && !ProjectFiles.IsRequested)
                LinuxBootstrapper.SetupBuild();
        }
#endif

#if PLATFORM_IN_SOURCESTREE_ANDROID
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("Android"))
        {
            var s = new PlatformDependent.AndroidPlayer.Jam.AndroidSupport();
            using (TinyProfiler.Section("Android.Setup"))
                s.Setup();
            if (Jamrules.CommandLineCouldBeInterestedIn("AndroidAutomation"))
                Backend.Current.AddAliasDependency("AndroidAutomation", AutomationPlayersAndroid.ProgramPair.Program.Path);
        }
#endif // PLATFORM_IN_SOURCESTREE_ANDROID

#if PLATFORM_IN_SOURCESTREE_XBOXONE
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn(XboxOneSupport.commandLinesOfInterest))
        {
            if (HostPlatform.IsWindows && XboxOneSupport.GetToolchain() != null)
            {
                using (TinyProfiler.Section("XboxOne.Setup"))
                {
                    var s = new XboxOneSupport();
                    s.Setup();
                }
            }
        }
#endif // PLATFORM_IN_SOURCESTREE_XBOXONE

#if PLATFORM_IN_SOURCESTREE_SWITCH
        if ((Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("Switch")) &&
            HostPlatform.IsWindows)
        {
            var s = new Unity.BuildSystem.V2.SwitchSupport();
            using (TinyProfiler.Section("Switch.Setup"))
            {
                if (Jamrules.CommandLineCouldBeInterestedIn("Switch"))
                    s.Setup();
                else
                    s.SetupManagedOnly();
            }
        }
#endif

#if PLATFORM_IN_SOURCESTREE_LUMIN
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("Lumin"))
        {
            var s = new Unity.BuildSystem.Lumin.LuminSupport();
            using (TinyProfiler.Section("Lumin.Setup"))
                s.Setup();
            if (Jamrules.CommandLineCouldBeInterestedIn("LuminAutomation"))
                Backend.Current.AddAliasDependency("LuminAutomation", AutomationPlayersLumin.ProgramPair.Program.Path);
        }
#endif // PLATFORM_SOURCESTREE_LUMIN

#if PLATFORM_IN_SOURCESTREE_IOS
        // note: tvOS setup needs to happen before iOS, so that iOSSupport.Instance ends up being the correct iOS object
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("tvOS", "AppleTV"))
        {
            var s = new PlatformDependent.iPhonePlayer.Jam.tvOSSupport();
            PlatformDependent.iPhonePlayer.Jam.tvOSSupport.Instance = s;

            using (TinyProfiler.Section("tvOS.Setup"))
                s.Setup();
        }
        if (Jamrules.BuildingAllAssemblies || Jamrules.CommandLineCouldBeInterestedIn("iPhone", "iOS"))
        {
            var s = new PlatformDependent.iPhonePlayer.Jam.iOSSupport();
            PlatformDependent.iPhonePlayer.Jam.iOSSupport.Instance = s;
            using (TinyProfiler.Section("iOS.Setup"))
                s.Setup();
        }
        if (Jamrules.CommandLineCouldBeInterestedIn("iPhoneAutomation"))
            Backend.Current.AddAliasDependency("iPhoneAutomation", AutomationPlayersiPhone.ProgramPair.Program.Path);
#endif// PLATFORM_IN_SOURCESTREE_IOS

#if PLATFORM_IN_SOURCESTREE_PS4
        if (Jamrules.CommandLineCouldBeInterestedIn("PS4"))
        {
            var s = new PS4Support();
            using (TinyProfiler.Section("PS4.Setup"))
                s.Setup();
        }
#endif


        if (Jamrules.CommandLineCouldBeInterestedIn("Binary2Text"))
            Binary2Text.Initialize();

        if (Jamrules.CommandLineCouldBeInterestedIn("AssetCacheServer"))
        {
            AssetCacheServer.NativeProgram.EnsureValueIsCreated();
        }

        if (Jamrules.CommandLineCouldBeInterestedIn("WebExtract"))
            WebExtract.Initialize();

        if (Jamrules.CommandLineCouldBeInterestedIn("Editor", "UnityYAMLMerge"))
            UnityYAMLMerge.Initialize();

        // Editor extensions
        if (!Vars.JAM_COMMAND_LINE_TARGETS.IsIn("MacEditor", "Editor", "WinEditor", "EditorNoLump", "WinEditorNoLump", "MacEditorNoLump"))
        {
            if (HostPlatform.IsWindows)
            {
                #if PLATFORM_IN_SOURCESTREE_PS4
                if (Jamrules.CommandLineCouldBeInterestedIn("PS4"))
                {
                    if (Jamrules.CommandLineCouldBeInterestedIn("PS4Player", "PS4EditorExtensions"))
                        PS4EditorExtensions.Initialize();
                    Backend.Current.AddAliasDependency("PS4Automation", AutomationPlayersPS4.ProgramPair.Program.Path);
                }
                #endif
                #if PLATFORM_IN_SOURCESTREE_XBOXONE
                if (Jamrules.CommandLineCouldBeInterestedIn("XboxOne"))
                {
                    Backend.Current.AddAliasDependency("XboxOneAutomation", AutomationPlayersXboxOne.ProgramPair.Program.Path);
                }
                #endif
                #if PLATFORM_IN_SOURCESTREE_SWITCH
                if (Jamrules.CommandLineCouldBeInterestedIn("Switch"))
                {
                    Backend.Current.AddAliasDependency("SwitchAutomation", AutomationPlayersSwitch.ProgramPair.Program.Path);
                }
                #endif
            }
        }

        // Shader compiler plugins
        if (HostPlatform.IsWindows)
        {
            #if PLATFORM_IN_SOURCESTREE_PS4
            if (Jamrules.CommandLineCouldBeInterestedIn("PS4CgBatchPlugin"))
                PS4CgBatchPlugin.SetupBuild();
            #endif
            #if PLATFORM_IN_SOURCESTREE_SWITCH
            if (Jamrules.CommandLineCouldBeInterestedIn("Switch"))
                SwitchCgBatchPlugin.Initialize();
            #endif
        }

        // Extensions
        UnityEditorGraphs.SetupBuild();
        UnityVR.SetupBuild();

        // Documentation tools
        CombinedAssemblies.Initialize();
        if (Jamrules.CommandLineCouldBeInterestedIn("Doc") && !ProjectFiles.IsRequested)
        {
            DocBrowserModel.SetupBuild();
            DocGen.SetupBuild();
            Tools.DocTools.DocBrowserHelper.DocBrowserHelper.SetupBuild();

            // DocBrowser invokes build with "DocProject" target alias
            Backend.Current.AddAliasToAliasDependency("DocProject", "DocGen");
            Backend.Current.AddAliasToAliasDependency("DocProject", "DocBrowserModel");
        }

        // Bug reporter
        if (Jamrules.CommandLineCouldBeInterestedIn("bugreporter"))
            Tools.BugReporterV2.BugReporter.Initialize();

        if (Jamrules.CommandLineCouldBeInterestedIn("ProjectFiles", "PrepareWorkingCopy", "Automation"))
        {
            ManagedProjectFiles.Initialize();
            Projects.CSharp.UnityCSharpProjects.SetupProjects();
        }

        CSharpTool.SetupDeferredSolutions();

        // Generate various IDE project files, if needed
        ProjectFiles.Setup();

        if (Jamrules.CommandLineCouldBeInterestedIn(TestInfrastructure.TargetNames))
        {
            TestInfrastructure.Setup();
        }
    }

    private static void CheckBuildHostCompatibleWithTarget()
    {
        // Windows editor & standalone are called just "Editor" and "StandalonePlayer",
        // which in some cases leads to people trying to build them on other OSes by
        // accident. Fail that case fast & clear.
        if (!HostPlatform.IsWindows)
        {
            if (Vars.JAM_COMMAND_LINE_TARGETS.Elements.Contains("Editor") || Vars.JAM_COMMAND_LINE_TARGETS.Elements.Contains("WinEditor"))
                throw new Exception("Trying to build Windows Editor on non-Windows OS. Did you want a jam MacEditor or LinuxEditor?");

            if (Vars.JAM_COMMAND_LINE_TARGETS.Elements.Contains("StandalonePlayer") || Vars.JAM_COMMAND_LINE_TARGETS.Elements.Contains("WinPlayer"))
                throw new Exception("Trying to build Windows player on non-Windows OS. Did you want a jam MacPlayer or LinuxPlayer?");
        }
    }
}
