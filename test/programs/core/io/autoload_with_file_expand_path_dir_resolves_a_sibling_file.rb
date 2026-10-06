# The dominant stdlib/bundler idiom: `autoload :C, File.expand_path("c",
# __dir__)` -- a computed sibling path. Resolved at compile time from the
# requiring file's directory.

require_relative "autoload_sibling/main"
