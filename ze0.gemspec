# frozen_string_literal: true

require_relative "lib/ze0/version"
require_relative "lib/ze0/libraries"

Gem::Specification.new do |spec|
  spec.name = "ze0"
  spec.version = Ze0::VERSION
  spec.authors = ["Ryan Seys"]
  spec.email = ["ryan@ryanseys.com"]

  spec.summary = "A Ruby compiler, written in Ruby, that answers what ruby 4.0.6 answers or refuses by name"
  spec.description = <<~TEXT
    ze0 compiles Ruby programs to native aarch64-apple-darwin binaries on an
    Apple Silicon Mac, and to WASI modules on any host. The compiler and the
    runtime are Ruby. The Ruby library a program requires is the gems
    this one depends on, which ze0 compiles into the program.
  TEXT
  spec.homepage = "https://github.com/ryanseys/ze0"
  spec.license = "MIT" # the vendored parts: THIRD_PARTY_NOTICES.md
  spec.required_ruby_version = "= #{Ze0::RUBY}"

  spec.metadata = {
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  # The compiler, its runtime and the vendored sources. The tests and
  # the tasks stay in the repository.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").select do |file|
      file.match?(%r{\A(exe|lib|rt|vendor/(ext|lib|prelude))/}) ||
        %w[LICENSE.txt THIRD_PARTY_NOTICES.md README.md CHANGELOG.md].include?(file)
    end
  end
  spec.bindir = "exe"
  spec.executables = ["ze0"]
  # Only lib/: rt/ and vendor/ hold files named like ruby's own libraries
  # (rbconfig, set, json), and must never shadow them.
  spec.require_paths = ["lib"]

  # The libraries a program's `require` reads, which ze0 compiles into
  # it and never loads itself (lib/ze0/libraries.rb). Pinned exactly: a
  # program answers what ruby answers with these versions, and a digest
  # of each holds ze0 to the files it was checked against.
  Ze0::Libraries::PINS.each { |name, version| spec.add_dependency name, "= #{version}" }
end
