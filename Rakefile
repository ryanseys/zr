# frozen_string_literal: true

require "bundler/gem_tasks"

# Every task is a thin call to bin/ze0, which runs the corpus and the
# checks the same way whether rake or a person starts it.
ZE0 = File.expand_path("bin/ze0", __dir__)

def ze0(*args)
  sh(Gem.ruby, ZE0, *args)
end

desc "Run the repo's own checks: rake check or rake 'check[exe zr]'"
task :check, [:filters] do |_, args|
  ze0("check", *args[:filters].to_s.split)
end

desc "Run corpus programs against ruby's recordings: rake 'corpus[ze0::]'"
task :corpus, [:filters] do |_, args|
  filters = args[:filters].to_s.split
  ze0("test", *(filters.empty? ? ["--all"] : filters))
end

desc "ze0 compiles itself twice, to the same bytes"
task :stage1 do
  ze0("stage1")
end

desc "The compiler compiled by itself is a fixed point"
task :stage2 do
  ze0("stage2")
end

# The OS tables come from the ruby of the OS they describe
# (tools/layer.rb), so this runs on each OS's own ruby: darwin here, an
# Alpine ruby for linux. socket's table follows ruby's own list of names,
# which lives in ruby's source rather than in any install.
desc "Write this OS's tables again and fail on a difference: MKCONSTANTS=<ruby>/ext/socket/mkconstants.rb rake tables"
task :tables do
  mkconstants = ENV.fetch("MKCONSTANTS") { abort "rake tables: MKCONSTANTS names ruby 4.0.6's ext/socket/mkconstants.rb" }
  %w[errno fcntl etc].each { |tool| sh(Gem.ruby, "tools/#{tool}.rb") }
  sh(Gem.ruby, "tools/socket.rb", mkconstants)
  os = RUBY_PLATFORM[/darwin|linux|wasi/]
  sh("git", "diff", "--exit-code", "--", "rt/core/os/#{os}", "rt/ext/os/#{os}")
end

task default: :check
