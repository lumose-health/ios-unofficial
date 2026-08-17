#!/usr/bin/env bash
#
# Regenerate the EC-JPAKE known-answer vectors from the Kotlin implementation and
# byte-diff them against the fixtures committed in this repo (SPK-2, AC 5/6).
#
# The Android checkout is treated as strictly read-only: all work happens in a
# disposable worktree that is removed on every exit path, so `git worktree list`
# in the main checkout shows only pre-existing entries afterwards (AC 6).
#
# Usage:  bash scripts/spk2/verify_vectors.sh             verify (the gate)
#         bash scripts/spk2/verify_vectors.sh --update    rewrite the committed fixtures
# Env:    ANDROID_REPO  path to the android-unofficial checkout
#                       (default /Users/devbox/repos/lumose-health/android-unofficial)

set -euo pipefail

MODE="verify"
case "${1:-}" in
  "") ;;
  --update) MODE="update" ;;
  *) echo "usage: $0 [--update]" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
ANDROID_REPO="${ANDROID_REPO:-/Users/devbox/repos/lumose-health/android-unofficial}"

FIXTURE_DIR="$REPO_ROOT/Tests/Fixtures/EcJpake"
HARNESS_SRC="$REPO_ROOT/scripts/spk2/harness/EcJpakeKatGeneratorTest.kt"
# Where the harness lands inside the worktree; mirrors the module's test source set.
HARNESS_DEST_DIR="plugins/shipped/tandem/src/test/java/com/glycemicgpt/mobile/ble/crypto"
GRADLE_MODULE=":tandem-pump-driver"
GRADLE_TEST_FILTER="*EcJpakeKatGeneratorTest*"

die() { echo "FAIL: $*" >&2; exit 1; }

[ -d "$ANDROID_REPO/.git" ] || [ -f "$ANDROID_REPO/.git" ] \
  || die "ANDROID_REPO is not a git checkout: $ANDROID_REPO"
[ -f "$HARNESS_SRC" ] || die "harness source not found: $HARNESS_SRC"
if [ "$MODE" = "update" ]; then
  mkdir -p "$FIXTURE_DIR"
else
  [ -d "$FIXTURE_DIR" ] || die "committed fixtures not found: $FIXTURE_DIR"
fi

WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/spk2-ecjpake-worktree.XXXXXX")"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/spk2-ecjpake-regen.XXXXXX")"
REGEN_DIR="$WORKDIR/fixtures"
mkdir -p "$REGEN_DIR"

cleanup() {
  local status=$?
  # `worktree add` refuses an existing directory, so mktemp's dir is removed first
  # and recreated by git; on cleanup both the registration and the files must go.
  if [ -e "$WORKTREE" ] || git -C "$ANDROID_REPO" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $WORKTREE"; then
    git -C "$ANDROID_REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORKTREE" "$WORKDIR"
  git -C "$ANDROID_REPO" worktree prune >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT

rmdir "$WORKTREE"
git -C "$ANDROID_REPO" worktree add --detach "$WORKTREE" HEAD >/dev/null \
  || die "could not create a disposable worktree of $ANDROID_REPO"

ANDROID_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"
echo "Regenerating from $ANDROID_REPO @ $ANDROID_SHA"

mkdir -p "$WORKTREE/$HARNESS_DEST_DIR"
cp "$HARNESS_SRC" "$WORKTREE/$HARNESS_DEST_DIR/"

# The worktree has no local.properties, so carry over whatever the main checkout uses
# to locate the Android SDK (git worktrees do not copy untracked files).
if [ -f "$ANDROID_REPO/local.properties" ]; then
  cp "$ANDROID_REPO/local.properties" "$WORKTREE/local.properties"
fi

# The output directory reaches the forked test JVM as a system property. It is injected
# through an init script rather than an environment variable because the Gradle daemon
# may already be running with a different environment, in which case the test JVM would
# never see an exported variable.
INIT_SCRIPT="$WORKDIR/spk2-init.gradle"
cat >"$INIT_SCRIPT" <<'INIT'
// Injected by scripts/spk2/verify_vectors.sh; never written into the Android repo.
allprojects {
    tasks.withType(Test).configureEach {
        systemProperty 'spk2.fixture.out', (project.findProperty('spk2FixtureOut') ?: '')
        // The capture must really execute every run: an UP-TO-DATE or cache-restored
        // result would leave the regen directory empty and silently pass the byte-diff.
        outputs.upToDateWhen { false }
        outputs.cacheIf { false }
    }
}
INIT

"$WORKTREE/gradlew" -p "$WORKTREE" --init-script "$INIT_SCRIPT" \
  -Pspk2FixtureOut="$REGEN_DIR" \
  "$GRADLE_MODULE:testDebugUnitTest" --tests "$GRADLE_TEST_FILTER" \
  || die "the Kotlin capture harness did not run cleanly"

shopt -s nullglob
regenerated=("$REGEN_DIR"/*.json)
shopt -u nullglob
[ "${#regenerated[@]}" -gt 0 ] || die "the harness produced no fixtures in $REGEN_DIR"

if [ "$MODE" = "update" ]; then
  # Drop fixtures the harness no longer produces, so --update leaves exactly the
  # generated set and the verify-mode byte-diff stays meaningful.
  shopt -s nullglob
  for existing in "$FIXTURE_DIR"/*.json; do
    [ -f "$REGEN_DIR/$(basename "$existing")" ] || rm -f "$existing"
  done
  shopt -u nullglob
  cp "${regenerated[@]}" "$FIXTURE_DIR/"
  echo "OK: wrote ${#regenerated[@]} fixture(s) into $FIXTURE_DIR (regenerated from $ANDROID_SHA)"
  echo "NOTE: --update does not verify; re-run without --update to prove the committed state."
  exit 0
fi

# Byte-diff regenerated against committed. The README is documentation, not
# generated output, so it is excluded rather than expected on both sides.
if ! diff --recursive --exclude=README.md "$FIXTURE_DIR" "$REGEN_DIR"; then
  die "regenerated vectors differ from the committed fixtures in $FIXTURE_DIR"
fi

echo "OK: ${#regenerated[@]} regenerated fixture(s) are byte-identical to $FIXTURE_DIR"
