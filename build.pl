#!/usr/bin/env perl

package Main;

my $dir = File::Spec->rel2abs(dirname($0));
my $root = File::Spec->rel2abs(dirname($0));
chdir($root);

use strict;
use warnings;
use File::Basename qw (dirname basename fileparse);
use File::Copy;
use File::Spec;
use File::Path;
use File::Glob;
use File::Find;
use File::Basename;
use lib ('.', "./Configuration");
use BuildConfig;
use lib ('.', "./Coverrun", "./External/Perl/lib");
use lib ('Tools/Build/TargetBuildRecipes');
use Switch;
use File::chdir;
use Getopt::Long;
use Carp qw (croak carp);
use lib ('./Tools/Build');
use PrepareWorkingCopy qw (PrepareWorkingCopy);
use Tools qw (GenerateUnityConfigure RmtreeSleepy MkpathSleepy AmRunningOnBuildServer
    ProgressMessage TeamCityOnlyProgressMessage TakeFirstElementIfPrefixMatch TakeFirstElementIfAnyPrefixMatches
    HasAnyElementThatIsPrefixMatch ReadFile ConvertToLowercaseAndMatchByPrefix Jam
    OpenBrowser LaunchExecutableAndExit AmInHgRepository);

use Repositories qw (ReposFetch ReposApply ReposPin);
use BuildsZipHelper qw (DeployBuildsZipsToCorrectLocation);
use BuildNotification qw (InstallNotificationSignalHandler NotifyAndPrintSuccess NotifySuccess);
use GfxTestsReferenceImagesDownloader;

InstallNotificationSignalHandler();

#use RunTests qw (RunTests);

my %targetDescriptions = ();

#todo: register modules using a glob..
use WindowsEditor;
WindowsEditor->Register();
use WindowsStandaloneSupport;
WindowsStandaloneSupport->Register();
use MetroSupport;
MetroSupport->Register();
use WindowsEditorInstaller;
WindowsEditorInstaller->Register();
use WindowsEditorZipInstallerSet;
WindowsEditorZipInstallerSet->Register();
use TargetSupportInstaller;
TargetSupportInstaller->Register();

use UserDocumentation;
UserDocumentation->Register();
use SymbolFiles;
SymbolFiles->Register();
use LinuxSymbolFiles();
LinuxSymbolFiles->Register();
use BuiltinShaders;
BuiltinShaders->Register();
use UnityRemote;
UnityRemote->Register();

use MacEditor;
MacEditor->Register();
use MacStandaloneSupport;
MacStandaloneSupport->Register();
use iOSSupport;
iOSSupport->Register();
use AppleTVSupport;
AppleTVSupport->Register();
use MacEditorInstaller;
MacEditorInstaller->Register();
use MacEditorZipInstallerSet;
MacEditorZipInstallerSet->Register();
use MacDocumentationInstaller;
MacDocumentationInstaller->Register();
use LinuxStandaloneSupport;
LinuxStandaloneSupport->Register();
use LinuxEditor;
LinuxEditor->Register();
use LinuxEditorDebPackage;
LinuxEditorDebPackage->Register();
use LinuxEditorSelfExtractingShellScript;
LinuxEditorSelfExtractingShellScript->Register();
use LinuxEditorInstaller;
LinuxEditorInstaller->Register();
use CacheServer;
CacheServer->Register();

use WindowsBugReporter();
WindowsBugReporter->Register();
use MacBugReporter();
MacBugReporter->Register();
use LinuxBugReporter();
LinuxBugReporter->Register();
use AllAssemblies;
AllAssemblies->Register();
use ProjectTemplateLibraryFolder;
ProjectTemplateLibraryFolder->Register();

# Register remaining modular platforms
use File::Glob;
my @modules = glob('PlatformDependent/*/*.pm PlatformDependent/*/Build/*.pm');
my @platforms;
my @moduleTargets;
my $lastRegisteredName;
foreach my $path (@modules)
{
    my $module = basename($path);
    $module =~ s/\.[^.]+$//;
    my ($platform) = $path =~ /PlatformDependent\/(.+?)\//;

    # A platform may register more than one module, so only require module filename start with platform folder name
    if ($module =~ /^$platform.*/)
    {
        require $path;
        $module->Register();
        if ($lastRegisteredName)
        {
            push(@moduleTargets, $lastRegisteredName);
            $lastRegisteredName = undef;
        }
    }
}

my $zGraphicsTests;
my @targets;
my $debug = 0;
my $manual = 0;
my $numArgs = $#ARGV + 1;
my $logPath = "";
my $targetPath;
my $tempPath = "$root/build/temp";
my $scaffold = 0;
my $reset = 0;

# Whether to perform a build.
my $runBuild = 1;

# Whether to run tests.
my $runTests = 0;

# Whether to launch the editor for the current platform.
my $runEditor = 0;

# Whether to launch the standalone player for the current platform.
my $runPlayer = 0;

# Whether to run as regression suite
my $runRegressionSuite = 0;

# Filter regexp for runtime tests.
my $runRuntimeTestFilter = "";

# Filter area for runtime tests, area=somearea
my $runRuntimeTestArea = "";

# Filter string for native tests.  Not a regexp.
my $runNativeTestFilter = "";

# If true, list all native tests matching $runNativeTestFilter.
my $runListNativeTests = 0;

# If doing a prepare and this is true, only regenerate IDE project files.
my $runScaffoldWorkspace = 0;

# If true, opens the system's IDE on the AllTargets solution.
my $runOpenWorkspace = 0;

# If true, opens the system's IDE on CSharpProjects.
my $runOpenTests = 0;

# If true, opens system's IDE on CSharpProjects and Editor.sln.
my $runOpenEditorWorkspace = 0;

# If true, opens Ono changelog on the working copy's branch (unity or draft respectively).
my $runOpenOnoUnity = 0;
my $runOpenOnoDraft = 0;

# If true, opens Ono pull request on the working copy's branch (unity or draft respectively).
my $runOpenPullRequestUnity = 0;
my $runOpenPullRequestDraft = 0;

# If true, opens the Unity project on Katana on the current branch of the working copy.
my $runOpenKatana = 0;

# If true, opens the Unity project on Yamato on the current branch of the working copy.
my $runOpenYamato = 0;

# If true, displays a help message.
my $runDisplayHelp = 0;

# If true, build default resources.
my $runBuildDefaultResources = 0;

# If true, build editor resources.
my $runBuildEditorResources = 0;

# Default options for developers
my $buildDependencies = 1;
my $buildAutomation = 1;

my $codegen = "debug";
my $platform = "";
my $buildSudoPass = "";
my $incremental = 1;
my $developmentPlayer = 1;
my $zipresults = 0;
my $abvsubset = 0;
my $abi = "";
my $playbackEngines = [];
my $scriptingBackend = "default";
my $enableMonoSGen = 0;
my $lump = 1;
my $staticLib = 1;
my $enableAssertions;    # default is undef
my $headlessPlayer;      # default is undef

if ($^O eq "MSWin32")
{
    $playbackEngines = ["WindowsStandaloneSupport"];
}
if ($^O eq "darwin")
{
    $playbackEngines = ["MacStandaloneSupport"];
}
if ($^O eq 'linux')
{
    $playbackEngines = ["LinuxStandaloneSupport"];
}

