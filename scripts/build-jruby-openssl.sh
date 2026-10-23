#!/usr/bin/env bash
set -euo pipefail
source_dir=$1
output=$2
# Upstream targets Java 8 bytecode, which javac 25 no longer supports.
export JAVA_HOME=${JAVA_HOME_21_X64:?JDK 21 is required to build jruby-openssl}
export PATH="$JAVA_HOME/bin:$PATH"
cd "$source_dir"
./mvnw -B -ntp prepare-package -Dmaven.test.skip=true
gem build jruby-openssl.gemspec --output "$output"
