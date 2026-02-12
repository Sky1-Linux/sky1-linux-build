#!/usr/bin/env -S uv run --python 3.14 --script
# /// script
# requires-python = ">=3.14"
# ///
"""Manage kernel config options across all Sky1 build tracks.

Sets, shows, or removes config options in all track configs, the config
policy file, and the config README — in a single command.

Usage:
  manage-config.py set USB_UAS=m                      # all tracks + dev copies
  manage-config.py set USB_UAS=m --apply              # actually write (default is dry-run)
  manage-config.py set USB_UAS=m --policy usb --apply # also add to [usb] in policy
  manage-config.py set USB_UAS=m --policy usb \\
      --doc "USB Support" --type module \\
      --desc "USB Attached SCSI (high-performance storage)" --apply
  manage-config.py show USB_UAS                       # show across all tracks
  manage-config.py remove USB_UAS --policy --apply    # remove from policy

Files managed:
  Authoritative configs: ~/sky1-linux-distro/linux-sky1/config/config.sky1*
  Config policy:         ~/sky1-linux-distro/linux-sky1/config/config-policy.ini
  Config docs:           ~/sky1-linux-distro/linux-sky1/config/README.md
  Dev build copies:      ~/mainline-linux/config.sky1* (untracked)
"""

import argparse
import re
import sys
from pathlib import Path

LINUX_SKY1 = Path.home() / "sky1-linux-distro" / "linux-sky1"
CONFIG_DIR = LINUX_SKY1 / "config"
POLICY_FILE = CONFIG_DIR / "config-policy.ini"
README_FILE = CONFIG_DIR / "README.md"
MAINLINE = Path.home() / "mainline-linux"

TRACK_CONFIGS = [
    CONFIG_DIR / "config.sky1",
    CONFIG_DIR / "config.sky1-latest",
    CONFIG_DIR / "config.sky1-rc",
    CONFIG_DIR / "config.sky1-next",
]


def normalize_option(name: str) -> str:
    """Strip CONFIG_ prefix if present, return bare name."""
    return name.removeprefix("CONFIG_")


def find_dev_configs() -> list[Path]:
    """Find dev build config copies in mainline-linux."""
    return sorted(MAINLINE.glob("config.sky1*"))


# ---------------------------------------------------------------------------
# Config file operations
# ---------------------------------------------------------------------------

def get_config_value(path: Path, option: str) -> str | None:
    """Get the value of a config option in a kernel config file."""
    key = f"CONFIG_{option}"
    for line in path.read_text().splitlines():
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1]
        if line == f"# {key} is not set":
            return "n"
    return None


def set_config_line(text: str, option: str, value: str) -> tuple[str, bool]:
    """Replace a config option line in config text. Returns (new_text, changed)."""
    key = f"CONFIG_{option}"
    if value == "n":
        new_line = f"# {key} is not set"
    else:
        new_line = f"{key}={value}"

    # Try replacing existing enabled line
    pattern_enabled = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    # Try replacing existing disabled line
    pattern_disabled = re.compile(rf"^# {re.escape(key)} is not set$", re.MULTILINE)

    if pattern_enabled.search(text):
        new_text = pattern_enabled.sub(new_line, text)
        return new_text, new_text != text
    if pattern_disabled.search(text):
        new_text = pattern_disabled.sub(new_line, text)
        return new_text, new_text != text

    return text, False  # not found


# ---------------------------------------------------------------------------
# Policy file operations
# ---------------------------------------------------------------------------

def get_policy_entry(option: str) -> tuple[str, str] | None:
    """Find option in policy file, return (section, value) or None."""
    if not POLICY_FILE.exists():
        return None
    section = None
    bare = option.upper()
    for line in POLICY_FILE.read_text().splitlines():
        line_stripped = line.strip()
        if line_stripped.startswith("[") and line_stripped.endswith("]"):
            section = line_stripped[1:-1]
        elif "=" in line_stripped and not line_stripped.startswith("#"):
            key, _, val = line_stripped.partition("=")
            if key.strip().upper() == bare:
                return (section or "unknown", val.strip())
    return None


def set_policy_entry(text: str, option: str, value: str, section: str) -> tuple[str, bool]:
    """Add or update a policy entry. Returns (new_text, changed)."""
    bare = option.upper()
    new_entry = f"{bare}={value}"

    # Check if option already exists anywhere
    lines = text.splitlines()
    for i, line in enumerate(lines):
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#") and not stripped.startswith("["):
            key = stripped.split("=")[0].strip()
            if key.upper() == bare:
                if stripped == new_entry:
                    return text, False  # already correct
                lines[i] = new_entry
                return "\n".join(lines) + "\n", True

    # Not found — add under the specified section
    section_header = f"[{section}]"
    in_section = False
    insert_at = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == section_header:
            in_section = True
            continue
        if in_section:
            if stripped.startswith("["):
                # Hit next section — insert before it
                insert_at = i
                break
            if stripped == "":
                # Blank line at end of section
                insert_at = i
                break
            insert_at = i + 1  # after last entry in section

    if insert_at is not None:
        lines.insert(insert_at, new_entry)
        return "\n".join(lines) + "\n", True

    # Section not found — append new section
    lines.append(f"\n{section_header}")
    lines.append(new_entry)
    return "\n".join(lines) + "\n", True


