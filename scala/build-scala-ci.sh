#!/bin/sh -e

./scripts/sbt-ci.sh "compile ; test:compile ; unusedCompileDependenciesTest ; undeclaredCompileDependenciesTest ; test:unusedCompileDependenciesTest ; test:undeclaredCompileDependenciesTest ; test ; dist ; $EXTRA_SBT_ARGS"

copy_jmx_agent() {
  cp jmx_prometheus_javaagent-*.jar "$1"/
}

move_dist() {
  rm -f "$1/target/universal/$1.zip"
  mv "$1/target/universal/$1"*.zip "$1/target/universal/$1.zip"
}

for project in $COPY_PROMETHEUS_TO; do
  copy_jmx_agent $project
done

for project in $SIMPLIFY_PROJECT_NAMES; do
  move_dist $project
done
