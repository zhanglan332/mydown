#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

WORKSPACE="MacDown.xcworkspace"
SCHEME="MacDown"
CONFIGURATION="Debug"
DERIVED_DATA="$ROOT/.build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/MacDown.app"
XCODE_DESTINATION="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

strip_servbay_from_path()
{
    local part cleaned="" first=1
    IFS=':'
    for part in ${PATH:-}; do
        [[ "$part" == *ServBay* ]] && continue
        if [[ $first -eq 1 ]]; then
            cleaned="$part"
            first=0
        else
            cleaned="${cleaned}:$part"
        fi
    done
    unset IFS
    export PATH="$cleaned"
}

prefer_homebrew_ruby()
{
    local prefix
    for prefix in /opt/homebrew/opt/ruby@3.1 /usr/local/opt/ruby@3.1; do
        if [[ -x "$prefix/bin/ruby" ]]; then
            export PATH="$prefix/bin:$PATH"
            return 0
        fi
    done
    return 1
}

ensure_ruby_env()
{
    strip_servbay_from_path
    prefer_homebrew_ruby || true

    export LANG="${LANG:-en_US.UTF-8}"
    export LC_ALL="${LC_ALL:-en_US.UTF-8}"

    command -v ruby >/dev/null 2>&1 || die "ruby not found. Run: brew install ruby@3.1"

    local ver major minor
    ver="$(ruby -e 'print RUBY_VERSION')"
    major="${ver%%.*}"
    minor="${ver#*.}"
    minor="${minor%%.*}"
    if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 1 ]]; then
        die "Ruby >= 3.1 required (current ${ver}). Run: brew install ruby@3.1"
    fi
    info "Ruby ${ver}"
}

ensure_rexml()
{
    if ! ruby -e 'require "rexml/document"' >/dev/null 2>&1; then
        info "Installing rexml gem for CocoaPods compatibility..."
        gem install rexml
    fi
}

require_cmd()
{
    command -v "$1" >/dev/null 2>&1 || die "$1 not found. ${2:-}"
}

needs_setup()
{
    [[ ! -f "$WORKSPACE/contents.xcworkspacedata" ]] \
        || [[ ! -d "$ROOT/Pods" ]] \
        || [[ ! -f "$ROOT/Dependency/peg-markdown-highlight/pmh_parser.c" ]]
}

run_setup()
{
    require_cmd git
    ensure_ruby_env
    ensure_rexml

    info "Initializing git submodules..."
    git submodule update --init

    info "Installing Ruby gems..."
    bundle install

    info "Installing CocoaPods dependencies..."
    RUBYOPT="${RUBYOPT:-} -rrexml/document" bundle exec pod install

    info "Building peg-markdown-highlight..."
    make -C "$ROOT/Dependency/peg-markdown-highlight"
}

run_build()
{
    require_cmd xcodebuild "Install Xcode first."
    [[ -f "$WORKSPACE/contents.xcworkspacedata" ]] || die "$WORKSPACE not found. Run ./run.sh --setup first."

    mkdir -p "$DERIVED_DATA"
    info "Building $SCHEME ($CONFIGURATION) -> $XCODE_DESTINATION"
    info "The first build can take 5-15 minutes and should keep printing logs."

    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "$XCODE_DESTINATION" \
        build

    [[ -d "$APP_PATH" ]] || die "Build finished but app not found: $APP_PATH"
    info "Built app: $APP_PATH"
}

run_app()
{
    [[ -d "$APP_PATH" ]] || die "App not found. Run ./run.sh --build first."
    info "Launching $SCHEME..."
    open "$APP_PATH"
}

run_xcode()
{
    [[ -f "$WORKSPACE/contents.xcworkspacedata" ]] || die "$WORKSPACE not found. Run ./run.sh --setup first."
    open "$WORKSPACE"
}

run_test()
{
    require_cmd xcodebuild
    [[ -f "$WORKSPACE/contents.xcworkspacedata" ]] || die "$WORKSPACE not found. Run ./run.sh --setup first."
    info "Running tests..."
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "$XCODE_DESTINATION" \
        test
}

usage()
{
    cat <<'EOF'
MacDown local development

Daily use: open MacDown.xcworkspace -> Cmd+R in Xcode

First-time setup:
  brew install ruby@3.1
  ./run.sh --setup

Commands:
  ./run.sh          Build and launch MacDown
  ./run.sh --setup  Install submodules, bundle, CocoaPods, and local dependency builds
  ./run.sh --xcode  Open the workspace in Xcode
  ./run.sh --build  Build only
  ./run.sh --test   Run tests
  ./run.sh --help   Show help
EOF
}

main()
{
    local do_setup=0 do_build=0 do_run=0 do_xcode=0 do_test=0

    [[ $# -eq 0 ]] && { do_build=1; do_run=1; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --setup) do_setup=1 ;;
            --build) do_build=1 ;;
            --run) do_run=1 ;;
            --xcode) do_xcode=1 ;;
            --test) do_test=1 ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown argument: $1" ;;
        esac
        shift
    done

    if [[ $do_test -eq 1 ]]; then
        needs_setup && run_setup
        run_test
        exit 0
    fi

    if [[ $do_xcode -eq 1 ]]; then
        needs_setup && run_setup
        run_xcode
        exit 0
    fi

    if [[ $do_setup -eq 1 ]]; then
        run_setup
        [[ $do_build -eq 0 && $do_run -eq 0 ]] && info "Setup complete."
    elif needs_setup; then
        info "Dependencies are not ready; running setup first..."
        run_setup
    fi

    [[ $do_build -eq 1 ]] && run_build
    [[ $do_run -eq 1 ]] && run_app
}

main "$@"
