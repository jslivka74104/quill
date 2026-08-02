#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname(ARGV.fetch(0, Pathname(__dir__).parent.to_s)).expand_path
SOURCE_ROOT = ROOT.join("Sources", "quill")

ALLOWED_PROCESS_SITES = {
  "Sources/quill/Install.swift" => "/bin/launchctl",
  "Sources/quill/Notify.swift" => "/usr/bin/osascript"
}.freeze

INTERPRETER_PATTERNS = {
  "direct command interpreter" => %r{/(?:usr/)?bin/(?:ba|z|fi|da|k)?sh\b},
  "environment-selected command interpreter" => %r{/usr/bin/env[\s\S]{0,240}?(?:\"|')?(?:ba|z|fi|da|k)?sh\b}
}.freeze

RETIRED_HOOK_PATTERNS = {
  "retired onStop identifier" => /\bonStop\b/,
  "retired runHook identifier" => /\brunHook\b/
}.freeze

PROCESS_REFERENCE_PATTERN = /\b(?:Foundation\s*\.\s*)?Process\b/
PROCESS_CONSTRUCTOR_PATTERN = /\b(?:Foundation\s*\.\s*)?Process\s*\(/
OTHER_LAUNCH_PRIMITIVE_PATTERNS = {
  "NSTask" => /\bNSTask\s*\(/,
  "posix_spawn" => /\bposix_spawnp?\s*\(/,
  "system" => /\bsystem\s*\(/,
  "popen" => /\bpopen\s*\(/,
  "exec" => /\bexec(?:v|ve|vp|vP|l|le|lp)\s*\(/,
  "dynamic loader" => /\bdl(?:open|sym)\s*\(/
}.freeze
EXECUTABLE_ASSIGNMENT_PATTERN = /\.(?:launchPath|executableURL)\s*=/

def read_utf8(path)
  source = Pathname(path).binread.force_encoding(Encoding::UTF_8)
  raise ArgumentError, "#{path}: source is not valid UTF-8" unless source.valid_encoding?

  source
end

def literal_process_executables(source)
  launch_paths = source
    .scan(/\.launchPath\s*=\s*"([^"]+)"\s*(?=;|\n|\z)/)
    .flatten
  executable_urls = source.scan(
    /\.executableURL\s*=\s*URL\s*\(\s*fileURLWithPath:\s*"([^"]+)"\s*\)\s*(?=;|\n|\z)/
  ).flatten
  launch_paths + executable_urls
end

unless SOURCE_ROOT.directory?
  warn "missing product source directory: #{SOURCE_ROOT}"
  exit 1
end

failures = []
sources = Dir[SOURCE_ROOT.join("**", "*.swift").to_s].sort.map do |path|
  relative = Pathname(path).relative_path_from(ROOT).to_s
  [relative, read_utf8(path)]
end

sources.each do |relative, source|
  INTERPRETER_PATTERNS.each do |description, pattern|
    failures << "#{relative}: #{description}" if source.match?(pattern)
  end
  RETIRED_HOOK_PATTERNS.each do |description, pattern|
    failures << "#{relative}: #{description}" if source.match?(pattern)
  end

  allowed_executable = ALLOWED_PROCESS_SITES[relative]
  process_references = source.scan(PROCESS_REFERENCE_PATTERN).count
  process_count = source.scan(PROCESS_CONSTRUCTOR_PATTERN).count
  other_primitives = OTHER_LAUNCH_PRIMITIVE_PATTERNS.each_with_object([]) do |(name, pattern), matches|
    matches << name if source.match?(pattern)
  end

  if allowed_executable
    unless other_primitives.empty?
      failures << "#{relative}: reviewed Process site contains unapproved launch primitives"
    end

    assignment_count = source.scan(EXECUTABLE_ASSIGNMENT_PATTERN).count
    executables = literal_process_executables(source)
    unless process_count == 1 &&
           process_references == process_count &&
           assignment_count == 1 &&
           executables == [allowed_executable]
      failures << "#{relative}: reviewed Process site contains unapproved executable assignments"
    end
  elsif process_references.positive? || !other_primitives.empty?
    failures << "#{relative}: unreviewed process launch primitive"
  end
end

ALLOWED_PROCESS_SITES.each do |relative, executable|
  source = sources.assoc(relative)&.last
  if source.nil?
    failures << "#{relative}: reviewed Process site is missing"
  elsif source.scan(PROCESS_CONSTRUCTOR_PATTERN).count != 1 ||
        literal_process_executables(source) != [executable]
    failures << "#{relative}: reviewed Process site does not match its allowlist"
  end
end

if failures.empty?
  puts "No retired on_stop consumer or command-interpreter launch path found"
  puts "Reviewed Process sites: #{ALLOWED_PROCESS_SITES.keys.sort.join(', ')}"
  exit 0
end

warn "Shell-hook validation failed:"
failures.uniq.sort.each { |failure| warn "- #{failure}" }
exit 1
