#!/usr/bin/env bash
# Use the generated wrapper's exact distribution and Gradle's published checksum.
set -euo pipefail
wrapper=android/gradle/wrapper/gradle-wrapper.properties
zip=$(sed -n 's|^distributionUrl=.*/||p' "$wrapper" | tr -d '\r')
[[ "$zip" =~ ^gradle-([0-9]+\.[0-9]+(\.[0-9]+)?)-(all|bin)\.zip$ ]]
version=${BASH_REMATCH[1]}
if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then version+=.0; fi
dir=$(mktemp -d)
checksum=$(curl --fail --silent --show-error --location --retry 2 --max-time 45 "https://services.gradle.org/distributions/$zip.sha256")
[[ "$checksum" =~ ^[0-9a-f]{64}$ ]]
gh release download "v$version" --repo gradle/gradle-distributions --pattern "$zip" --dir "$dir"
echo "$checksum  $dir/$zip" | sha256sum --check --status
sed -i "s|^distributionUrl=.*|distributionUrl=file://$dir/$zip|" "$wrapper"
