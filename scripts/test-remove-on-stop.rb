#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

ROOT = Pathname(__dir__).parent
VALIDATOR = ROOT.join("scripts", "validate-no-shell-hook.rb")

class RemoveOnStopContractTest < Minitest::Test
  def test_product_exposes_one_actionable_migration_notice_path
    config = ROOT.join("Sources", "quill", "Config.swift").read
    application = ROOT.join("Sources", "quill", "Quill.swift").read

    assert_includes config, "static func migrationNotices(in config:"
    assert_includes config, 'config.keys.contains("on_stop")'
    assert_includes config, "configuration update required"
    assert_includes config, "no longer supported"
    assert_includes config, "ignored"
    assert_includes application, "Config.migrationNotices()"
    assert_equal 1, application.scan("Config.migrationNotices()").count
    assert_includes application, "reportConfigMigrationNotices("
    assert_includes application, "notifyUser(title: title, body: message)"
  end

  def test_current_product_has_no_shell_hook_consumer
    output, status = run_validator(ROOT)

    assert status.success?, output
  end

  def test_validator_allows_reviewed_argument_vector_process_sites
    with_fixture do |fixture|
      write_reviewed_process_sites(fixture)

      output, status = run_validator(fixture)

      assert status.success?, output
    end
  end

  def test_validator_rejects_direct_and_environment_selected_interpreters
    probes = {
      "direct sh" => 'task.launchPath = "/bin/sh"',
      "alternate bash" => 'task.launchPath = "/bin/bash"',
      "alternate zsh" => 'task.launchPath = "/bin/zsh"',
      "alternate fish" => 'task.launchPath = "/usr/bin/fish"',
      "environment-selected sh" => <<~SWIFT
        task.launchPath = "/usr/bin/env"
        task.arguments = ["sh", "-c", command]
      SWIFT
    }

    probes.each do |name, source|
      with_fixture do |fixture|
        write_reviewed_process_sites(fixture)
        write_source(fixture, "Sources/quill/Unsafe.swift", <<~SWIFT)
          import Foundation
          let task = Process()
          #{source}
        SWIFT

        output, status = run_validator(fixture)

        refute status.success?, "#{name} unexpectedly passed:\n#{output}"
        assert_match(/command interpreter|unreviewed Process site/, output)
      end
    end
  end

  def test_validator_rejects_retired_hook_identifiers
    %w[onStop runHook].each do |identifier|
      with_fixture do |fixture|
        write_reviewed_process_sites(fixture)
        write_source(
          fixture,
          "Sources/quill/Legacy.swift",
          "func #{identifier}() {}\n"
        )

        output, status = run_validator(fixture)

        refute status.success?, "#{identifier} unexpectedly passed:\n#{output}"
        assert_includes output, "retired #{identifier} identifier"
      end
    end
  end

  def test_validator_rejects_an_unreviewed_non_shell_process_site
    with_fixture do |fixture|
      write_reviewed_process_sites(fixture)
      write_source(fixture, "Sources/quill/Unexpected.swift", <<~SWIFT)
        import Foundation
        let task = Process()
        task.launchPath = "/usr/bin/true"
      SWIFT

      output, status = run_validator(fixture)

      refute status.success?, output
      assert_includes output, "unreviewed Process site"
    end
  end

  def test_validator_rejects_an_extra_executable_in_a_reviewed_process_site
    with_fixture do |fixture|
      write_reviewed_process_sites(fixture)
      write_source(fixture, "Sources/quill/Notify.swift", <<~SWIFT)
        import Foundation
        let notification = Process()
        notification.launchPath = "/usr/bin/osascript"
        let unexpected = Process()
        unexpected.launchPath = "/usr/bin/true"
      SWIFT

      output, status = run_validator(fixture)

      refute status.success?, output
      assert_includes output, "reviewed Process site contains unapproved executables"
    end
  end

  def test_ci_runs_remove_on_stop_contract_and_validator
    workflow = ROOT.join(".github", "workflows", "test.yml").read

    assert_includes workflow, "ruby scripts/test-remove-on-stop.rb"
    assert_includes workflow, "ruby scripts/validate-no-shell-hook.rb"
  end

  private

  def run_validator(root)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      VALIDATOR.to_s,
      root.to_s
    )
    [stdout + stderr, status]
  end

  def with_fixture
    Dir.mktmpdir("quill-remove-on-stop") do |directory|
      yield Pathname(directory)
    end
  end

  def write_reviewed_process_sites(root)
    write_source(root, "Sources/quill/Notify.swift", <<~SWIFT)
      import Foundation
      let task = Process()
      task.launchPath = "/usr/bin/osascript"
      task.arguments = ["-e", "display notification"]
    SWIFT
    write_source(root, "Sources/quill/Install.swift", <<~SWIFT)
      import Foundation
      let task = Process()
      task.launchPath = "/bin/launchctl"
      task.arguments = ["bootstrap"]
    SWIFT
  end

  def write_source(root, relative, contents)
    path = root.join(relative)
    FileUtils.mkdir_p(path.dirname)
    path.write(contents)
  end
end
