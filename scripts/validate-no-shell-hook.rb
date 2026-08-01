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

unless SOURCE_ROOT.directory?
  warn "missing product source directory: #{SOURCE_ROOT}"
  exit 1
end

failures = []
sources = Dir[SOURCE_ROOT.join("**", "*.swift").to_s].sort.map do |path|
  relative = Pathname(path).relative_path_from(ROOT).to_s
  [relative, Pathname(path).read]
end

sources.each do |relative, source|
  INTERPRETER_PATTERNS.each do |description, pattern|
    failures << "#{relative}: #{description}" if source.match?(pattern)
  end
  RETIRED_HOOK_PATTERNS.each do |description, pattern|
    failures << "#{relative}: #{description}" if source.match?(pattern)
  end

  next unless source.include?("Process()")

  allowed_executable = ALLOWED_PROCESS_SITES[relative]
  if allowed_executable.nil?
    failures << "#{relative}: unreviewed Process site"
  elsif !source.include?(%("#{allowed_executable}"))
    failures << "#{relative}: reviewed Process site no longer launches #{allowed_executable}"
  end
end

ALLOWED_PROCESS_SITES.each do |relative, executable|
  source = sources.assoc(relative)&.last
  if source.nil?
    failures << "#{relative}: reviewed Process site is missing"
  elsif !source.include?("Process()") || !source.include?(%("#{executable}"))
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
