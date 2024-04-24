#!/usr/bin/env perl

my %supported_extensions;
my %found_extensions;
my %interesting_paths;

for my $extension (split " ", $ENV{INPUT_FILE_EXTENSIONS}) {
  $supported_extensions{$extension} = "";
}

open my $git, "-|", "git ls-files -z";
{
  local $/ = "\0";
  my $sought_extensions_re = join '|', (map { s/([\\{}.\[\]])/\\$1/g; $_ } keys %supported_extensions);
  while (my $file_with_path = <$git>) {
    chomp $file_with_path;
    my ($path, $file) = ($file_with_path =~ m<(.*/|)([^/]+)$>);
    $path = "." if $path eq "";
    $path =~ s</$><>;
    next unless $file =~ /($sought_extensions_re)$/;
    my $ext = $1;
    $found_extensions{$ext} = 1;
    $interesting_paths{$path} = 1;
  }
}
close $git;

exit unless keys %interesting_paths && keys %found_extensions;

sub maybe_use_braces {
  my ($hash) = @_;
  my @items = keys %{$hash};
  if (scalar @items == 1) {
    return $items[0];
  }
  return "{".(join ",", sort map {$_ =~ s/([,\\])/\\$1/g; $_} @items)."}";
}
print "".(maybe_use_braces \%interesting_paths)."/*".(maybe_use_braces \%found_extensions);
