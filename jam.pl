#!/usr/bin/perl

use strict;
use warnings;
use English;
use Digest::MD5 qw(md5_hex);
use File::Basename qw(dirname basename fileparse);
use File::Spec;
use List::Util qw(first);

my $top;

BEGIN
{
    $top = File::Spec->rel2abs(dirname($0));
}
use lib ("$top/Tools/Build");
use lib ("$top/Tools/Unity.BuildSystem");
use Tundra qw (call_tundra);
use Frontend qw (prepare_build_program);
use PrepareWorkingCopy qw (PrepareExternalDependency PrepareMonoBleedingEdge);
use lib ('$top/External/Perl/lib');
use Cwd;

my @tundraargs;
my @manualtundraargs;
my $seenTundraFlag = 0;

my @args = ();
my $forceFrontEnd = 0;
my $verifyUpToDate = 0;

my $cleanedIncomingArguments = "";
my $incomingArgumentsToHash = "";

my @processArgs = @ARGV;

while (my $el = shift(@processArgs))
{
    $el = AdjustArgCaseSensitivity($el);

    if ($seenTundraFlag)
    {
        push(@manualtundraargs, $el);
        next;
    }
    if ($el eq "-dx" || $el eq "-dax" || $el eq "-dxa" || $el eq "-dg")
    {
        push(@tundraargs, "-v");
        next;
    }
    if ($el eq "-a")
    {
        push(@tundraargs, "-l");
        next;
    }
    if ($el eq "-f")
    {
        $forceFrontEnd = 1;
        next;
    }
    if ($el eq "--verify-up-to-date")
    {
        $verifyUpToDate = 1;
        next;
    }
    if ($el eq "--tundra")
    {
        $seenTundraFlag = 1;
        next;
    }
    if ($el =~ m/-sDEBUG=./)
    {
        die(
            "Debugging the buildsystem no longer happens through -sDEBUG=1, but by opening Tools/Unity.BuildSystem/Unity.BuildSystem.gen.sln in Rider or VisualStudio, setting the working directiry to your repo root, and setting the program arguments to something like MacEditor, and hitting debug"
        );
    }

    # Tundra DAG filename is based on almost all incoming command line arguments, since they
    # can affect the DAG itself. However just concatenating all of them could lead
    # to too long filenames (especially on Windows). So do some common short transformations
    # for often used arguments, and hash the rest of them:
    # - build target names: come through as is
    # - CONFIG/PLATFORM/SCRIPTING_BACKEND/LUMP parameters: their values appended
    # - everything else: concatenated and md5 of them all appended
    #
    # e.g. jam StandalonePlayer -sCONFIG=debug -sSCRIPTING_BACKEND=mono -sFOO=bar -sBAR=foo
    # ends up using StandalonePlayerCfgdebugScriptmono-772f434d75.dag.json DAG filename
    if ($el =~ /^-sCONFIG=(.*)/)
    {
        $cleanedIncomingArguments .= "Cfg" . $1;
    }
    elsif ($el =~ /^-sPLATFORM=(.*)/)
    {
        $cleanedIncomingArguments .= "Plat" . $1;
    }
    elsif ($el =~ /^-sSCRIPTING_BACKEND=(.*)/)
    {
        $cleanedIncomingArguments .= "Script" . $1;
    }
    elsif ($el =~ /^-sLUMP=(.*)/)
    {
        $cleanedIncomingArguments .= "Lump" . $1;
    }
    elsif ($el =~ /^-s/)
    {
        $incomingArgumentsToHash .= $el;
    }
    else
    {
        $cleanedIncomingArguments .= $el;
    }

    if ($el eq "--workspace")
    {
        die("Old IDE projects (--workspace) have been removed; use jam NativeProjectFiles");
    }

    push(@args, $el);
}