my $setPlaybackEngines;
my $workingCopyOnly = 0;
my $versionOverride = "";
my $justApplyBuildsZip = 0;
my $buildsZipPath = "";
my @justReposFetch = ();
my $justReposApply = "";
my @justReposApplyRepos = ();
my $justReposPin = "";
my $reposBranchName = "";
my $noNativeTests = 0;
my $notarize = 0;
my $jamArgs = "";
my $enableBugReporterTests = 0;
my $force = 0;
my $preparingForHuman = 1;
my $sdkOverride = "";
my $userDocumentationConfig = "";
my $artifacts = "";
my $customInstallerName = "";
my $downloadGraphicsTestsUrl = "";
my $dontFetchGraphicsRepo = 0;
my $assetpipelinev2 = 0;
my $runargs = "";
my $projectTemplateLibraryFolder = 0;

my @testSuitesToRunByDefault = ("native");
my @allTestSuites = ("native", "graphics", "integration", "runtime", "performance", "substance", "cgbatch", "regression", "docs");
my @testSuitesToRun;
my $buildenv = "";

# Special case of determining build environment first
foreach my $arg (@ARGV)
{
    if ($arg =~ /buildenv=(.*)/i)
    {
        $buildenv = lc($1);
        Tools::SetBuildEnvironment($buildenv);
        print "Build Environment is $buildenv\n";
        last;
    }
}

if (AmRunningOnBuildServer())
{
    $codegen = "Release";
    $developmentPlayer = 0;
    $buildDependencies = 0;
    $preparingForHuman = 0;
    $zipresults = 1;
    if (grep { $_ =~ /zipresults=0/ } @ARGV)
    {
        $zipresults = 0;
    }
    $enableBugReporterTests = 1;
}

# See what we are supposed to do.
ProcessCommandLine();

if ($noNativeTests)
{
    $ENV{UNITY_RUN_NATIVE_TESTS_DURING_BUILD} = "0";
}

# Features can have environment variables override commandline settings, as that allows us to run custom teamcity builds
# with different settings (like make a debug build), without having to modify buildconfigs.
if ($ENV{OVERRIDE_CODEGEN}) { $codegen = $ENV{OVERRIDE_CODEGEN}; }

# Make sure codegen is correct cased or xcode won't like it
if ($^O eq 'darwin') { $codegen =~ s/(\w+)/\u\L$1/g; }

if ($^O eq 'darwin' and IsTargetSpecified("iossupport", @targets))
{
    # Workaround for mono/mcs hangups on TC iOS build agents
    print("MONO_DISABLE_SHM=1\n");
    $ENV{MONO_DISABLE_SHM} = 1;
}

# override any hg defaults to be able to properly parse hg output
$ENV{HGPLAIN} = 1;

# Convert the comma delimited playback engine string to an array
if ($setPlaybackEngines)
{
    my @temp = split(',', $setPlaybackEngines);
    $playbackEngines = \@temp;
}

if ($scaffold)
{
    if ($runScaffoldWorkspace)
    {
        system("$root/jam ProjectFiles");
        NotifySuccess("Workspace prepared");
    }
    else
    {
        PrepareDevelopmentEnvironment();
        NotifySuccess("Development environment prepared");
    }
    if (!AmRunningOnBuildServer())
    {
        system("$root/jam DocBrowserModel $jamArgs");
    }

    exit();
}

if ($runBuildEditorResources || $runBuildDefaultResources)
{
    PrepareDevelopmentEnvironment();
    BuildBuiltinResourcesModular();

    exit();
}

if ($justApplyBuildsZip)
{
    DeployBuildsZipsToCorrectLocation($buildsZipPath);
    exit();
}

if (@justReposFetch)
{
    my @repopaths = @justReposFetch;
    if (@repopaths && !$repopaths[0])
    {
        # Fix ('',) for no paths specified
        @repopaths = ();
    }
    ReposFetch(\@repopaths, $force);
    exit();
}

if ($justReposApply)
{
    ReposApply($justReposApply, \@justReposApplyRepos);
    exit();
}

if ($justReposPin)
{
    ReposPin($justReposPin, $reposBranchName);
    exit();
}

if ($downloadGraphicsTestsUrl)
{
    GetGraphicsTestArtifacts($downloadGraphicsTestsUrl, $dontFetchGraphicsRepo);
    exit();
}

if ($runOpenWorkspace)
{
    RunOpenWorkspace();
    exit();
}

if ($runOpenTests)
{
    RunOpenTests();
    exit();
}

if ($runOpenEditorWorkspace)
{
    RunOpenEditorWorkspace();
    exit();
}

if ($runOpenOnoUnity)
{
    RunOpenOnoUnity();
    exit();
}
if ($runOpenOnoDraft)
{
    RunOpenOnoDraft();
    exit();
}

if ($runOpenPullRequestUnity)
{
    RunOpenPullRequestUnity();
    exit();
}
if ($runOpenPullRequestDraft)
{
    RunOpenPullRequestDraft();
    exit();
}

if ($runOpenKatana)
{
    RunOpenKatana();
    exit();
}

if ($runOpenYamato)
{
    RunOpenYamato();
    exit();
}

if ($runDisplayHelp)
{
    RunDisplayHelp();
    exit();
}

if ($reset)
{
    print("Reset requested. Erasing entire $root/build and artifacts directories\n");
    if (-d "$root/build")
    {
        rmtree("$root/build", { keep_root => 1 }) or die("Failed to delete 'build' folder");
    }
    if (-d "$root/artifacts")
    {
        rmtree("$root/artifacts", { keep_root => 1 }) or die("Failed to delete 'artifacts' folder");
    }
    PrepareDevelopmentEnvironment();
    exit();
}

my %builtTargets = ();
my $starttime = time();

if ($runBuild)
{
    RunBuild();
}

if ($runListNativeTests)
{
    RunOrListNativeTests();
}

if ($runTests)
{
    RunTests();
}

if ($runEditor)
{
    RunEditorAndExit();
}

if ($runPlayer)
{
    RunPlayerAndExit();
}

my $duration = time() - $starttime;
NotifyAndPrintSuccess("build.pl ran for $duration seconds\n");

