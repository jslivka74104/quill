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
    config = read_utf8(ROOT.join("Sources", "quill", "Config.swift"))
    application = read_utf8(ROOT.join("Sources", "quill", "Quill.swift"))

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
        assert_match(/command interpreter|unreviewed process launch primitive/, output)
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
      assert_includes output, "unreviewed process launch primitive"
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
      assert_includes output, "reviewed Process site contains unapproved executable assignments"
    end
  end

  def test_validator_rejects_whitespace_and_constructed_process_bypass
    with_fixture do |fixture|
      write_reviewed_process_sites(fixture)
      source = <<~SWIFT
        import Foundation
        let task = Process ()
        task.launchPath = "/bin/" + "sh"
      SWIFT
      path = write_source(fixture, "Sources/quill/WhitespaceBypass.swift", source)
      assert_swift_parses(path)

      output, status = run_validator(fixture)

      refute status.success?, output
      assert_includes output, "unreviewed process launch primitive"
    end
  end

  def test_validator_rejects_nstask_and_c_launch_primitives
    probes = {
      "NSTask" => <<~SWIFT,
        import Foundation
        let task = NSTask()
        task.launchPath = "/bin/csh"
      SWIFT
      "posix_spawn" => <<~SWIFT,
        import Darwin
        var processIdentifier: pid_t = 0
        _ = posix_spawn(&processIdentifier, "/usr/bin/true", nil, nil, nil, nil)
      SWIFT
      "system" => <<~SWIFT,
        import Darwin
        let executable = String(decoding: [47, 98, 105, 110, 47, 115, 104], as: UTF8.self)
        executable.withCString { _ = system($0) }
      SWIFT
      "popen" => <<~SWIFT,
        import Darwin
        let executable = String(decoding: [47, 98, 105, 110, 47, 115, 104], as: UTF8.self)
        executable.withCString { _ = popen($0, "r") }
      SWIFT
      "execvp" => <<~SWIFT,
        import Darwin
        let executable = String(decoding: [47, 98, 105, 110, 47, 115, 104], as: UTF8.self)
        executable.withCString { _ = execvp($0, nil) }
      SWIFT
    }

    probes.each do |name, source|
      with_fixture do |fixture|
        write_reviewed_process_sites(fixture)
        path = write_source(fixture, "Sources/quill/#{name}.swift", source)
        assert_swift_parses(path)

        output, status = run_validator(fixture)

        refute status.success?, "#{name} unexpectedly passed:\n#{output}"
        assert_includes output, "unreviewed process launch primitive"
      end
    end
  end

  def test_validator_rejects_aliased_launch_primitives
    probes = {
      "NSTask alias" => "import Foundation\nlet launcher = NSTask.self\n",
      "posix_spawn alias" => "import Darwin\nlet launcher = posix_spawn\n",
      "system alias" => "import Darwin\nlet launcher = system\n",
      "popen alias" => "import Darwin\nlet launcher = popen\n",
      "exec alias" => "import Darwin\nlet launcher = execvp\n",
      "dynamic loader alias" => "import Darwin\nlet launcher = dlsym\n",
    }

    probes.each do |name, source|
      with_fixture do |fixture|
        write_reviewed_process_sites(fixture)
        path = write_source(fixture, "Sources/quill/Alias.swift", source)
        assert_swift_parses(path)

        output, status = run_validator(fixture)

        refute status.success?, "#{name} unexpectedly passed:\n#{output}"
        assert_includes output, "unreviewed process launch primitive"
      end
    end
  end

  def test_validator_rejects_system_import_alias_and_silgen_name_bypasses
    probes = {
      "system import alias" => <<~SWIFT,
        import func Darwin.system
        let launcher = system
      SWIFT
      "silgen system binding" => <<~SWIFT,
        @_silgen_name("system")
        func c_shell(_ command: UnsafePointer<CChar>) -> Int32
      SWIFT
    }

    probes.each do |name, source|
      with_fixture do |fixture|
        write_reviewed_process_sites(fixture)
        path = write_source(fixture, "Sources/quill/Bypass.swift", source)
        assert_swift_parses(path)

        output, status = run_validator(fixture)

        refute status.success?, "#{name} unexpectedly passed:\n#{output}"
        assert_includes output, "unreviewed process launch primitive"
      end
    end
  end

  def test_validator_rejects_dynamic_reassignment_in_a_reviewed_process_site
    with_fixture do |fixture|
      write_reviewed_process_sites(fixture)
      source = <<~SWIFT
        import Foundation
        let notification = Process()
        notification.launchPath = "/usr/bin/osascript"
        notification.launchPath = "/bin/" + "sh"
      SWIFT
      path = write_source(fixture, "Sources/quill/Notify.swift", source)
      assert_swift_parses(path)

      output, status = run_validator(fixture)

      refute status.success?, output
      assert_includes output, "reviewed Process site contains unapproved executable assignments"
    end
  end

  def test_validator_runs_under_the_posix_locale
    output, status = run_validator(ROOT, { "LANG" => "C", "LC_ALL" => "C" })

    assert status.success?, output
  end

  def test_ci_runs_remove_on_stop_contract_and_validator
    workflow = read_utf8(ROOT.join(".github", "workflows", "test.yml"))

    assert_includes workflow, "ruby scripts/test-remove-on-stop.rb"
    assert_includes workflow, "env LANG=C LC_ALL=C ruby scripts/test-remove-on-stop.rb"
    assert_includes workflow, "ruby scripts/validate-no-shell-hook.rb"
  end

  private

  def run_validator(root, environment = {})
    stdout, stderr, status = Open3.capture3(
      environment,
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
    path
  end

  def assert_swift_parses(path)
    stdout, stderr, status = Open3.capture3(
      "swiftc",
      "-frontend",
      "-parse",
      path.to_s
    )
    assert status.success?, "invalid Swift fixture #{path}:\n#{stdout}#{stderr}"
  end

  def read_utf8(path)
    source = path.binread.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "#{path}: source is not valid UTF-8" unless source.valid_encoding?

    source
  end
end
