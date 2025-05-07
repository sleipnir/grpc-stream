#!/bin/bash

OUT="bulk_input.json"
> "$OUT" # limpa o arquivo

for i in $(seq 1 100000); do
  echo "{\"name\": \"User$i\"}" >> "$OUT"
  echo "" >> "$OUT"
done