chdir $top;
my $mono = "$top/External/MonoBleedingEdge/builds/monodistribution/bin/mono";
if (defined($ARGV[0]) and ($ARGV[0] eq "why" || $ARGV[0] eq "how"))
{
    system("$mono", "artifacts/BeeStandaloneDriver/Bee.StandaloneDriver.exe", "--root-artifacts-path=artifacts/tundra", @ARGV);
    exit;
}
if (defined($ARGV[0]) and ($ARGV[0] eq "time-report"))
{
    PrepareExternalDependency("External/tundra");
    prepare_build_program();
    system("$mono", "artifacts/BeeStandaloneDriver/Bee.StandaloneDriver.exe", @ARGV, "--profile=artifacts/BuildProfile");
    exit;
}
if (defined($ARGV[0]) and ($ARGV[0] eq "include-report"))
{
    PrepareExternalDependency("External/tundra");
    prepare_build_program();
    system("$mono", "artifacts/BeeStandaloneDriver/Bee.StandaloneDriver.exe", "--root-artifacts-path=artifacts/tundra", @ARGV);
    exit;
}

PrepareExternalDependency("External/Roslyn/csc");

# handle 'jam bee/steve/privacy/internaldocs' (case-insensitive match for 'bee' for historical reasons)
if (defined($ARGV[0]) and $ARGV[0] =~ /^[Bb][Ee][Ee]$|^steve$|^privacy$|^internaldocs$/)
{
    PrepareMonoBleedingEdge();
    PrepareExternalDependency("External/ILRepack");
    PrepareExternalDependency("External/tundra");
    PrepareExternalDependency("External/Unity.Cecil");
    $ENV{"MONO_EXECUTABLE"} = $mono;    # used by bee_bootstrap when invoking itself under Tundra
    system($mono, "Tools/BeeBootstrap/bee_bootstrap.exe", "bee")
        and die("failed to run bee_bootstrap");

    if ($ARGV[0] eq 'privacy')
    {
        print("The Unity build system includes the Stevedore binary artifact manager.\n");    # as way of introduction
        system($mono, "build/BeeDistribution/bee.exe", "steve", "privacy")
            and die("failed to run bee.exe");
    }
    elsif ($ARGV[0] eq 'internaldocs')
    {
        if ($^O eq 'MSWin32')
        {
            system(
                'build/BeeDistribution/bee.exe',
                'steve', 'internal-unpack', 'public',
                'winpython2-x64/2.7.13.1Zero_740e3bbd4c2384963a0944dec446dc36ce7513df2786c243b417b93a2dff851e.zip',
                'artifacts/Stevedore/winpython2-x64'
            ) and die('failed to run bee.exe');
        }
        else
        {
            my $pythonVersion = `python -V 2>&1`;
            if (${^CHILD_ERROR_NATIVE})
            {
                die("Error invoking 'python -V': '$OS_ERROR'");
            }
            my $minPythonPatchVersion = 10;
            if ($pythonVersion =~ /^Python 2\.7\.(\d+)$/)
            {
                my $patchVersion = $1;
                if ($patchVersion < $minPythonPatchVersion)
                {
                    die("mkdocs is known to work with Python 2.7.$minPythonPatchVersion or greater");
                }
            }
            else
            {
                die("Python 2.7.$minPythonPatchVersion+ is required ");
            }
        }
    }
    elsif ($ARGV[0] eq 'steve')
    {
        # Run Stevedore with system .NET (Windows) or Mono (Unix), to avoid MonoBleedingEdge SSL cert issues.
        unshift(@ARGV, 'build/BeeDistribution/bee.exe');
        if ($^O ne 'MSWin32')
        {
            unshift(@ARGV, 'mono');
        }
        my $exit_status = system(@ARGV) >> 8;
        exit $exit_status;
    }
    exit;
}

# invoking jam with no arguments is the same as jam --help
if (@ARGV == 0)
{
    push @ARGV, "--help";
}

# make jam -help, -h, --h do the same as --help
s/^-help$|^-h$|^--h$/--help/i for @ARGV;
if (grep { $_ =~ /^--help$|^--helpjson$/i } @ARGV)
{
    PrepareExternalDependency("External/tundra");
    prepare_build_program();
    system($mono, "artifacts/UnityBuildSystem/Unity.BuildSystem/Unity.BuildSystem.exe", @ARGV)
        and die("failed to run help");
    exit;
}

# HACK (can kill once we can unconditionally depend on Stevedore downloads).
if (defined($ARGV[0]) and $ARGV[0] =~ /^stevewrite$/i)
{
    prepare_build_program();
    $ENV{"STEVEDORE_WRITE_OUT"} = '1';
    system("perl Tools/Unity.BuildSystem/frontend.pl");
    exit;
}