sub ProcessCommandLine
{
    if ($numArgs == 0)
    {
        # No commandline arguments.  Pop up menu.
        $manual = 1;
        BuildCommandLineTroughMenu();
    }
    else
    {
        GetOptions(
            "buildenv=s" => \$buildenv,
            "target=s" => \@targets,
            "builddependencies=i" => \$buildDependencies,
            "codegen=s" => \$codegen,
            "platform=s" => \$platform,
            "incremental=i" => \$incremental,
            "sudoPassword=s" => \$buildSudoPass,
            "prepare" => \$scaffold,
            "scaffold" => \$scaffold,
            "reset" => \$reset,
            "developmentPlayer=i" => \$developmentPlayer,
            "playbackEngines=s" => \$setPlaybackEngines,
            "workingCopyOnly=i" => \$workingCopyOnly,
            "versionOverride=s" => \$versionOverride,
            "zipresults=i" => \$zipresults,
            "abvsubset=i" => \$abvsubset,
            "abi=s" => \$abi,
            "scriptingBackend=s" => \$scriptingBackend,
            "applyBuildsZip=s" => \$buildsZipPath,
            "logpath=s" => \$logPath,
            "lump=s" => \$lump,
            "staticLib=s" => \$staticLib,
            "help" => \$runDisplayHelp,
            "sdkOverride=s" => \$sdkOverride,
            "userDocsConfig=s" => \$userDocumentationConfig,
            "artifacts=s" => \$artifacts,
            "customInstallerName=s" => \$customInstallerName,
            "noNativeTests" => \$noNativeTests,
            "notarize" => \$notarize,
            "jamArgs=s" => \$jamArgs,
            "enableBugReporterTests" => \$enableBugReporterTests,
            "force" => \$force,
            "preparingForHuman=s" => \$preparingForHuman,
            "assetpipelinev2" => \$assetpipelinev2,
            "enableAssertions=i" => \$enableAssertions,
            "headlessPlayer=i" => \$headlessPlayer,
            "runArgs=s" => \$runargs,
            "projectTemplateLibraryFolder" => \$projectTemplateLibraryFolder,
        ) or croak("illegal cmdline options");

        if ($versionOverride ne "")
        {
            foreach (@targets)
            {
                my $target = lc($_);
            }
            $BuildConfig::unityVersion = $versionOverride;
        }

        if ($buildsZipPath ne "")
        {
            $justApplyBuildsZip = 1;
        }

        if ($logPath ne "")
        {
            Tools::SetLogPath($logPath);
        }

        @targets = split(/,/, join(',', @targets));

        # By default, we build but if there's more stuff (i.e. commands) on the command-line,
        # turn the default off.
        if (scalar(@ARGV) > 0)
        {
            $runBuild = 0;
        }

        ####TODO: "run tests integration"
        ####TODO: "run tests graphics"
        ####TODO: "run tests assetimport"

        # If there's more stuff (i.e. non-options) on the commandline, so we expect a
        # command, like "perl build.pl test".
        while (scalar(@ARGV) > 0)
        {
            if (TakeFirstElementIfPrefixMatch(\@ARGV, 'build'))
            {
                $runBuild = 1;

                while (scalar(@ARGV) > 0)
                {
                    # Recognize 'build editor' as shortcut for respective editor target for current platform.
                    if (TakeFirstElementIfPrefixMatch(\@ARGV, 'editor'))
                    {
                        push(@targets, GetDefaultEditorTargetForCurrentPlatform());
                    }

                    # Recognize 'build player' as shortcut for respective player targets for current platform.
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'player'))
                    {
                        push(@targets, GetDefaultPlayerTargetForCurrentPlatform());
                    }

                    # Recognize 'build resources'.
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'resources'))
                    {
                        while (1)
                        {
                            if (TakeFirstElementIfPrefixMatch(\@ARGV, 'default'))
                            {
                                $runBuildDefaultResources = 1;
                            }
                            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'editor'))
                            {
                                $runBuildEditorResources = 1;
                            }
                            else
                            {
                                last;
                            }
                        }

                        if (!$runBuildEditorResources && !$runBuildDefaultResources)
                        {
                            $runBuildEditorResources = 1;
                            $runBuildDefaultResources = 1;
                        }
                    }
                    else
                    {
                        # Recognize build target name.

                        my $haveFoundTarget = 0;
                        my $arg = $ARGV[0];

                        # Look for target description matching $arg as prefix.
                        foreach my $target (%targetDescriptions)
                        {
                            if (ConvertToLowercaseAndMatchByPrefix($arg, $target))
                            {
                                push(@targets, $arg);
                                shift(@ARGV);
                                $haveFoundTarget = 1;
                                last;
                            }
                        }

                        if (!$haveFoundTarget)
                        {
                            last;
                        }
                    }
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'test'))
            {
                $runTests = 1;

                # Check which tests to run.
                while (1)
                {
                    my $testSuite = TakeFirstElementIfAnyPrefixMatches(\@ARGV, \@allTestSuites);
                    if (!$testSuite)
                    {
                        last;
                    }

                    if (HasAnyElementThatIsPrefixMatch(['runtime', 'regression'], $testSuite))
                    {
                        while (scalar(@ARGV) > 0)
                        {
                            my $arg = shift(@ARGV);
                            my $expr = '(?i:.*' . $arg . '.*)';

                            if ($arg =~ /^area=/)
                            {
                                $runRuntimeTestArea = $arg;
                            }
                            elsif ($runRuntimeTestFilter eq "")
                            {
                                $runRuntimeTestFilter = $expr;
                            }
                            else
                            {
                                $runRuntimeTestFilter .= '|' . $expr;
                            }
                        }
                    }
                    elsif ($testSuite eq "native")
                    {
                        while (scalar(@ARGV) > 0)
                        {
                            $runNativeTestFilter .= " " . shift(@ARGV);
                        }
                    }

                    push(@testSuitesToRun, $testSuite);
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'prepare'))
            {
                $scaffold = 1;

                while (1)
                {
                    if (TakeFirstElementIfPrefixMatch(\@ARGV, 'workspace'))
                    {
                        $runScaffoldWorkspace = 1;
                    }
                    else
                    {
                        last;
                    }
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'run'))
            {
                while (1)
                {
                    # Check for 'run editor'.
                    if (TakeFirstElementIfPrefixMatch(\@ARGV, 'editor'))
                    {
                        $runEditor = 1;
                    }

                    # Check for 'run player'.
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'player'))
                    {
                        $runPlayer = 1;
                    }

                    else
                    {
                        last;
                    }
                }

                # If we save neither 'editor' nor 'player', default to 'editor'.
                if (!$runEditor && !$runPlayer)
                {
                    $runEditor = 1;
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'open'))
            {
                while (1)
                {
                    # Check for 'open editor'.
                    if (TakeFirstElementIfPrefixMatch(\@ARGV, 'workspace'))
                    {
                        $runOpenWorkspace = 1;
                    }

                    # Check for 'open tests'.
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'tests'))
                    {
                        $runOpenTests = 1;
                    }
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'editorworkspace'))
                    {
                        $runOpenEditorWorkspace = 1;
                    }
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'ono'))
                    {
                        if (TakeFirstElementIfPrefixMatch(\@ARGV, 'unity'))
                        {
                            $runOpenOnoUnity = 1;
                        }
                        elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'draft'))
                        {
                            $runOpenOnoDraft = 1;
                        }
                        else
                        {
                            $runOpenOnoUnity = 1;
                        }
                    }
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'pr'))
                    {
                        if (TakeFirstElementIfPrefixMatch(\@ARGV, 'unity'))
                        {
                            $runOpenPullRequestUnity = 1;
                        }
                        elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'draft'))
                        {
                            $runOpenPullRequestDraft = 1;
                        }
                        else
                        {
                            $runOpenPullRequestUnity = 1;
                        }
                    }
                    elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'katana'))
                    {
                        $runOpenKatana = 1;
                    }
                    else
                    {
                        last;
                    }
                }

                # If we save neither 'editor' nor 'player', default to 'editor'.
                if (!$runEditor && !$runPlayer)
                {
                    $runEditor = 1;
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'list'))
            {
                while (1)
                {
                    # Check for 'list tests'.
                    if (TakeFirstElementIfPrefixMatch(\@ARGV, 'tests'))
                    {
                        while (1)
                        {
                            # Check for 'list tests native'.
                            if (TakeFirstElementIfPrefixMatch(\@ARGV, 'native'))
                            {
                                $runListNativeTests = 1;

                                while (scalar(@ARGV) > 0)
                                {
                                    $runNativeTestFilter = " " . shift(@ARGV);
                                }
                            }
                            else
                            {
                                last;
                            }
                        }
                    }

                    else
                    {
                        last;
                    }
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'repos')
                or TakeFirstElementIfPrefixMatch(\@ARGV, 'repo')
                or TakeFirstElementIfPrefixMatch(\@ARGV, 'repositories')
                or TakeFirstElementIfPrefixMatch(\@ARGV, 'repository'))
            {
                if (TakeFirstElementIfPrefixMatch(\@ARGV, 'fetch'))
                {
                    @justReposFetch = scalar(@ARGV) ? @ARGV : ('',);
                    @ARGV = ();
                }
                elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'apply'))
                {
                    scalar(@ARGV) or die("Missing command to apply");
                    $justReposApply = shift(@ARGV);
                    @justReposApplyRepos = @ARGV;
                    @ARGV = ();
                }
                elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'pin'))
                {
                    $justReposPin = scalar(@ARGV) ? shift(@ARGV) : '*';
                    $reposBranchName = scalar(@ARGV) ? shift(@ARGV) : "";
                }
                else
                {
                    die("Missing repos command (fetch, apply, branch or pin)");
                }
                if (scalar(@ARGV))
                {
                    die("Unrecognized option: $ARGV[0]");
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'download'))
            {
                $dontFetchGraphicsRepo = 0;

                if (TakeFirstElementIfPrefixMatch(\@ARGV, 'gfx-tests'))
                {
                    if (TakeFirstElementIfPrefixMatch(\@ARGV, 'nofetch'))
                    {
                        $dontFetchGraphicsRepo = 1;
                    }

                    scalar(@ARGV) or die("Missing a url to graphics tests\n");

                    $downloadGraphicsTestsUrl = shift(@ARGV);
                    if (scalar(@ARGV))
                    {
                        die("Unrecognized option: $ARGV[0]");
                    }
                }
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'help'))
            {
                $runDisplayHelp = 1;
            }
            elsif (TakeFirstElementIfPrefixMatch(\@ARGV, 'version'))
            {
                print("$BuildConfig::unityVersion\n");
                exit();
            }
            else
            {
                die "Unrecognized command: $ARGV[0]";
            }
        }
    }
}

