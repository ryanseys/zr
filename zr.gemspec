# frozen_string_literal: true

require_relative "lib/zr/version"
require_relative "lib/zr/libraries"

Gem::Specification.new do |spec|
  spec.name = "zr"
  spec.version = Zr::VERSION
  spec.authors = ["Ryan Seys"]
  spec.email = ["ryan@ryanseys.com"]

  spec.summary = "A Ruby compiler, written in Ruby: its programs give ruby 4.0.7's output, or zr refuses them by name"
  spec.description = <<~TEXT
    zr compiles Ruby programs to native aarch64-apple-darwin binaries on an
    Apple Silicon Mac, and to WASI modules on any host. The compiler and the
    runtime are Ruby. The Ruby library a program requires is the gems
    this one depends on, which zr compiles into the program.
  TEXT
  spec.homepage = "https://github.com/ryanseys/zr"
  spec.license = "MIT" # the vendored parts: THIRD_PARTY_NOTICES.md
  # Exactly the ruby that zr checks its output against (.ruby-version).
  # Another ruby has another standard library, which zr is not tested with.
  spec.required_ruby_version = "= #{Zr::RUBY}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "#{spec.homepage}/tree/main/docs",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  # The compiler, its runtime and the vendored sources. The tests and
  # the tasks stay in the repository.
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL, &:read).split("\x0").select do |file|
    file.match?(%r{\A(exe|lib|licenses|runtime|vendor/(ext|lib|prelude))/}) ||
      %w[LICENSE.txt THIRD_PARTY_NOTICES.md README.md CHANGELOG.md].include?(file)
  end
  spec.bindir = "exe"
  spec.executables = ["zr"]
  # Only lib/: runtime/ and vendor/ hold files named like ruby's own libraries
  # (rbconfig, set, json), and must never shadow them.
  spec.require_paths = ["lib"]

  # The libraries a program's `require` reads, which zr compiles into
  # it and never loads itself (lib/zr/libraries.rb). Pinned exactly: a
  # program answers what ruby answers with these versions, and a digest
  # of each holds zr to the files it was checked against.
  Zr::Libraries::PINS.each { |name, version| spec.add_dependency name, "= #{version}" }
end
