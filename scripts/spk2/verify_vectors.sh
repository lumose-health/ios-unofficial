#!/usr/bin/env bash
#
# Regenerate the EC-JPAKE known-answer vectors from the Kotlin implementation and
# byte-diff them against the fixtures committed in this repo (SPK-2, AC 5/6).
#
# The Android checkout is treated as strictly read-only: all work happens in a
# disposable worktree created at the revision pinned in scripts/spk2/provenance.env
# (never the checkout's mutable HEAD), and that one worktree — no other — is removed
# before the script exits. If its removal fails — or cannot be confirmed, because the
# worktree query itself failed — the script exits nonzero, so a leftover registration
# can never be reported as a passing gate (AC 6).
#
# Usage:  bash scripts/spk2/verify_vectors.sh             verify (the gate)
#         bash scripts/spk2/verify_vectors.sh --update    rewrite the committed fixtures
# Env:    ANDROID_REPO  path to the android-unofficial checkout
#                       (default /Users/devbox/repos/lumose-health/android-unofficial)
#         ANDROID_SHA   re-pin to a different revision. --update only; in verify mode
#                       the pin is the committed one, otherwise the gate would prove
#                       nothing about the recorded provenance. --update rewrites
#                       provenance.env; the README provenance table must be updated in
#                       the same commit (validate_fixtures.py fails while they differ).

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
PROVENANCE_FILE="$REPO_ROOT/scripts/spk2/provenance.env"
# Where the harness lands inside the worktree; mirrors the module's test source set.
HARNESS_DEST_DIR="plugins/shipped/tandem/src/test/java/com/glycemicgpt/mobile/ble/crypto"
GRADLE_MODULE=":tandem-pump-driver"
GRADLE_TEST_FILTER="*EcJpakeKatGeneratorTest*"

die() { echo "FAIL: $*" >&2; exit 1; }

[ -d "$ANDROID_REPO/.git" ] || [ -f "$ANDROID_REPO/.git" ] \
  || die "ANDROID_REPO is not a git checkout: $ANDROID_REPO"
[ -f "$HARNESS_SRC" ] || die "harness source not found: $HARNESS_SRC"
[ -f "$PROVENANCE_FILE" ] || die "provenance pin not found: $PROVENANCE_FILE"
if [ "$MODE" = "update" ]; then
  mkdir -p "$FIXTURE_DIR"
else
  [ -d "$FIXTURE_DIR" ] || die "committed fixtures not found: $FIXTURE_DIR"
fi

# -- Which revision to regenerate from ----------------------------------------

PINNED_SHA="$(sed -n 's/^ANDROID_SHA=\([0-9a-f]\{40\}\)$/\1/p' "$PROVENANCE_FILE")"
[ -n "$PINNED_SHA" ] \
  || die "no 'ANDROID_SHA=<40 hex chars>' line in $PROVENANCE_FILE"

REPIN="${ANDROID_SHA:-}"
if [ -n "$REPIN" ]; then
  [ "$MODE" = "update" ] \
    || die "ANDROID_SHA overrides the committed provenance pin and is only allowed with --update"
  git -C "$ANDROID_REPO" rev-parse --verify --quiet "$REPIN^{commit}" >/dev/null \
    || die "ANDROID_SHA $REPIN is not a commit in $ANDROID_REPO"
  TARGET_SHA="$(git -C "$ANDROID_REPO" rev-parse "$REPIN^{commit}")"
else
  TARGET_SHA="$PINNED_SHA"
fi

# The pin is worthless if the checkout no longer contains it: say so, rather than
# silently regenerating from whatever that checkout happens to be at now.
git -C "$ANDROID_REPO" rev-parse --verify --quiet "$TARGET_SHA^{commit}" >/dev/null \
  || die "the pinned revision $TARGET_SHA is not present in $ANDROID_REPO (fetch it, or re-pin with ANDROID_SHA=<sha> --update)"

# -- Disposable worktree -------------------------------------------------------

# Resolve symlinks up front: on macOS mktemp reports /var/folders/... while git
# registers the physical /private/var/folders/... path, and cleanup below matches its
# own registration by exact path — it must not be looking for the wrong spelling.
WORKTREE="$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/spk2-ecjpake-worktree.XXXXXX")" && pwd -P)"
WORKDIR="$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/spk2-ecjpake-regen.XXXXXX")" && pwd -P)"
REGEN_DIR="$WORKDIR/fixtures"

# Three states, deliberately not two: an unreadable/failing `git worktree list` is
# NOT evidence that the worktree is gone. Collapsing the two would let a broken
# query silently look like a clean checkout and pass the gate (AC 6).
#   0 = registered   1 = confirmed absent   2 = the query itself failed
WORKTREE_REGISTERED=0
WORKTREE_ABSENT=1
WORKTREE_QUERY_FAILED=2

