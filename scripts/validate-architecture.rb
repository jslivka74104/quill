#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

ROOT = Pathname(__dir__).parent
ARCH = ROOT.join("docs", "architecture")

def read_utf8(path)
  source = Pathname(path).binread.force_encoding(Encoding::UTF_8)
  raise ArgumentError, "#{path}: source is not valid UTF-8" unless source.valid_encoding?

  source
end

required_adrs = [
  "0001-single-application-process.md",
  "0002-folder-authority-and-sqlite-index.md",
  "0003-versioned-transcripts-and-scoped-identity.md",
  "0004-verified-model-provisioning.md"
].map { |name| ARCH.join("adr", name) }

required_schemas = [
  "annotations-v1.schema.json",
  "part-v1.schema.json",
  "session-v2.schema.json",
  "state-v1.schema.json",
  "transcript-v2.schema.json"
].map { |name| ARCH.join("schemas", name) }

required = [
  ARCH.join("quill-v2-architecture.md"),
  ARCH.join("governing-rules.md"),
  ARCH.join("phase-0-baseline.md"),
  *required_adrs,
  *required_schemas
]

missing = required.reject(&:file?)
abort "Missing architecture files:\n#{missing.map { |path| "- #{path}" }.join("\n")}" unless missing.empty?

actual_adrs = Dir[ARCH.join("adr", "*.md").to_s].map { |path| Pathname(path) }
actual_schemas = Dir[ARCH.join("schemas", "*.schema.json").to_s].map { |path| Pathname(path) }

unexpected_adrs = actual_adrs - required_adrs
unexpected_schemas = actual_schemas - required_schemas
unless unexpected_adrs.empty? && unexpected_schemas.empty?
  unexpected = unexpected_adrs + unexpected_schemas
  abort "Unexpected architecture package files:\n#{unexpected.map { |path| "- #{path}" }.join("\n")}"
end

schema_files = required_schemas.map(&:to_s)
schema_files.each do |path|
  schema = JSON.parse(read_utf8(path))
  refs = []

  walk = lambda do |value|
    case value
    when Hash
      refs << value["$ref"] if value.key?("$ref")
      value.each_value { |child| walk.call(child) }
    when Array
      value.each { |child| walk.call(child) }
    end
  end

  walk.call(schema)
  refs.each do |ref|
    ref_path = ref.split("#", 2).first
    next if ref_path.empty?

    target = Pathname(File.expand_path(ref_path, File.dirname(path)))
    abort "Missing schema ref: #{path} -> #{ref}" unless target.file?
  end
end

markdown_errors = []
Dir[ARCH.join("**", "*.md").to_s].each do |path|
  read_utf8(path).scan(/\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)/).flatten.each do |target|
    next if target.match?(%r{\A(?:https?|mailto):})

    resolved = Pathname(path).dirname.join(target).cleanpath
    markdown_errors << "#{path} -> #{target}" unless resolved.file?
  end
end
unless markdown_errors.empty?
  abort "Missing Markdown links:\n#{markdown_errors.map { |error| "- #{error}" }.join("\n")}"
end

pr_reference = /PR #[0-9]+|pull request #[0-9]+/
references = Dir[ARCH.join("**", "*.md").to_s].select do |path|
  read_utf8(path).match?(pr_reference)
end
unless references.empty?
  abort "Speculative PR references found in:\n#{references.map { |path| "- #{path}" }.join("\n")}"
end

puts "Architecture validation passed"
puts "- #{schema_files.length} schemas parsed"
puts "- local schema references resolved"
puts "- local Markdown links resolved"
puts "- no speculative PR references"
