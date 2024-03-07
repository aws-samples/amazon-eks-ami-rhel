#!/usr/bin/env bash

if [[ "$ENABLE_FIPS" == "true" ]]; then
  sudo dnf -y install crypto-policies crypto-policies-scripts
  sudo fips-mode-setup --enable
fi
