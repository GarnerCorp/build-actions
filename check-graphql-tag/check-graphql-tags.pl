#!/usr/bin/env perl

our %files;
our %fragments;
our %fragment_map;

sub scan_file {
  my ($current_file) = @_;
  open my $fh, '<', $current_file or return;
  our %files;
  our %fragments;
  while (<$fh>) {
    next unless /^\s*fragment\s+(\w+)\s+on\b/;
    $fragments{$1}++;
    $files{$current_file} = 1;
  }
  close $fh;
}

sub get_files {
  local $/ = "\0";
  my @to_scan;
  while (<>) {
    chomp;
    push @to_scan, $_;
  }
  return @to_scan;
}

sub find_duplicated_fragments {
  my @duplicated_fragments = grep {$fragments{$_} > 1} keys %fragments;
  exit 0 unless @duplicated_fragments;
  my $pattern = '^\s*(fragment\s+(?:'.(join "|", @duplicated_fragments).'))\b';
  for my $file (keys %files) {
    open my $has_fragments_fh, q(<), $file or do {
      warn "could not open $file: $!";
      next;
    };
    while (<$has_fragments_fh>) {
      if (/$pattern/) {
         my ($b, $e) = ($-[1] + 1, $+[1] + 1);
         my ($fragment, $location) = ($1, "$file:$.:$b:$e");
         print "$location duplicate fragment: $fragment\n";
         my @fragment_list = @{$fragment_map{$fragment}};
         push @fragment_list, $location;
         $fragment_map{$fragment} = \@fragment_list;
      }
    }
    close $has_fragments_fh;
  }
}

sub report_summary {
  my $summary = $ENV{GITHUB_STEP_SUMMARY};
  exit +1 unless defined $summary;

  die "Failed to append to $summary: $!" unless open my $output, '>>', $summary;

  print $output q<## Duplicate graphql-tag fragments detected

[apollographql/graphql-tag](https://github.com/apollographql/graphql-tag/) doesn't like this.
For more information, see: https://www.apollographql.com/docs/react/data/fragments#unique-names

>;

  our %fragment_map;
  for my $fragment (keys %fragment_map) {
    print $output "### $fragment

File|Line|Start|End
-|-|-|-
";
    my @fragment_list = @{$fragment_map{$fragment}};
    for my $location (@fragment_list) {
      $location =~ s/:/|/g;
      print $output "$location\n";
    }
    print $output "\n";
  }
  close $output;
}

for my $file (get_files()) {
  scan_file($file);
}

find_duplicated_fragments();
report_summary();
exit 1;
