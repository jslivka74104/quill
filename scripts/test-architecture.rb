#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

ROOT = Pathname(__dir__).parent
ARCH = ROOT.join("docs", "architecture")

class ArchitectureContractTest < Minitest::Test
  REQUIRED_ADRS = %w[
    0001-single-application-process.md
    0002-folder-authority-and-sqlite-index.md
    0003-versioned-transcripts-and-scoped-identity.md
    0004-verified-model-provisioning.md
  ].freeze

  REQUIRED_SCHEMAS = %w[
    annotations-v1.schema.json
    part-v1.schema.json
    session-v2.schema.json
    state-v1.schema.json
    transcript-v2.schema.json
  ].freeze

  def test_required_architecture_package_is_exact
    actual_adrs = Dir[ARCH.join("adr", "*.md").to_s].map { |path| File.basename(path) }.sort
    actual_schemas = Dir[ARCH.join("schemas", "*.schema.json").to_s]
      .map { |path| File.basename(path) }
      .sort

    assert_equal REQUIRED_ADRS, actual_adrs
    assert_equal REQUIRED_SCHEMAS,
                 actual_schemas
  end

  def test_validator_rejects_a_missing_named_schema_even_if_its_link_is_removed
    with_probe_copy do |probe|
      schema = probe.join("docs", "architecture", "schemas", "part-v1.schema.json")
      FileUtils.mv(schema, probe.join("part-v1.schema.json.omitted"))
      remove_lines_containing(
        probe.join("docs", "architecture", "quill-v2-architecture.md"),
        "part-v1.schema.json"
      )

      output, status = run_validator(probe)

      refute status.success?, output
      assert_includes output, "part-v1.schema.json"
    end
  end

  def test_validator_rejects_a_missing_named_adr_even_if_its_link_is_removed
    with_probe_copy do |probe|
      adr = probe.join(
        "docs", "architecture", "adr", "0004-verified-model-provisioning.md"
      )
      FileUtils.mv(adr, probe.join("0004-verified-model-provisioning.md.omitted"))
      remove_lines_containing(
        probe.join("docs", "architecture", "quill-v2-architecture.md"),
        "0004-verified-model-provisioning.md"
      )

      output, status = run_validator(probe)

      refute status.success?, output
      assert_includes output, "0004-verified-model-provisioning.md"
    end
  end

  def test_validator_rejects_an_unreviewed_extra_normative_schema
    with_probe_copy do |probe|
      FileUtils.cp(
        probe.join("docs", "architecture", "schemas", "state-v1.schema.json"),
        probe.join("docs", "architecture", "schemas", "unreviewed-v1.schema.json")
      )

      output, status = run_validator(probe)

      refute status.success?, output
      assert_includes output, "unreviewed-v1.schema.json"
    end
  end

  def test_session_schema_can_represent_preterminal_capture
    schema = read_schema("session-v2.schema.json")
    properties = schema.fetch("properties")
    track = schema.fetch("$defs").fetch("track")

    assert_nullable properties.fetch("started_at")
    assert_nullable track.fetch("properties").fetch("start_offset_ms")
    assert_includes track.fetch("properties").fetch("capture_status").fetch("enum"), "pending"
    assert_includes track.fetch("properties").fetch("capture_status").fetch("enum"), "recording"
  end

  def test_speaker_labels_are_durable_history_events
    schema = read_schema("annotations-v1.schema.json")
    item_ref = schema.fetch("properties").fetch("speaker_labels").fetch("items").fetch("$ref")
    event = schema.fetch("$defs")["speaker_label_event"]

    refute_nil event, "speaker labels must use immutable history events"
    return unless event

    required = event.fetch("required")

    assert_equal "#/$defs/speaker_label_event", item_ref
    assert_includes required, "speaker_label_event_id"
    assert_includes required, "created_at"
    assert_includes required, "supersedes_speaker_label_event_id"
  end

  def test_phase_zero_defers_measurement_gates_without_blocking_test_foundation
    baseline = read_utf8(ARCH.join("phase-0-baseline.md"))

    assert_includes baseline, "Status: **Accepted — Phase 0 complete**"
    assert_includes baseline, "deferred to the foundation boundary"
    assert_includes baseline, "Phase 2\nmay begin only after the remediation branch also passes its pinned CI lane."
    refute_includes baseline,
                    "The full-size model and signed App Sandbox/Core Audio feasibility gate\n" \
                    "      has measured evidence."
  end

  def test_governing_architecture_documents_are_accepted
    architecture = read_utf8(ARCH.join("quill-v2-architecture.md"))
    governing_rules = read_utf8(ARCH.join("governing-rules.md"))

    assert_includes architecture, "Status: **Accepted**"
    assert_includes governing_rules, "Status: **Accepted**"
  end

  def test_adrs_record_owner_acceptance_without_clearing_adr_0004_for_production
    REQUIRED_ADRS.first(3).each do |name|
      assert_includes read_utf8(ARCH.join("adr", name)), "Status: **Accepted**"
    end

    model_adr = read_utf8(ARCH.join("adr", REQUIRED_ADRS.last))
    assert_includes model_adr, "Status: **Accepted — Option C conditionally selected"
    assert_includes model_adr, "It does not clear Option C for production use."
  end

  def test_phase_one_evidence_does_not_deny_its_recorded_remote_runs
    evidence = read_utf8(ROOT.join("docs", "testing", "test-foundation.tdd.md"))

    refute_includes evidence, "A remote GitHub Actions result cannot exist"
  end

  def test_ci_enforces_architecture_and_swift_tests
    workflow = read_utf8(ROOT.join(".github", "workflows", "test.yml"))

    assert_includes workflow, "ruby scripts/test-architecture.rb"
    assert_includes workflow, "ruby scripts/validate-architecture.rb"
    assert_includes workflow, "swift test"
  end

  def test_parakeet_segmentation_is_accessible_to_package_tests
    source = read_utf8(ROOT.join("Sources", "quill", "Transcription", "ParakeetEngine.swift"))

    refute_includes source, "private static func segments"
    assert_includes source, "static func segments"
  end

  def test_validator_runs_without_locale_environment
    output, status = run_validator(
      ROOT,
      {
        "LANG" => "C",
        "LC_ALL" => "C",
        "RUBYOPT" => "-EUS-ASCII:US-ASCII"
      }
    )

    assert status.success?, output
  end

  private

  def read_utf8(path)
    source = Pathname(path).binread.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "#{path}: source is not valid UTF-8" unless source.valid_encoding?

    source
  end

  def assert_nullable(fragment)
    one_of = fragment["oneOf"]
    refute_nil one_of, "#{fragment.inspect} must accept null"
    return unless one_of

    types = one_of.map { |option| option["type"] }
    assert_includes types, "null"
  end

  def read_schema(name)
    JSON.parse(read_utf8(ARCH.join("schemas", name)))
  end

  def remove_lines_containing(path, needle)
    path.binwrite(read_utf8(path).lines.reject { |line| line.include?(needle) }.join)
  end

  def run_validator(probe, environment = {})
    stdout, stderr, status = Open3.capture3(
      environment,
      RbConfig.ruby,
      probe.join("scripts", "validate-architecture.rb").to_s
    )
    [stdout + stderr, status]
  end

  def with_probe_copy
    Dir.mktmpdir("quill-architecture-test") do |directory|
      probe = Pathname(directory)
      FileUtils.cp_r(ROOT.join("docs"), probe)
      FileUtils.mkdir_p(probe.join("scripts"))
      FileUtils.cp(ROOT.join("scripts", "validate-architecture.rb"), probe.join("scripts"))
      yield probe
    end
  end
end
