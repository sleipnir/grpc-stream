#!/bin/bash

OUT="bulk_input.json"
> "$OUT"

for i in $(seq 1 100000); do
  echo "{\"name\": \"User$i\"}" >> "$OUT"
  echo "" >> "$OUT"
done