def remove_policy_entry(text: str, option: str) -> tuple[str, bool]:
    """Remove a policy entry. Returns (new_text, changed)."""
    bare = option.upper()
    lines = text.splitlines()
    new_lines = []
    removed = False
    for line in lines:
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#") and not stripped.startswith("["):
            key = stripped.split("=")[0].strip()
            if key.upper() == bare:
                removed = True
                continue
        new_lines.append(line)
    return "\n".join(new_lines) + "\n", removed


# ---------------------------------------------------------------------------
# README operations
# ---------------------------------------------------------------------------

def get_readme_entry(option: str) -> str | None:
    """Find option in README tables, return the table row or None."""
    if not README_FILE.exists():
        return None
    key = f"`{option}`"
    for line in README_FILE.read_text().splitlines():
        if key in line and line.startswith("|"):
            return line.strip()
    return None


def add_readme_entry(text: str, option: str, heading: str,
                     opt_type: str, desc: str) -> tuple[str, bool]:
    """Add a row to a README table under the given heading. Returns (new_text, changed)."""
    key = f"`{option}`"
    new_row = f"| `{option}` | {opt_type} | {desc} |"

    # Check if already present
    if key in text:
        # Update existing row
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if key in line and line.startswith("|"):
                if lines[i].strip() == new_row:
                    return text, False
                lines[i] = new_row
                return "\n".join(lines) + "\n", True

    # Find the heading section and insert before next blank line or heading
    lines = text.splitlines()
    heading_pattern = f"## {heading}"
    in_section = False
    in_table = False
    insert_at = None

    for i, line in enumerate(lines):
        if line.strip() == heading_pattern:
            in_section = True
            continue
        if in_section:
            if line.startswith("|---") or line.startswith("| ---"):
                in_table = True
                continue
            if in_table:
                if line.startswith("|"):
                    insert_at = i + 1  # after this table row
                else:
                    # End of table
                    insert_at = i
                    break

    if insert_at is not None:
        lines.insert(insert_at, new_row)
        return "\n".join(lines) + "\n", True

    return text, False


def remove_readme_entry(text: str, option: str) -> tuple[str, bool]:
    """Remove a row from README tables. Returns (new_text, changed)."""
    key = f"`{option}`"
    lines = text.splitlines()
    new_lines = []
    removed = False
    for line in lines:
        if key in line and line.startswith("|"):
            removed = True
            continue
        new_lines.append(line)
    return "\n".join(new_lines) + "\n", removed


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_show(option: str) -> int:
    """Show current value of an option across all tracks."""
    option = normalize_option(option)
    key = f"CONFIG_{option}"

    print(f"=== {key} ===\n")

    # Track configs
    for path in TRACK_CONFIGS:
        if path.exists():
            val = get_config_value(path, option)
            display = f"{key}={val}" if val and val != "n" else f"# {key} is not set" if val == "n" else "(not found)"
            print(f"  {path.name:25s} {display}")

    # Dev copies
    for path in find_dev_configs():
        val = get_config_value(path, option)
        display = f"{key}={val}" if val and val != "n" else f"# {key} is not set" if val == "n" else "(not found)"
        print(f"  (dev) {path.name:20s} {display}")

    # Policy
    entry = get_policy_entry(option)
    if entry:
        print(f"  {'policy':25s} [{entry[0]}] {option}={entry[1]}")
    else:
        print(f"  {'policy':25s} (not in policy)")

    # README
    row = get_readme_entry(option)
    if row:
        print(f"  {'README':25s} {row}")
    else:
        print(f"  {'README':25s} (not documented)")

    print()
    return 0


