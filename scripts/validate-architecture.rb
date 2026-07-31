#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

ROOT = Pathname(__dir__).parent
ARCH = ROOT.join("docs", "architecture")

required = [
  ARCH.join("quill-v2-architecture.md"),
  ARCH.join("governing-rules.md"),
  ARCH.join("phase-0-baseline.md"),
  *Dir[ARCH.join("adr", "000[1-4]-*.md").to_s].map { |path| Pathname(path) },
  *Dir[ARCH.join("schemas", "*.schema.json").to_s].map { |path| Pathname(path) }
]

missing = required.reject(&:file?)
abort "Missing architecture files:\n#{missing.map { |path| "- #{path}" }.join("\n")}" unless missing.empty?

schema_files = Dir[ARCH.join("schemas", "*.schema.json").to_s]
schema_files.each do |path|
  schema = JSON.parse(File.read(path))
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
  File.read(path).scan(/\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)/).flatten.each do |target|
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
  File.read(path).match?(pr_reference)
end
unless references.empty?
  abort "Speculative PR references found in:\n#{references.map { |path| "- #{path}" }.join("\n")}"
end

puts "Architecture validation passed"
puts "- #{schema_files.length} schemas parsed"
puts "- local schema references resolved"
puts "- local Markdown links resolved"
puts "- no speculative PR references"