sub BuildTarget
{
    my ($givenTargetName) = @_;

    my $targetInfo = $targetDescriptions{ (lc $givenTargetName) };
    if (not defined $targetInfo)
    {
        croak("Don't know how to build '$givenTargetName' target!");
    }
    my $target = $targetDescriptions{ (lc $givenTargetName) }->{name};

    if ($buildDependencies)
    {
        my $temp = $targetInfo->{dependencies};
        foreach my $dep (@$temp)
        {
            if (defined $builtTargets{$dep})
            {
                next;
            }
            BuildTarget($dep);
        }
    }
    $targetPath = "$root/build/$target";
    if (not -d $targetPath)
    {
        mkpath($targetPath);
    }

    my $allOptions = {};
    $allOptions->{codegen} = $codegen;
    $allOptions->{platform} = $platform;
    $allOptions->{incremental} = $incremental;
    $allOptions->{buildSudoPass} = $buildSudoPass;
    $allOptions->{developmentPlayer} = $developmentPlayer;
    $allOptions->{scriptingBackend} = $scriptingBackend;
    $allOptions->{enableMonoSGen} = $enableMonoSGen;
    $allOptions->{playbackengines} = $playbackEngines;
    $allOptions->{versionOverride} = $versionOverride;
    $allOptions->{zipresults} = $zipresults;
    $allOptions->{abvsubset} = $abvsubset;
    $allOptions->{abi} = $abi;
    $allOptions->{sdkOverride} = $sdkOverride;
    $allOptions->{jamArgs} = $jamArgs;
    $allOptions->{userDocumentationConfig} = $userDocumentationConfig;
    $allOptions->{artifacts} = $artifacts;
    $allOptions->{customInstallerName} = $customInstallerName;
    $allOptions->{lump} = $lump;
    $allOptions->{staticLib} = $staticLib;
    $allOptions->{enableBugReporterTests} = $enableBugReporterTests;
    $allOptions->{projectTemplateLibraryFolder} = $projectTemplateLibraryFolder;

    if (defined $enableAssertions)
    {
        $allOptions->{jamArgs} = $allOptions->{jamArgs} . " -sASSERTS_ENABLED=" . $enableAssertions;
    }

    my $options = {};
    print("===============================================================\n");
    print("====== Building target: $target, with the following options:\n");
    my $targetOptions = $targetInfo->{options};

    for my $configName (keys(%$targetOptions))
    {
        my $configValue = $allOptions->{$configName};
        if (not defined($configValue))
        {
            croak("Could not find value for configuration $configName");
        }
        $options->{$configName} = $configValue;
        if (ref($configValue) eq "ARRAY")
        {
            print("====== $configName: @$configValue \n");
        }
        else
        {
            print("====== $configName: $configValue \n");
        }
    }
    $options->{codegen} = $codegen;
    $options->{buildAutomation} = $buildAutomation;
    $options->{headlessPlayer} = $headlessPlayer;
    $options->{notarize} = $notarize;

    print("===============================================================\n");
    TeamCityOnlyProgressMessage("Building target: $target");

    # Kill results from previous build except if we're doing a local
    # incremental build.
    if (!$incremental || AmRunningOnBuildServer())
    {
        RmtreeSleepy($targetPath) or croak("Failed deleting $targetPath");
        MkpathSleepy($targetPath) or croak("Failed creating path: $targetPath");

        RmtreeSleepy($tempPath) or croak("Failed deleting $tempPath");
        MkpathSleepy($tempPath) or croak("Failed creating path: $targetPath");
    }
    $targetInfo->{buildfunction}->($root, $targetPath, $options);
    $builtTargets{$target} = 1;
}

sub BuildCommandLineTroughMenu
{
    my $targetConfigurations = {};
    my $selectedTargets = {};
    my %bf = %targetDescriptions;
    my @options = sort (keys(%bf));

    while (1)
    {
        ShowMenu($selectedTargets, $targetConfigurations);
        my $pick = <STDIN>;

        if ($pick)
        {
            chomp($pick);
        }
        else
        {
            # null stdin probably means ctrl-c
            $pick = "q";
        }

        if ($pick eq "q" or $pick eq "x")
        {
            exit();
        }
        if ($pick eq "c")
        {
            $codegen = $codegen eq "debug" ? "release" : "debug";
        }
        if ($pick eq "j")
        {
            $scriptingBackend =
                  $scriptingBackend eq "default" ? "il2cpp"
                : $scriptingBackend eq "il2cpp" ? "mono"
                : "default";
        }
        if ($pick eq "d")
        {
            $buildDependencies = 1 - $buildDependencies;
        }
        if ($pick eq "r")
        {
            $developmentPlayer = 1 - $developmentPlayer;
        }
        if ($pick eq "a")
        {
            $abvsubset = 1 - $abvsubset;
        }
        if ($pick eq "b")
        {
            @targets = keys %$selectedTargets;
            return;
        }
        if ($pick eq "p")
        {
            @targets = keys %$selectedTargets;
            PrepareDevelopmentEnvironment();
            exit();
        }
        if ($pick eq "f")
        {
            ReposFetch([]);
            exit();
        }
        if ($pick eq 'l')
        {
            $lump = 1 - $lump;
        }
        if ($pick =~ /^[\d]+$/)
        {
            my $count = scalar(@options);
            my $val = int($pick);
            if ($val > 0 and $val <= $count)
            {
                my $name = $options[$val - 1];

                if (exists($selectedTargets->{$name}))
                {
                    delete($selectedTargets->{$name});
                }
                else
                {
                    my $test = $bf{$name}{dependencies};
                    $selectedTargets->{$name} = 1;
                }
            }
        }
    }
}

