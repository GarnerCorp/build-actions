#!/bin/bash
registries=$(perl -e '
  my @images = split /\s+/, $ENV{registries};
  my %repos;
  for my $image (@images) {
    $image =~ s</.*><>;
    next unless $image =~ /\bgcr\.io$|pkg\.dev$/;
    $repos{$image} = 1;
  }
  print join " ", sort keys %repos;
')
if [ -n "$registries" ]; then
  echo ::group::Configure docker gcloud credential helpers
  old_config=$(mktemp)
  new_config=$(mktemp)
  additions=$(mktemp)

  trim_docker_conf_trailing_commas() {
    perl -pe 's/,$//' ~/.docker/config.json
  }

  for registry in $registries; do
    if [ "$(jq -r '.credHelpers["$registry"] // empty' ~/.docker/config.json)" = '' ] ; then
      trim_docker_conf_trailing_commas > "$old_config" || true
      gcloud auth configure-docker "$registry" > /dev/null 2> /dev/null < /dev/null
      trim_docker_conf_trailing_commas > "$new_config" || true
      if ! diff -q "$old_config" "$new_config" > /dev/null; then
        diff -U0 "$old_config" "$new_config" | perl -ne 'next unless /"gcloud"/ && s/^[+]([^+])/$1/; print' >> "$additions"
      fi
    fi
  done
  if [ -s "$additions" ]; then
    echo 'Additions to ~/.docker/config.json:'
    cat "$additions"
  fi
  echo "::end"group::
fi
