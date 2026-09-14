# frozen_string_literal: true

require "bundler/gem_tasks"

# Every task is a thin call to bin/ze0, which runs the corpus and the
# checks the same way whether rake or a person starts it.
ZE0 = File.expand_path("bin/ze0", __dir__)

def ze0(*args)
  sh(Gem.ruby, ZE0, *args)
end

desc "Build the vendored C archives (prism, oniguruma, zlib)"
task :compile do
  ze0("deps", "build")
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

task default: :check