sub PrepareDevelopmentEnvironment
{
    GenerateUnityConfigure();
    my $prepareArgs = $jamArgs;
    if ($sdkOverride ne '')
    {
        $prepareArgs = "$jamArgs -sSDK_OVERRIDE=$sdkOverride";
    }
    PrepareWorkingCopy($preparingForHuman, $platform, $prepareArgs);

    if ($workingCopyOnly == 1)
    {
        return;
    }

    if ($^O eq 'MSWin32')
    {
        PrepareDevelopmentEnvironmentWindows();
    }
    elsif (($^O eq 'darwin') || ($^O eq 'Darwin'))
    {
        PrepareDevelopmentEnvironmentMac();
    }
    elsif (($^O eq 'linux') || ($^O eq 'Linux'))
    {
        PrepareDevelopmentEnvironmentLinux();
    }
    else
    {
        die("Unsupported platform: $^O\n");
    }
}

sub PrepareDevelopmentEnvironmentModular
{
    (my $options, my @targets) = @_;

    my $target;
    foreach $target (@moduleTargets)
    {
        # If target is not passed by command line or menu option skip over it
        if (!IsTargetSpecified(lc($target), @targets))
        {
            next;
        }

        print "Running prepare on module " . $target . "\n";

        my $targetInfo = $targetDescriptions{ (lc $target) };
        if (defined($targetInfo))
        {
            if (defined($targetInfo->{preparefunction}))
            {
                $targetInfo->{preparefunction}->($root, "not-specified", $options);
            }
            else
            {
                print "WARNING; target '" . $target . "' doesn't define a prepare function\n";
            }
        }
    }
}

sub PrepareDevelopmentEnvironmentWindows
{
    if (scalar(@targets) == 0)
    {
        @targets = ("windowseditor", "windowsstandalonesupport", "metrosupport", "iossupport");
    }

    my $options = {
        "codegen" => $codegen,
        "developmentPlayer" => $developmentPlayer,
        "incremental" => $incremental,
        "scriptingBackend" => $scriptingBackend
    };

    if (IsTargetSpecified("iossupport", @targets)) { iOSSupport::PrepareiOSSupport($root, "$root/build/iOSSupport", $options); }
    if (IsTargetSpecified("metrosupport", @targets)) { MetroSupport::PrepareMetroSupport($root, "$root/build/MetroSupport", $options); }

    PrepareDevelopmentEnvironmentModular($options, @targets);
}

sub PrepareDevelopmentEnvironmentMac
{
    if (scalar(@targets) == 0)
    {
        @targets = ("maceditor", "iossupport");
    }

    my $options = {
        "codegen" => $codegen,
        "developmentPlayer" => $developmentPlayer,
        "incremental" => $incremental,
        "scriptingBackend" => $scriptingBackend
    };

    # Setup defaults for xcode lazy symbol loading to 0.
    # This makes it possible to debug builds made with jam
    system("defaults write com.apple.Xcode PBXDebugger.LazySymbolLoading 0");

    if (IsTargetSpecified("maceditor", @targets)) { MacEditor::PrepareEditor($root, "$root/build/MacEditor", $options, $preparingForHuman); }
    if (IsTargetSpecified("iossupport", @targets)) { iOSSupport::PrepareiOSSupport($root, "$root/build/iOSSupport", $options); }

    PrepareDevelopmentEnvironmentModular($options, @targets);
}

sub PrepareDevelopmentEnvironmentLinux
{
    if (scalar(@targets) == 0)
    {
        @targets = ("linuxstandalonesupport");
    }

    my $options = {
        "codegen" => $codegen,
        "developmentPlayer" => $developmentPlayer,
        "incremental" => $incremental
    };

    PrepareDevelopmentEnvironmentModular($options, @targets);
}

sub BuildBuiltinResourcesModular
{
    my $target;
    foreach $target (@moduleTargets)
    {
        # If target is not passed by command line skip over it
        if (!IsTargetSpecified(lc($target), @targets))
        {
            next;
        }

        print "Running BuildCgBatch on module " . $target . "\n";

        my $targetInfo = $targetDescriptions{ (lc $target) };
        if (defined($targetInfo))
        {
            if (defined($targetInfo->{cgbatchfunction}))
            {
                $targetInfo->{cgbatchfunction}->($root, "not-specified", 0);
            }
            else
            {
                print "WARNING; target '" . $target . "' doesn't define a CgBatchPlugin function\n";
            }
        }
    }

    # Finnaly run build_resources
    RunBuildResources();
}

# Return true if $target equals a lowercased entry in @targets
# Note: $target must be lowercase!
sub IsTargetSpecified
{
    (my $target, my @targets) = @_;
    return (grep (lc($_) eq $target, @targets));
}

sub ShowMenu
{
    (my $selectedTargets, my $targetConfigurations) = $_[0];

    my $config = "release";
    if ($debug == 1)
    {
        $config = "debug";
    }
    for (my $i = 0; $i < 3; ++$i)
    {
        print("\n");
    }
    print("====== Current Build Plan ==========\n");

    my %bf = %targetDescriptions;

    my $counter = 1;

    my $dependencies = {};
    foreach my $selected (keys %$selectedTargets)
    {
        my $deps = $bf{$selected}{dependencies};
        foreach my $dep (@$deps)
        {
            $dependencies->{$dep} = 1;
        }
    }

    foreach my $key (sort (keys %bf))
    {
        my $selected;
        my $dependency;

        if (exists $selectedTargets->{$key})
        {
            $selected = 1;
        }
        else
        {
            if (exists $dependencies->{$key})
            {
                $dependency = 1;
            }
            else
            {
                $dependency = 0;
            }
        }

        if ($counter < 10)
        {
            print(" ($counter)  [");
        }
        else
        {
            print(" ($counter) [");
        }
        print($selected ? "x" : " ");
        print("]  [");

        if ($selected || ($dependency && $buildDependencies))
        {
            print("Build ");
        }
        elsif (!$selected && !$dependency)
        {
            print("None  ");
        }
        else
        {
            print("Assume");
        }
        print("] ");

        my $name = $targetDescriptions{$key}{name};
        print($name);
        my $globalConfig = {
            codegen => $codegen,
            scriptingBackend => $scriptingBackend,
            developmentPlayer => $developmentPlayer,
            abvsubset => $abvsubset,
            abi => $abi,
            versionOverride => $versionOverride,
            platform => $platform,
            lump => $lump,
            staticLib => $staticLib,
            enableBugReporterTests => $enableBugReporterTests,
            headlessPlayer => $headlessPlayer
        };
        my $options = $targetDescriptions{$key}{options};

        if (not defined($targetConfigurations->{$key}))
        {
            $targetConfigurations->{$key} = {};
        }
        my $config = $targetConfigurations->{$key};
        for my $configName (keys(%$options))
        {
            if ($configName eq "incremental")
            {
                next;
            }
            my $configValue = $globalConfig->{$configName};
            if (not defined($configValue))
            {
                my $allConfigValues = $options->{$configName};
                $configValue = @$allConfigValues[1];
                if (not defined($configValue))
                {
                    $configValue = '';
                }
            }
            print(" [$configName=$configValue]");
        }

        print("\n");
        $counter++;
    }

    print("\n");
    print("====== Development Environment Setup ======\n");
    print("(f) Update all present tracked repositories\n");
    print("(p) Prepare development environment\n");
    print("(t) Run TeamCity environment cleaner\n");
    print("(q) Exit\n");
    print("\n");
    print("====== Commands =========\n");
    print("(c) Flip codegeneration (current=$codegen)\n");
    print("(j) Flip scriptingBackend (current=$scriptingBackend)\n");
    print("(d) Flip dependencybuilding (current=" . ($buildDependencies ? "Building Dependencies" : "Assuming dependencies are prebuilt") . ")\n");
    print("(r) Flip development player (current=" . ($developmentPlayer ? "Development Player" : "Non-Development Player") . ")\n");
    print("(a) Flip abvsubset (current=$abvsubset)\n");
    print("(l) Flip lump (current=$lump)\n");
    print("(b) Build selected targets\n");
    print("\n");
}

