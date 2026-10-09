#!/bin/bash
set -euo pipefail
exec bash "$(dirname "$0")/swift.sh" run CoreChecks
