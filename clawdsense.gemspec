# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "clawdsense"
  spec.version = "0.1.0"
  spec.authors = ["Jeremy Smith"]
  spec.summary = "Search across all your Claude Code sessions locally"
  spec.description = "CLI tool that indexes Claude Code session transcripts into Typesense for fast keyword and semantic search."
  spec.homepage = "https://github.com/jeremysmithco/clawdsense"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "bin/*"]
  spec.bindir = "bin"
  spec.executables = ["clawdsense"]

  spec.add_dependency "typesense", ">= 5.0.0"
end
