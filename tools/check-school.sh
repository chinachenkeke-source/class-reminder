#!/bin/bash
# 仅解析与渲染，不启动提醒、不修改使用中的课表。
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d /tmp/class-reminder-check.XXXXXX)
trap 'rm -rf "$CHECK_DIR"' EXIT
python3 -c 'from pathlib import Path; import sys; source=Path("Sources/main.swift").read_text().split("// MARK: - 入口")[0]; Path(sys.argv[1]).write_text(source + "\ntry runSchoolChecks()\n")' "$CHECK_DIR/main.swift"
swiftc -swift-version 5 "$CHECK_DIR/main.swift" Sources/SchoolSchedule.swift tests/SchoolScheduleChecks.swift -o "$CHECK_DIR/check"
"$CHECK_DIR/check" "$@"
