#!/usr/bin/env perl

my @required;

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
            push @required, $key;
        }
    }
}

if (@required) {
    print "::error ::Some required inputs are missing\n";
    print '::notice ::Required inputs: ['.join(', ', @required)."]\n";
}
