#!/usr/bin/env bash
set -euo pipefail

# Force a UTF-8 locale so the embedded Ruby heredoc can contain Chinese
# text in raise() messages (e.g. README must keep current native version
# line) without invalid-multibyte errors under C / POSIX locale.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/build.yml"
README_FILE="$ROOT_DIR/README.md"
PROJECT_INDEX_FILE="$ROOT_DIR/docs/PROJECT_INDEX.md"
RELEASE_DOC_FILE="$ROOT_DIR/docs/RELEASE_AND_VALIDATION.md"
RELEASE_AUDIT_DOC_FILE="$ROOT_DIR/docs/RELEASE_CANDIDATE_AUDIT.md"
LIVE_SOURCE_TESTS_FILE="$ROOT_DIR/macos/Tests/CPaperNativeTests/LiveSourceTests.swift"
VERIFY_DMG_SCRIPT="$ROOT_DIR/scripts/verify_native_dmg.sh"
RELEASE_AUDIT_SCRIPT="$ROOT_DIR/scripts/run_native_release_audit.sh"
SWIFTPM_RETRY_HELPER="$ROOT_DIR/scripts/lib/swiftpm_retry_helpers.sh"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow)
      WORKFLOW_FILE="$2"
      shift 2
      ;;
    --readme)
      README_FILE="$2"
      shift 2
      ;;
    --project-index)
      PROJECT_INDEX_FILE="$2"
      shift 2
      ;;
    --release-doc)
      RELEASE_DOC_FILE="$2"
      shift 2
      ;;
    --release-audit-doc)
      RELEASE_AUDIT_DOC_FILE="$2"
      shift 2
      ;;
    --live-source-tests)
      LIVE_SOURCE_TESTS_FILE="$2"
      shift 2
      ;;
    --verify-dmg-script)
      VERIFY_DMG_SCRIPT="$2"
      shift 2
      ;;
    --release-audit-script)
      RELEASE_AUDIT_SCRIPT="$2"
      shift 2
      ;;
    --swiftpm-retry-helper)
      SWIFTPM_RETRY_HELPER="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

fail() {
  echo "RELEASE DOC CHECK: $1" >&2
  exit 1
}

ruby - "$WORKFLOW_FILE" "$README_FILE" "$PROJECT_INDEX_FILE" "$RELEASE_DOC_FILE" "$RELEASE_AUDIT_DOC_FILE" "$VERIFY_DMG_SCRIPT" "$RELEASE_AUDIT_SCRIPT" "$SWIFTPM_RETRY_HELPER" <<'RUBY'
require "yaml"

workflow_path, readme_path, project_index_path, release_doc_path, release_audit_doc_path, verify_dmg_script_path, release_audit_script_path, swiftpm_retry_helper_path = ARGV
workflow = YAML.load_file(workflow_path)
jobs = workflow.fetch("jobs")
validate = jobs.fetch("validate")
package = jobs.fetch("package")
release = jobs.fetch("release")

validate_steps = validate.fetch("steps")
validate_step_names = validate_steps.map { |step| step["name"] }
doc_step = validate_steps.find { |step| step["name"] == "Check release documentation consistency" }
raise "validate job missing release-doc consistency step" unless doc_step
raise "release-doc consistency step must run scripts/check_release_docs.sh" unless doc_step["run"].to_s.include?("bash scripts/check_release_docs.sh")

swift_test_step = validate_steps.find { |step| step["name"] == "Run Swift tests" }
raise "validate job missing swift test step" unless swift_test_step
raise "validate job must run swift test --jobs 1" unless swift_test_step["run"].to_s.include?("swift test --jobs 1")
raise "validate job must set CPAPER_SWIFT_SCRATCH_PATH" unless validate["env"].to_h.fetch("CPAPER_SWIFT_SCRATCH_PATH", "").include?("cpaper-native-swiftpm")
raise "validate job must pass --scratch-path to swift test" unless swift_test_step["run"].to_s.include?('--scratch-path "$CPAPER_SWIFT_SCRATCH_PATH"')
raise "validate job must source scripts/lib/swiftpm_retry_helpers.sh" unless swift_test_step["run"].to_s.include?("source scripts/lib/swiftpm_retry_helpers.sh")
raise "validate job must use run_swiftpm_command_with_retry" unless swift_test_step["run"].to_s.include?("run_swiftpm_command_with_retry")

package_needs = Array(package["needs"])
raise "package job must depend on validate" unless package_needs == ["validate"]
package_if = package["if"].to_s
raise "package job must stay gated to workflow_dispatch or push" unless package_if.include?("workflow_dispatch") && package_if.include?("push")
package_steps = package.fetch("steps")
verify_step = package_steps.find { |step| step["name"] == "Verify packaged native DMG" }
raise "package job missing verify step" unless verify_step
raise "package verify step must run scripts/verify_native_dmg.sh" unless verify_step["run"].to_s.include?("bash scripts/verify_native_dmg.sh")
raise "missing verify_native_dmg.sh script" unless File.file?(verify_dmg_script_path)
raise "missing run_native_release_audit.sh script" unless File.file?(release_audit_script_path)
raise "missing swiftpm retry helper script" unless File.file?(swiftpm_retry_helper_path)