def cmd_set(option: str, value: str, *,
            policy_section: str | None = None,
            doc_heading: str | None = None,
            doc_type: str | None = None,
            doc_desc: str | None = None,
            apply: bool = False) -> int:
    """Set a config option across all tracks."""
    option = normalize_option(option)
    key = f"CONFIG_{option}"
    changes: list[tuple[Path, str, str]] = []  # (path, description, diff_summary)

    # Track configs
    for path in TRACK_CONFIGS:
        if not path.exists():
            continue
        text = path.read_text()
        new_text, changed = set_config_line(text, option, value)
        if changed:
            changes.append((path, f"set {key}={value}", new_text))
        else:
            old_val = get_config_value(path, option)
            if old_val is None:
                print(f"  warn: {key} not found in {path.name} (may not exist in this kernel version)")

    # Dev copies
    for path in find_dev_configs():
        text = path.read_text()
        new_text, changed = set_config_line(text, option, value)
        if changed:
            changes.append((path, f"set {key}={value}", new_text))

    # Policy
    if policy_section:
        text = POLICY_FILE.read_text()
        new_text, changed = set_policy_entry(text, option, value, policy_section)
        if changed:
            changes.append((POLICY_FILE, f"add {option}={value} to [{policy_section}]", new_text))

    # README
    if doc_heading and doc_type and doc_desc:
        text = README_FILE.read_text()
        new_text, changed = add_readme_entry(text, option, doc_heading, doc_type, doc_desc)
        if changed:
            changes.append((README_FILE, f"add to '{doc_heading}' table", new_text))

    # Report
    if not changes:
        print(f"No changes needed — {key}={value} already set everywhere.")
        return 0

    print(f"{'Will apply' if apply else 'Dry run'}: {len(changes)} file(s) to update\n")
    for path, desc, _ in changes:
        relpath = path.relative_to(Path.home()) if str(path).startswith(str(Path.home())) else path
        print(f"  ~/{relpath}: {desc}")

    if apply:
        print()
        for path, desc, new_text in changes:
            path.write_text(new_text)
            print(f"  wrote {path.name}")
        print(f"\nDone. {len(changes)} file(s) updated.")
    else:
        print(f"\nPass --apply to write changes.")

    return 0


def cmd_remove(option: str, *, policy: bool = False, doc: bool = False,
               apply: bool = False) -> int:
    """Remove option from policy and/or README (does not change config values)."""
    option = normalize_option(option)
    changes: list[tuple[Path, str, str]] = []

    if policy and POLICY_FILE.exists():
        text = POLICY_FILE.read_text()
        new_text, changed = remove_policy_entry(text, option)
        if changed:
            changes.append((POLICY_FILE, f"remove {option} from policy", new_text))

    if doc and README_FILE.exists():
        text = README_FILE.read_text()
        new_text, changed = remove_readme_entry(text, option)
        if changed:
            changes.append((README_FILE, f"remove {option} from README", new_text))

    if not changes:
        print(f"Nothing to remove for {option}.")
        return 0

    print(f"{'Will apply' if apply else 'Dry run'}: {len(changes)} file(s) to update\n")
    for path, desc, _ in changes:
        relpath = path.relative_to(Path.home()) if str(path).startswith(str(Path.home())) else path
        print(f"  ~/{relpath}: {desc}")

    if apply:
        print()
        for path, desc, new_text in changes:
            path.write_text(new_text)
            print(f"  wrote {path.name}")
        print(f"\nDone. {len(changes)} file(s) updated.")
    else:
        print(f"\nPass --apply to write changes.")

    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # show
    p_show = sub.add_parser("show", help="Show option value across all tracks")
    p_show.add_argument("option", help="Config option name (with or without CONFIG_ prefix)")

    # set
    p_set = sub.add_parser("set", help="Set option across all tracks")
    p_set.add_argument("assignment", help="OPTION=VALUE (e.g. USB_UAS=m)")
    p_set.add_argument("--policy", metavar="SECTION",
                       help="Also add/update in config-policy.ini under [SECTION]")
    p_set.add_argument("--doc", metavar="HEADING",
                       help="README section heading (e.g. 'USB Support')")
    p_set.add_argument("--type", metavar="TYPE", dest="doc_type",
                       help="Config type for README (bool/module/string)")
    p_set.add_argument("--desc", metavar="DESC",
                       help="Description for README table")
    p_set.add_argument("--apply", action="store_true",
                       help="Actually write changes (default is dry-run)")

    # remove
    p_remove = sub.add_parser("remove", help="Remove from policy/README (not from configs)")
    p_remove.add_argument("option", help="Config option name")
    p_remove.add_argument("--policy", action="store_true",
                          help="Remove from config-policy.ini")
    p_remove.add_argument("--doc", action="store_true",
                          help="Remove from README.md")
    p_remove.add_argument("--apply", action="store_true",
                          help="Actually write changes (default is dry-run)")

    args = parser.parse_args()

    if args.command == "show":
        sys.exit(cmd_show(args.option))

    elif args.command == "set":
        if "=" not in args.assignment:
            parser.error("set requires OPTION=VALUE (e.g. USB_UAS=m)")
        opt, _, val = args.assignment.partition("=")
        if args.doc and not (args.doc_type and args.desc):
            parser.error("--doc requires both --type and --desc")
        sys.exit(cmd_set(
            opt, val,
            policy_section=args.policy,
            doc_heading=args.doc,
            doc_type=args.doc_type,
            doc_desc=args.desc,
            apply=args.apply,
        ))

    elif args.command == "remove":
        if not args.policy and not args.doc:
            parser.error("remove requires --policy and/or --doc")
        sys.exit(cmd_remove(args.option, policy=args.policy, doc=args.doc,
                            apply=args.apply))


if __name__ == "__main__":
    main()
