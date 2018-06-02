#!/usr/bin/env bash
cd "$(dirname "$0")"
cd ..
mix run test/binding_tester.exs $*
