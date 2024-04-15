#!/usr/bin/env perl

use JSON::PP;

my $json;

sub get_from_json_env {
    my ($key) = @_;
    return () unless defined $ENV{$key} && $ENV{$key};

    our $json;
    $json = JSON::PP->new->utf8->pretty->sort_by(sub { $JSON::PP::a cmp $JSON::PP::b }) unless defined $json;
    my $result = $json->decode($ENV{$key});
    return $result;
}

my @codependent = @{ get_from_json_env 'CODEPENDENT' };
my %inputs = %{ get_from_json_env 'INPUTS' };

my @required;
my $status = 0;

open INPUT, '<', "$ENV{GITHUB_ACTION_PATH}/action.yml";
while (<INPUT>) {
    if ($state == 0) {
        $state = 1 if /^inputs:/;
        next;
    }
    if ($state == 1) {
        last if /^\S/;
        if (/^  (\S+):/) {
            $key = $1;
        } elsif (/^    required: true/) {
            push @required, $key unless %inputs && defined $inputs{$key} && $inputs{$key} =~ /./;
        }
    }
}

open my $github_step_summary, '>>', $ENV{GITHUB_STEP_SUMMARY};

if (@codependent && %inputs) {
    my $warned_about_missing_codependent;
    for my $dependents (@codependent) {
        my $expected = 0;
        my $found = 0;
        my @needed;
        my @dependents = @{$dependents};
        for $dependent (@dependents) {
            ++$expected;
            if (defined $inputs{$dependent} && $inputs{$dependent}) {
                ++$found;
            } else {
                push @needed, $dependent;
            }
        }
        if ($found && $expected != $found) {
            my $codependent_message = "Codependent inputs (".join(', ', @dependents).") need: ".join(', ', @needed)."\n";
            print "::error ::$codependent_message";
            unless ($warned_about_missing_codependent) {
                print $github_step_summary "## :x: Unsatisfied codependent inputs\n\n";
                $warned_about_missing_codependent = 1;
            }
            print $github_step_summary $codependent_message;
            $status |= 2;
        }
    }
    if ($warned_about_missing_codependent) {
        print $github_step_summary "\n";
    }
}

if (@required) {
    print "::error ::Some required inputs are missing\n";
    print '::notice ::Required inputs: ['.join(', ', @required)."]\n";
    print $github_step_summary "## :x: Missing required inputs\n\n".
        'Required inputs: ['.join(', ', @required)."]\n";
    $status |= 1;
}
close $github_step_summary;
exit $status;