sub ReplaceText
{
    my ($filein, $fileout, %fields) = @_;

    my $data;
    {
        open(my $FH, $filein) or croak("FAILED: unable to open $filein for reading!");
        $data = join '', <$FH>;
    }
    my $re = join('|', reverse(sort (keys(%fields))));

    # Protect against anyone providing us with a hash that has un-initialized elements
    foreach (keys(%fields))
    {
        if (not defined($fields{$_}))
        {
            $fields{$_} = "";
        }
    }

    $data =~ s|($re)|$fields{$1}|ge;

    open(my $FH, ">$fileout") or croak("FAILED: unable to open $fileout for writing!");
    print($FH $data);
}

sub RegisterTarget
{
    my ($name, $data) = @_;
    my $prepareFunction;
    my $buildFunction;
    my $cgbatchFunction;

    switch ($^O)
    {
        case 'MSWin32'
        {
            $prepareFunction = $data->{windowspreparefunction};
            $buildFunction = $data->{windowsbuildfunction};
            $cgbatchFunction = $data->{windowscgbatchfunction};
        }
        case 'darwin' { $prepareFunction = $data->{macpreparefunction}; $buildFunction = $data->{macbuildfunction}; }
        case 'linux' { $prepareFunction = $data->{linuxpreparefunction}; $buildFunction = $data->{linuxbuildfunction}; }
        else { print("Unknown platform $^O!\n"); }
    }

    if (not defined($buildFunction))
    {
        return;
    }

    $data->{name} = $name;
    if (not defined($data->{dependencies}))
    {
        $data->{dependencies} = [];
    }
    $data->{preparefunction} = $prepareFunction;
    $data->{buildfunction} = $buildFunction;
    $data->{cgbatchfunction} = $cgbatchFunction;
    $targetDescriptions{ lc $name } = $data;
    $lastRegisteredName = $name;
}

sub GetDefaultEditorTargetForCurrentPlatform
{
    switch ($^O)
    {
        case 'MSWin32' { return 'WindowsEditor'; }
        case 'darwin' { return 'MacEditor'; }
        case 'linux' { return 'LinuxEditor'; }
        else { print("Unknown editor platform $^O!\n"); }
    }

    return 0;
}

sub GetDefaultPlayerTargetForCurrentPlatform
{
    switch ($^O)
    {
        case 'MSWin32' { return 'WindowsStandaloneSupport'; }
        case 'darwin' { return 'MacStandaloneSupport'; }
        case 'linux' { return 'LinuxStandaloneSupport'; }
        else { print("Unknown player platform $^O!\n"); }
    }

    return 0;
}

sub GetExecutablePathForTarget
{
    my ($targetName) = @_;

    my $target = $targetDescriptions{ lc($targetName) };
    my $executable = $target->{'executable'};
    my $executablePath = "$root/build/$targetName/$executable";

    return $executablePath;
}

sub RunTests
{
    # If no specific test suite was specified, use the default set of suites.
    if (scalar(@testSuitesToRun) == 0)
    {
        @testSuitesToRun = @testSuitesToRunByDefault;
    }

    if (HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "native"))
    {
        RunOrListNativeTests();
    }

    if (HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "integration"))
    {
        RunIntegrationTests();
    }

    if (HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "runtime") or HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "regression"))
    {
        $runRegressionSuite = HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "regression");
        RunRuntimeTests();
    }

    if (HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "graphics"))
    {
        RunGraphicsTests();
    }

    if (HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "cgbatch"))
    {
        RunCgBatchTests();
    }

    if (HasAnyElementThatIsPrefixMatch(\@testSuitesToRun, "docs"))
    {
        RunQuickDocsVerification();
    }
}

sub RunOrListNativeTests
{
    # If no targets were explicitly set, default to running unit tests from the editor.
    if (scalar(@targets) == 0)
    {
        push(@targets, GetDefaultEditorTargetForCurrentPlatform());
    }

    foreach my $target (@targets)
    {
        my $executablePath = GetExecutablePathForTarget($target);
        my $args;
        if ($assetpipelinev2)
        {
            $args .= " -assetpipelinev2";
        }

        # Check whether we are supposed to actually run the tests
        # or only list them.
        if ($runListNativeTests)
        {
            $args .= " -listNativeTests";
        }
        else
        {
            $args .= " -runNativeTests";
        }

        if ($runNativeTestFilter ne "")
        {
            # Append test filter.
            $args .= $runNativeTestFilter;
        }

        my $useLogRedirect = 0;
        my $lowerTarget = lc($target);
        my $logOutputPath;
        if (defined($targetDescriptions{$lowerTarget}->{requiresStdoutRedirect}) && $targetDescriptions{$lowerTarget}->{requiresStdoutRedirect})
        {
            # On Windows, we won't see the stdout output from the editor since it is a GUI app.
            # Redirect all logging output to a file and then dump that file to stdout.
            # Don't use -unitTestsLog as it uses an XML format.
            $logOutputPath = "$executablePath.testLog";
            $args .= " -logfile $logOutputPath";
            $useLogRedirect = 1;
        }

        # On OSX, run the binary directly instead of using "open".  Otherwise we run
        # into some problems with the file system layer not being able to create files
        # (I suspect it's because the OSX platform code has trouble locating the application
        # directory correctly).
        if ($^O eq 'darwin' and $executablePath =~ /.*\/([^\.]+)\.app$/)
        {
            $executablePath = "$executablePath/Contents/MacOS/$1";
        }

        ####TODO: launch asynchronously and spill log to stdout until editor process exits
        system("$executablePath $args");

        if ($useLogRedirect)
        {
            my $logOutput = ReadFile($logOutputPath);
            print $logOutput;
        }
    }
}

sub RunIntegrationTests
{
    my $runPlPath = "$root/Tests/Unity.IntegrationTests/run.pl";
    my $args = "--testresultsxml=$tempPath/TestResult.xml";
    system("perl $runPlPath $args");
}

sub RunRuntimeTests
{
    my $runPlPath = "$root/Tests/Unity.RuntimeTests.AllIn1Runner/run.pl";
    my $args;

    if ($runRuntimeTestFilter ne "")
    {
        $args .= " -testfilter=\"$runRuntimeTestFilter\"";
    }

    if ($platform ne "")
    {
        $args .= " -platform=$platform";
    }

    if ($runRegressionSuite)
    {
        $args .= " --regressionsuite";
    }

    if ($scriptingBackend ne "")
    {
        $args .= " --scriptingbackend=$scriptingBackend";
    }

    if ($runRuntimeTestArea ne "")
    {
        $args .= " --$runRuntimeTestArea";
    }

    system("perl $runPlPath $args");
}

sub RunGraphicsTests
{
    my $runPlPath = "$root/Tests/Unity.GraphicsTestsRunner/run.pl";

    my $args;

    if ($platform ne "")
    {
        $args .= "-platform $platform";
    }

    system("perl $runPlPath $args");
}

