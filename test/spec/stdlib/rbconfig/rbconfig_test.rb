# frozen_string_literal: true

require "spec_helper"

describe "Rbconfig programs" do
  it "rbconfig shim is built in" do
    result = ze0(<<~'RUBY')
      # `host_os`/`arch` are the BUILD host's, so pinning them pinned this
      # test to one machine: it read `darwin25`/`arm64-darwin25`, which is
      # wrong on Linux and goes stale on the next macOS release. What the
      # shim actually owes is CRuby's own agreement rule: `arch` is
      # `<cpu>-<host_os>` with any `-gnu` suffix DROPPED -- a glibc ruby
      # reports `host_os` `linux-gnu` beside `arch` `aarch64-linux` -- and
      # both name the platform this test is running on.

      require "rbconfig"
      puts RbConfig::CONFIG["ruby_version"]
      puts RbConfig::CONFIG.fetch("host_os").sub(/\d+\z/, "N")
      puts RbConfig::CONFIG["EXEEXT"].inspect
      puts RbConfig::CONFIG["arch"].sub(/\d+\z/, "N")
      puts defined?(RbConfig::CONFIG)
    RUBY

    _(result).must_answer <<~'OUT'
      4.0.0
      darwinN
      ""
      arm64-darwinN
      constant
    OUT
  end

  it "require of rbconfig answers like rubys preloaded one" do
    result = ze0(<<~'RUBY')
      p(require("rbconfig"))
      f = "rbconfig"
      p(require(f))
      p RbConfig::CONFIG.key?("host_os")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
    OUT
  end
end
