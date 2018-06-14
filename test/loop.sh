#!/bin/bash

set +e
for round in {1..10}
do
    echo "Round $round"
    echo "========"
    echo ""

    echo "# api"
    foundationdb/bindings/bindingtester/bindingtester.py elixir --test-name api --num-ops 1000 --compare python || exit 1

    echo "# api with concurrency 5"
    foundationdb/bindings/bindingtester/bindingtester.py elixir --test-name api --num-ops 1000 --concurrency 5 || exit 1
done
