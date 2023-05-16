#!/usr/bin/env perl
use File::Basename;
my @modules;

for my $file (<*/target/scala-*/scoverage-data/scoverage.coverage>) {
    my $module=(dirname (dirname (dirname (dirname $file))));
    push @modules, $module;
}

die 'Could not find any scoverage.coverage files' unless @modules;

open BUILD, '>', 'build.sbt';
print BUILD '
import ProjectExtensions._
';

my @values;

for my $i (0..$#modules) {
    my ($lazy, $module) = ("a$i", "$modules[$i]");
    push @values, $lazy;
    print BUILD qq<lazy val $lazy = (project in file("$module")).commonSettings.settings()
>;
}

print BUILD 'lazy val root = (project in file(".")).aggregate('.join(',', @values).')
';
close BUILD;