$cleanedIncomingArguments =~ tr/a-zA-Z0-9//dc;
if ($incomingArgumentsToHash ne '')
{
    $cleanedIncomingArguments .= "-" . substr(md5_hex($incomingArgumentsToHash), 0, 10);
}

if ($^O eq 'darwin')
{
    # Xcode (9.2 at least) sets up SDKROOT environment variable when doing builds from it,
    # which seemingly hijacks & overrides --sysroot compiler argument. This makes the build
    # use system-installed Xcode SDK/toolchain instead of the one we version & want to use.

    # todo: make the xcode bee toolchain implementation explicitely clear these variables in the environment variables for the action, so we don't have to do this ugly hack in the jam.pl script
    delete $ENV{SDKROOT};
}

my $schrootprefix = SetupLinuxSchroot();

push(@tundraargs, "-f") if $forceFrontEnd;
my $profileName = 'artifacts/BuildProfile/' . $cleanedIncomingArguments . '.json';
push(@tundraargs, "--profile=$profileName");
push(@tundraargs, @manualtundraargs);
push(@tundraargs, "convertedjamtargets") if (!@manualtundraargs);
my $arg_string = join(" ", @args);
call_tundra($schrootprefix, "artifacts/tundra/$cleanedIncomingArguments.dag", "perl Tools/Unity.BuildSystem/frontend.pl $arg_string", join(" ", @tundraargs));

if ($verifyUpToDate)
{
    system(
        "$mono", "artifacts/BeeStandaloneDriver/Bee.StandaloneDriver.exe",
        "--root-artifacts-path=artifacts/tundra", "--dag-filename=$cleanedIncomingArguments.dag",
        "--verify-up-to-date", "convertedjamtargets"
        )
        and die(
        "*** ERROR: Doing a second build right after previous one should not update/build anything. However --verify-up-to-date said that things were updated; see messages above."
        );
}

exit;

sub SetupLinuxSchroot
{
    #Our linux build situation is kind of sad. It requires the entire build process to happen inside a "schroot", which is a command
    #that replaces your entire view on the filesystem to a different directory,  that we have carefully prepared (recycled from Valve's)
    #and has the exact compiler, linker etc that we expect. This function describes what prefix to put before any realcommand to make
    #it happen in this linux schroot. Hopefully we'll be able to finally kill this horrible setup soon(tm).
    if ($^O eq "linux")
    {
        if (exists $ENV{'UNITY_USE_LINUX_SCHROOT'} and defined($ENV{LINUX_BUILD_ENVIRONMENT}) and $ENV{LINUX_BUILD_ENVIRONMENT} ne '')
        {
            # Use linux build environment
            ProgressMessage('Building with the Linux SDK schroot');

            # Make sure we're cleaned up from last time
            system('schroot', '--all-sessions', '--end-session', '--force');

            # linux sdk gcc is too old :-(
            $ENV{"DOWNSTREAM_STDOUT_CONSUMER_SUPPORTS_COLOR"} = '0';

            return "schroot -c $ENV{LINUX_BUILD_ENVIRONMENT} -- ";
        }
    }
    return "";
}

sub AdjustArgCaseSensitivity
{
    # Jam target names are case sensitive, but to help people doing typos often,
    # we recognize a set of "often used" target names by doing case insensitive comparison,
    # and return the proper casing.

    #todo: remove this code, and implement case insensitive target search in tundra
    my ($t) = @_;
    my $lct = lc($t);
    my @common = qw(
        Editor MacEditor LinuxEditor
        StandalonePlayer WinPlayer MacStandalonePlayer MacPlayer LinuxStandalonePlayer LinuxPlayer
        ProjectFiles NativeProjectFiles ManagedProjectFiles BuildSystemProjectFiles
        CgBatch CgBatchTests JobProcess UnwrapCL Binary2Text WebExtract bugreporter AssetCacheServer
        iOSPlayer tvOSPlayer AndroidPlayer WebGLSupport WebGLSupportAll WebGLPlayer
        BuiltinResourcesExtra EditorResources
        Pass1);
    my $res = first { lc($_) eq $lct } @common;
    return $res if $res;
    return $t;
}