release_needs = Array(release["needs"])
raise "release job must depend on package" unless release_needs == ["package"]
release_if = release["if"].to_s
raise "release job must remain tag-only" unless release_if.include?("startsWith(github.ref, 'refs/tags/')")

on_section = workflow["on"] || workflow[true] || workflow[:on]
raise "workflow missing on section" unless on_section
pull_request_paths = on_section.fetch("pull_request").fetch("paths")
push_paths = on_section.fetch("push").fetch("paths")
required_paths = [
  "README.md",
  "docs/PROJECT_INDEX.md",
  "docs/RELEASE_CANDIDATE_AUDIT.md",
  "docs/RELEASE_AND_VALIDATION.md",
  "scripts/check_release_docs.sh",
  "scripts/run_native_release_audit.sh",
  "scripts/verify_native_dmg.sh"
]
required_paths.each do |path|
  raise "pull_request paths missing #{path}" unless pull_request_paths.include?(path)
  raise "push paths missing #{path}" unless push_paths.include?(path)
end

release_doc = File.read(release_doc_path, encoding: "UTF-8")
release_audit_doc = File.read(release_audit_doc_path, encoding: "UTF-8")
[
  "validate/package/release",
  "tag-only",
  "workflow_dispatch",
  "ad hoc",
  "Developer ID/notary",
  "--release-candidate",
  "scratch directory redirected outside the repository tree",
  "retry the known transient SwiftPM `input file ... was modified during the build` failure",
  "external-link pending",
  "privacy/disclaimer/data source reliability",
  "RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests",
  "bash scripts/check_release_docs.sh",
  "bash scripts/run_native_release_audit.sh",
  "bash scripts/verify_native_dmg.sh"
].each do |needle|
  raise "release doc missing #{needle}" unless release_doc.include?(needle)
end

project_index = File.read(project_index_path, encoding: "UTF-8")
raise "project index must reference docs/RELEASE_AND_VALIDATION.md" unless project_index.include?("docs/RELEASE_AND_VALIDATION.md")
raise "project index must reference docs/RELEASE_CANDIDATE_AUDIT.md" unless project_index.include?("docs/RELEASE_CANDIDATE_AUDIT.md")
raise "project index validate summary must mention release-documentation consistency" unless project_index.include?("release-documentation consistency")
raise "project index must index scripts/run_native_release_audit.sh" unless project_index.include?("scripts/run_native_release_audit.sh")
raise "project index must index scripts/verify_native_dmg.sh" unless project_index.include?("scripts/verify_native_dmg.sh")
raise "project index must index scripts/lib/swiftpm_retry_helpers.sh" unless project_index.include?("scripts/lib/swiftpm_retry_helpers.sh")

readme = File.read(readme_path, encoding: "UTF-8")
raise "README must keep current native version line" unless readme.include?("当前 native 主线版本：`")
raise "README must mention bash scripts/run_native_release_audit.sh" unless readme.include?("bash scripts/run_native_release_audit.sh")
raise "README must mention bash scripts/verify_native_dmg.sh" unless readme.include?("bash scripts/verify_native_dmg.sh")
raise "README must mention --release-candidate" unless readme.include?("--release-candidate")

readme_version = readme[/当前 native 主线版本：`([^`]+)`/, 1]
raise "README current native version line must be parseable" unless readme_version
raise "release audit doc must mention current native version #{readme_version}" unless release_audit_doc.include?(readme_version)
raise "release audit doc must not keep stale 6.0.5 artifact evidence" if release_audit_doc.include?("6.0.5")
raise "release audit doc must not keep stale 2026-06-18 audit baseline" if release_audit_doc.include?("Audit date: `2026-06-18`")

puts "Release documentation workflow checks passed."
RUBY

python3 - "$LIVE_SOURCE_TESTS_FILE" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
required_tests = [
    "testLiveSubjectFallbackCanPopulateSearchInputsWithoutFrankcie",
    "testLiveAutomaticSearchFallbackReturnsDownloadablePDFWhenFrankcieIsUnavailable",
    "testLiveManualEasyPaperSearchStaysOnSelectedSource",
    "testLiveManualPapaCambridgeKeepsClearUnavailableReasonOrReturnsOwnPDF",
    "testLiveEasyPaperSearchReturnsDownloadablePDF",
    "testLivePastPapersReturnsPDFsOrClearUnavailableReason",
    "testLivePapaCambridgeReturnsPDFsOrClearUnavailableReason",
]
missing = [name for name in required_tests if name not in text]
if missing:
    raise SystemExit(f"Missing expected live source coverage: {', '.join(missing)}")
print("Live source expectation checks passed.")
PY

echo "Release documentation consistency check passed."
