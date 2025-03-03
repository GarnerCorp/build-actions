#!/usr/bin/env perl
my ($registry, $secret)=@ARGV;
my ($d, $d1)=('\$', '$1');
print qq<if grep -q 'image: $registry' "$d1"; then
  perl -pi -e 's/${d}IMAGE_PULL_CONFIG/$secret/' "$d1"
fi
>;
