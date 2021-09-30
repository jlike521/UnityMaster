#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw ($Bin);
use lib $Bin;
use lib "$Bin/Tools/UnifiedTestRunner";

use AutoComplete;
use GlobalOptions;
use AppHelper;
use Getopt::Long qw (GetOptionsFromArray :config pass_through);

if ($ENV{COMP_CWORD})
{
    my $str = $ARGV[$ENV{COMP_CWORD}];
    my @globalOptions = GlobalOptions::getOptions();
    my $globalOptions = new Options(options => \@globalOptions);
    $globalOptions->parse(@ARGV);
    my @runners = AppHelper::createRunners($globalOptions);
    my $suiteOptions = {};

    foreach my $r (@runners)
    {
        my $suiteName = $r->getName();
        my @suiteOptions = $r->getOptionsWithoutNamespace();
        $suiteOptions->{$suiteName} = new Options(options => \@suiteOptions);
    }

    my $autoComplete = new AutoComplete(
        globalOptions => $globalOptions,
        suiteOptions => $suiteOptions
    );

    my $inputInfo = {
        argv => \@ARGV,
        wordIdx => $ENV{COMP_CWORD}
    };

    my @matches = $autoComplete->complete($inputInfo);

    if (scalar(@matches) == 1)
    {
        if ($matches[0] =~ m/=$/)
        {

            # dirty trick: if there is only match ending with '=', it means option name is resolved
            # however if we insert it as it is, shell will insert space, which will result into
            # 'suite= ' , there is no way how to do it, so let's just insert som ambitious values
            push(@matches, $matches[0] . 'A');
            push(@matches, $matches[0] . 'B');
            pop(@matches);
        }
    }

    print join("\n", @matches);
    exit(0);
}

sub _debug
{
    my ($fileName, @matches) = @_;
    open(my $fh, '>', $fileName);
    print($fh $ENV{COMP_CWORD} . "\n");
    print($fh join(" ", @ARGV) . "\n");
    print($fh join(" ", @matches) . "\n");
    close($fh);
}

my $exitCode = system('perl', "./Tools/UnifiedTestRunner/test.pl", @ARGV, '--tag=utr-pl');
exit($exitCode >> 8);