sub RunCgBatchTests
{
    Jam($root, 'CgBatchTests', $codegen, $platform, $incremental);
}

sub RunQuickDocsVerification
{
    system("perl $root/Tools/DocTools/verify.pl");
}

sub RunEditorAndExit
{
    my $executablePath = GetExecutablePathForTarget(GetDefaultEditorTargetForCurrentPlatform());
    LaunchExecutableAndExit($executablePath, "-debugHub" . ' ' . $runargs);
}

sub RunPlayerAndExit
{
    my $executablePath = GetExecutablePathForTarget(GetDefaultPlayerTargetForCurrentPlatform());

    LaunchExecutableAndExit($executablePath);
}

sub GetUnversionedFiles
{
    my @files = `hg status -u`;
    chomp @files;
    return sort @files;
}

sub RunBuild
{
    # Build process should not produce new files that are not under version
    # control and outside of VCS ignore locations.
    my $checkUnversioned = AmInHgRepository();
    my @unversioned1;

    # Some of our build targets today do produce unversioned files;
    # until that is fixed properly allow them through
    my @targetsAllowedToProduceUnversionedFiles = (
        qr/AppleTVSupport/i,    # two files under External/XcodeAPI/Xcode.Tests
        qr/iOSSupport/i,        # two files under External/XcodeAPI/Xcode.Tests
        qr/PS4Player/i,         # PS4Player_Il2cpp.map in root
        qr/WindowsBootStrapper/i,    # Tools/Installers/WindowsEditor/UnityPaths.nsh
        qr/TargetSupportInstaller/i, # Tools/Installers/WindowsEditor/UnityPaths.nsh
        qr/Windows.*Installer/i      # Tools/Installers/WindowsEditor/UnityPaths.nsh
    );
    foreach my $re (@targetsAllowedToProduceUnversionedFiles)
    {
        if (grep (lc($_) =~ $re, @targets))
        {
            $checkUnversioned = 0;
            last;
        }
    }
    @unversioned1 = GetUnversionedFiles() if $checkUnversioned;

    GenerateUnityConfigure($versionOverride);
    my $prepareArgs = $jamArgs;
    if ($sdkOverride ne '')
    {
        $prepareArgs = "$jamArgs -sSDK_OVERRIDE=$sdkOverride";
    }
    PrepareWorkingCopy(0, $platform, $prepareArgs);

    foreach my $target (@targets)
    {
        BuildTarget($target);
    }

    if ($checkUnversioned)
    {
        my @unversioned2 = GetUnversionedFiles();
        my %hashUnversioned1;
        @hashUnversioned1{@unversioned1} = 1;
        my @newUnversioned = grep { !exists $hashUnversioned1{$_} } @unversioned2;
        if (@newUnversioned)
        {
            print "Build of @targets produced " . @newUnversioned . " new unversioned files:\n";
            foreach my $f (@newUnversioned)
            {
                print "  " . $f . "\n";
            }
            die "Build process should not produce new unversioned files in source checkout!";
        }
    }

    if (AmInHgRepository() and AmRunningOnBuildServer())
    {
        my $trackedApiDiff = `hg diff -I **.api`;
        if ($? != 0)
        {
            die("`hg diff -I **.api` exited with non-zero code: " . $? . "\n" . "Output: " . $trackedApiDiff . "\n");
        }
        if ($trackedApiDiff)
        {
            print("Build of @targets modified tracked API files. Diff:\n");
            print($trackedApiDiff . "\n");
            die(
                "Build process on build server should not modify tracked API files!\nTo regenerate these files locally, build `jam AllAssemblies` or the specific platform.\n"
            );
        }
    }
}

sub RunBuildResources
{
    my $build_resourcesPath = "$root/Tools/build_resources.pl";

    if ($runBuildDefaultResources)
    {
        system("perl $build_resourcesPath -builtin -extra") eq 0 or die("Failed to build built-in resources, check log files in the artifacts.");
    }

    if ($runBuildEditorResources)
    {
        system("perl $build_resourcesPath -editor") eq 0 or die("Failed to build editor resources, check log files in the artifacts.");
    }
}

sub RunOpenWorkspace
{
    switch ($^O)
    {
        case 'MSWin32' { my $suffix = basename($root); system("start $root/Projects/VisualStudio/AllTargets-$suffix.sln"); }
        case 'darwin' { system("open $root/Projects/Xcode/AllTargets.xcodeproj"); }
        case 'linux' { print("Open AllTargets project not implemented on Linux!\n"); }
        else { print("Unknown platform $^O!\n"); }
    }
}

sub RunOpenTests
{
    switch ($^O)
    {
        case 'MSWin32' { system("start $root/Projects/CSharp/Unity.CSharpProjects.gen.sln"); }
        case 'darwin' { system("open $root/Projects/CSharp/Unity.CSharpProjects.gen.sln"); }
        case 'linux' { system("xdg-open $root/Projects/CSharp/Unity.CSharpProjects.gen.sln\n"); }
        else { print("Unknown platform $^O!\n"); }
    }
}

sub RunOpenEditorWorkspace
{
    switch ($^O)
    {
        case 'MSWin32'
        {
            my $suffix = basename($root);
            system("start $root/Projects/CSharp/Unity.CSharpProjects.gen.sln");
            system("start $root/Projects/VisualStudio/AllTargets-$suffix.sln");
        }
        case 'darwin' { system("open $root/Projects/CSharp/Unity.CSharpProjects.gen.sln"); system("open $root/Projects/Xcode/AllTargets.xcodeproj"); }
        case 'linux' { print("Open EditorWorkspace not implemented on Linux!\n"); }
        else { print("Unknown platform $^O!\n"); }
    }
}

