# `host_os`/`arch` are the BUILD host's, so pinning them pinned this
# test to one machine: it read `darwin25`/`arm64-darwin25`, which is
# wrong on Linux and goes stale on the next macOS release. What the
# shim actually owes is CRuby's own agreement rule: `arch` is
# `<cpu>-<host_os>` with any `-gnu` suffix DROPPED -- a glibc ruby
# reports `host_os` `linux-gnu` beside `arch` `aarch64-linux` -- and
# both name the platform this test is running on.

require "rbconfig"
config = RbConfig::CONFIG
# The library directories carry the API version, and a development build's
# ABI version after a "+".
puts config["ruby_version"].match?(/\A#{Regexp.escape(config["RUBY_API_VERSION"])}\.\d+(\+\d+)?\z/)
puts config["arch"] == "#{config.fetch("host_cpu")}-#{config.fetch("host_os").delete_suffix("-gnu")}"
puts config["arch"] == RUBY_PLATFORM
puts config["EXEEXT"].inspect
puts defined?(RbConfig::CONFIG)