worktree_registration_state() {
  local listing
  listing="$(git -C "$ANDROID_REPO" worktree list --porcelain 2>/dev/null)" \
    || return "$WORKTREE_QUERY_FAILED"
  printf '%s\n' "$listing" | grep -qxF "worktree $WORKTREE" \
    && return "$WORKTREE_REGISTERED"
  return "$WORKTREE_ABSENT"
}

cleanup() {
  local status=$?
  local failed=0
  local state=0

  worktree_registration_state || state=$?
  case "$state" in
    # Only ever touch the worktree this run created: no repo-wide `worktree prune`,
    # which would also drop unrelated stale registrations in a shared checkout.
    "$WORKTREE_REGISTERED")
      git -C "$ANDROID_REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || failed=1
      ;;
    "$WORKTREE_QUERY_FAILED")
      echo "FAIL: could not list the worktrees of $ANDROID_REPO, so the disposable worktree $WORKTREE was not removed" >&2
      failed=1
      ;;
  esac
  rm -rf "$WORKTREE" "$WORKDIR" || failed=1

  # Cleanup is part of the gate (AC 6), so verify it rather than assume it.
  state=0
  worktree_registration_state || state=$?
  if [ "$state" = "$WORKTREE_REGISTERED" ]; then
    echo "FAIL: $ANDROID_REPO still registers the disposable worktree $WORKTREE" >&2
    failed=1
  elif [ "$state" = "$WORKTREE_QUERY_FAILED" ]; then
    echo "FAIL: could not list the worktrees of $ANDROID_REPO, so removal of $WORKTREE is unconfirmed; check it by hand" >&2
    failed=1
  fi
  if [ -e "$WORKTREE" ] || [ -e "$WORKDIR" ]; then
    echo "FAIL: could not remove the temporary directories ($WORKTREE, $WORKDIR)" >&2
    failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    echo "FAIL: the Android checkout was not left clean; resolve this by hand before trusting the gate" >&2
    [ "$status" -ne 0 ] || status=1
  fi
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$REGEN_DIR"
rmdir "$WORKTREE"
git -C "$ANDROID_REPO" worktree add --detach "$WORKTREE" "$TARGET_SHA" >/dev/null \
  || die "could not create a disposable worktree of $ANDROID_REPO at $TARGET_SHA"

# Cleanup finds its own worktree by exact registered path, so prove that lookup works
# now — while the worktree still exists — rather than silently leaking it later.
preflight_state=0
worktree_registration_state || preflight_state=$?
case "$preflight_state" in
  "$WORKTREE_REGISTERED") ;;
  "$WORKTREE_ABSENT")
    die "git did not register the disposable worktree under the path it was given ($WORKTREE); refusing to run, since cleanup could not find it afterwards" ;;
  *)
    die "could not list the worktrees of $ANDROID_REPO; refusing to run, since cleanup could not confirm removal of $WORKTREE afterwards" ;;
esac

ANDROID_SHA_ACTUAL="$(git -C "$WORKTREE" rev-parse HEAD)"
[ "$ANDROID_SHA_ACTUAL" = "$TARGET_SHA" ] \
  || die "the worktree is at $ANDROID_SHA_ACTUAL, not the requested $TARGET_SHA"
echo "Regenerating from $ANDROID_REPO @ $TARGET_SHA"

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
  if [ "$TARGET_SHA" != "$PINNED_SHA" ]; then
    # Re-pinning is explicit (ANDROID_SHA=... --update) and must not leave the pin
    # and the fixtures describing different revisions.
    tmp_provenance="$WORKDIR/provenance.env"
    sed "s/^ANDROID_SHA=.*$/ANDROID_SHA=$TARGET_SHA/" "$PROVENANCE_FILE" >"$tmp_provenance"
    cp "$tmp_provenance" "$PROVENANCE_FILE"
    echo "NOTE: re-pinned $(basename "$PROVENANCE_FILE") to $TARGET_SHA."
    echo "NOTE: update the provenance table in $FIXTURE_DIR/README.md to match, in the same commit;"
    echo "      validate_fixtures.py fails while the README and the pin disagree."
  fi
  echo "OK: wrote ${#regenerated[@]} fixture(s) into $FIXTURE_DIR (regenerated from $TARGET_SHA)"
  echo "NOTE: --update does not verify; re-run without --update to prove the committed state."
  exit 0
fi

# Byte-diff regenerated against committed. The README is documentation, not
# generated output, so it is excluded rather than expected on both sides.
if ! diff --recursive --exclude=README.md "$FIXTURE_DIR" "$REGEN_DIR"; then
  die "regenerated vectors differ from the committed fixtures in $FIXTURE_DIR"
fi

echo "OK: ${#regenerated[@]} regenerated fixture(s) are byte-identical to $FIXTURE_DIR"