sub RunDisplayHelp
{
    print("Without options, brings up interactive menu.\n");
    print("\n");
    print("Options:\n");
    print("  --platform=<list>           Build/run given platforms.\n");
    print("  --target=<list>             Build given targets.\n");
    print("  --prepare                   Prepare working copy and generate IDE workspace.\n");
    print("  --reset                     Delete build/artifacts folders and generate IDE workspace.\n");
    print("  --codegen=debug|release     Whether to build debug or release binaries (default: debug).\n");
    print("  --developmentPlayer=1|0     Whether to include profiler/script-debugging in Player build (default 1 for local builds).\n");
    print("  --incremental=1|0           Whether to do an incremental build or full rebuild (default for local builds).\n");
    print("  --abvsubset=1|0             Whether to build only a subset of build configurations that are needed by tests (default: false).\n");
    print(
        "  --abi=[armv7|x86|arm64]     Whether to build only a specific CPU architecture, currently only used by Android. (default: empty, will build all ABIs).\n"
    );
    print("  --scriptingBackend=default|mono|il2cpp     Whether to build with mono or il2cpp scripting backend (default: mono).\n");
    print("  --lump=1|0                  Enable/Disable source file lumping.\n");
    print("  --applyBuildsZip=<path>     Extracts a 'container' zip file and applies platform-specific builds.zip files to the correct place.\n");
    print("  --noNativeTests             Suppress execution of native tests during build (equivalent to setting UNITY_RUN_NATIVE_TESTS_DURING_BUILD=0).\n");
    print("  --notarize                  Upload the build to Apple Notary Service and staple the ticket to the distribution.\n");
    print("  --enableBugReporterTests    Enable execution of bugreporter tests during build (default on build agents).\n");
    print("  --jamArgs=<arguments>       Additional arguments to be passed to jam when building. Only supported on certain targets.\n");
    print("  --force                     When updating to another revision after fetching, override any local changes and purge all.\n");
    print("  --projectTemplateLibraryFolder Whether to pre-populate the Library folder of project templates.  Applies to the 'Editor' target only.\n");
    print("\n");
    print("build                         Build default target(s).\n");
    print("build editor                  Build editor for current platform.\n");
    print("build player                  Build player for current platform.\n");
    print("build <target>                Build given target (example: iOSPlayer).\n");
    print("build resources               Rebuild all built-in resources.\n");
    print("build resources default       Rebuild default resources.\n");
    print("build resources editor        Rebuild editor resources.\n");
    print("version                       Print Unity version string.\n");
    print("\n");
    print("run                           Launch editor.\n");
    print("run editor                    Launch editor.\n");
    print("run player                    Launch standalone player for platform (requires project installed into build folder).\n");
    print("\n");
    print("test                          Run default test suites.\n");
    print("test native                   Run native tests.\n");
    print("test native <name>            Run all native tests with \"name\" in the test or suite name.\n");
    print("test runtime                  Run runtime tests.\n");
    print("test runtime <name>           Run all runtime tests with \"name\" in their name.\n");
    print(
        "test runtime area=<name>      Run all runtime tests from a specific area, like Networking or Physics (see Tests/Unity.RuntimeTests.Framework/whitelist.txt).\n"
    );
    print("test regression               Run regression tests.\n");
    print("test regression <name>        Run all regression tests with \"name\" in their name.\n");
    print("test docs                     Run quick verification of docs.\n");
    print("\n");
    print("open tests                    Open Unity.CSharpProjects.gen.sln.\n");
    print("open workspace                Open AllTargets solution.\n");
    print("open editorworkspace          Open Unity.CSharpProjects.gen.sln and Editor.sln solutions.\n");
    print("open ono                      Open current branch in Ono unity/unity repository.\n");
    print("open ono draft                Open current branch in Ono unity/draft repository.\n");
    print("open pr                       Open pull request for current branch in Ono unity/unity repository.\n");
    print("open pr draft                 Open pull request for current branch in Ono unity/draft repository.\n");
    print("open katana                   Open current branch on Katana.\n");
    print("\n");
    print("list tests native             List native tests.\n");
    print("list tests native <name>      List native tests with \"name\" in their test or suite name.\n");
    print("\n");
    print("prepare                       Run prepare step.\n");
    print("prepare workspace             (Re-)generate solutions.\n");
    print("\n");
    print("repos fetch <names>           Clone or update a tracked repo - such as Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder.\n");
    print("repos fetch                   Fetch and synchronize all local tracked repos.\n");
    print("repos apply <command> <names> Apply shell command to tracked repos.\n");
    print("repos pin                     Pin repository to specific revision. Only relevant for Janitors.\n");
    print("\n");
    print("download gfx-tests [nofetch] <url>  Download preselected collection of reference images and extracts them to graphics test repository.\n");
    print("   [nofetch]                        Optional argument for download commands, that skips fetching of the graphic repo if it is already\n");
    print("                                    checked out and download reference images of specific Graphics Test run specified by <command>.\n");
    print("\n");
    print("All command words can be abbreviated; all matching is done against prefixes (e.g. \"t n\" is the same as \"test native\").\n");
}

sub GetBranchName
{
    my $branch = "";
    if (-d ".hg")
    {
        $branch = `hg branch`;
    }
    elsif ((-d ".git") || (-f ".git"))
    {
        $branch = `git rev-parse --abbrev-ref HEAD`;
    }
    chomp($branch);
    return $branch;
}

# Open changelog of current branch in Ono (unity or draft respectively)
sub RunOpenOnoUnity
{
    my $branch = GetBranchName();
    if (-d ".hg")
    {
        OpenBrowser("https://ono.unity3d.com/unity/unity/changelog?branch=$branch");
    }
    elsif ((-d ".git") || (-f ".git"))
    {
        OpenBrowser("https://ono.unity3d.com/unity/from-git/changelog?branch=$branch");
    }
}

sub RunOpenOnoDraft
{
    my $branch = GetBranchName();
    if (-d ".hg")
    {
        OpenBrowser("https://ono.unity3d.com/unity/draft/changelog?branch=$branch");
    }
    elsif ((-d ".git") || (-f ".git"))
    {
        OpenBrowser("https://ono.unity3d.com/unity/from-git/changelog?branch=$branch");
    }
}

# Open pull request from current branch in Ono (unity or draft respectively)
sub RunOpenPullRequestUnity
{
    my $branch = GetBranchName();
    if (-d ".hg")
    {
        OpenBrowser("https://ono.unity3d.com/unity/unity/pull-request/new?branch=$branch");
    }
    elsif ((-d ".git") || (-f ".git"))
    {
        OpenBrowser("https://ono.unity3d.com/unity/from-git/pull-request/new?branch=$branch");
    }
}

sub RunOpenPullRequestDraft
{
    my $branch = GetBranchName();
    if (-d ".hg")
    {
        OpenBrowser("https://ono.unity3d.com/unity/draft/pull-request/new?branch=$branch");
    }
    elsif ((-d ".git") || (-f ".git"))
    {
        OpenBrowser("https://ono.unity3d.com/unity/from-git/pull-request/new?branch=$branch");
    }
}

## Open Katana Unity project on current branch.
sub RunOpenKatana
{
    my $branch = GetBranchName();
    OpenBrowser("http://katana.bf.unity3d.com/projects/Unity/builders?unity_branch=$branch");
}

sub RunOpenYamato
{
    my $branch = `git rev-parse --abbrev-ref HEAD`;
    OpenBrowser("https://yamato.cds.internal.unity3d.com/jobs/3-unity/tree/$branch");
}

sub GetGraphicsTestArtifacts
{
    my ($downloadGraphicsTestsUrl, $dontFetchGraphicsRepo) = @_;
    my $gfxTestProjectFolder = "Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder";
    my $logOutputPath = "build/log/GraphicsTestsReferenceImages";
    my $logFileName = "Extract.log";
    my $updatedFiles = "";

    my $GfxTestsReferenceImagesDownloader =
        GfxTestsReferenceImagesDownloader->new($downloadGraphicsTestsUrl, $gfxTestProjectFolder, $logOutputPath, $logFileName, $dontFetchGraphicsRepo);
    $updatedFiles = $GfxTestsReferenceImagesDownloader->DownloadAndExtractReferenceImages();
    my $newGraphicsBranchName = $GfxTestsReferenceImagesDownloader->NewGraphicsBranchName();

    print(    "\nThe reference images have been downloaded to $gfxTestProjectFolder and have"
            . " been added to the repository. Current status of the files in the repository is:\n");
    print("$updatedFiles\n\n");
    print(    "If you are uncertain about the files that have been downloaded you can check the\n $logOutputPath/$logFileName"
            . " and compare the downloaded files to the added ones.\n\n");
    print("To commit and push the changes use the following commands:\n");
    if ($newGraphicsBranchName ne "")
    {
        print("hg --cwd Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder branch $newGraphicsBranchName\n");
        print("hg --cwd Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder ci -m \"Updated reference images from $downloadGraphicsTestsUrl\"\n");
        print("hg --cwd Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder push -r . --new-branch\n");
    }
    else
    {
        print("hg --cwd Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder ci -m \"Updated reference images from $downloadGraphicsTestsUrl\"\n");
        print("hg --cwd Tests/Unity.GraphicsTestsRunner/GfxTestProjectFolder push -r .\n");
    }
}
