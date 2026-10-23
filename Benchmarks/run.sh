#!/bin/zsh
set -e
cd "$(dirname "$0")"

swift build -c release --package-path Native
swift build -c release --package-path StreamingMarkdown

libraries=($@)
(( $#libraries )) || libraries=(Sumi SwiftStreamingMarkdown MarkdownUI Textual PlainTextView)
rm -rf results/runs
for run in 1 2 3 4 5; do
  for kind in mixed prose code table; do
    for library in $libraries; do
      package=Native
      [[ $library == SwiftStreamingMarkdown ]] && package=StreamingMarkdown
      $package/.build/release/Bench $library $kind $run
    done
  done
done

Native/.build/release/Bench summary "$(git describe --always --dirty)" $libraries

# Only a run of all libraries redraws the README charts.
(( $# )) || swift charts.swift "$(ls -t results/*.json | head -1)"
