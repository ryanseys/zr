# frozen_string_literal: true

# The runtime caches, swept.
#
# `tmp/rt` gains a runtime object, a prelinked image, an eval road and a
# symbol table for every digest this checkout has ever built, and a
# digest moves whenever anything under `lib` or `rt` does. Nothing
# removed the old ones, so a week of work left 9.5 GB of caches for
# compilers that no longer exist.
#
#   rake cache:size                what is there, by kind
#   rake cache:prune               all but what this checkout names
#   rake 'cache:prune[3]'          ... keeping anything touched in 3 days
#
# What this checkout names is kept whatever its age, so a prune never
# costs the next build the runtime, the road or either image. Everything
# else is content-addressed and comes back on demand, which is what the
# day's grace is for: a wasm prelude and a gem prelude are named after
# more than the runtime's digest -- the program's own pending symbols,
# the files the prelude loaded -- so those two kinds are kept by age
# alone, and a hard prune costs the next wasm build its prelude.
require_relative "../lib/ze0/zr"
require_relative "../lib/ze0/native/build"

module Caches
  module_function

  def files = Dir[File.join(Ze0::Zr.cache, "*")].select { |path| File.file?(path) }

  # The names this checkout's compiler asks for, over every target it
  # builds: the runtime object, the eval road and its meta, and the
  # prelinked image of each -- the road's own key comes out of its meta,
  # which is the one file that says it.
  def live
    Ze0::Target.all.flat_map { |target| live_for(target) }.compact.uniq
  rescue StandardError
    [] # a checkout the compiler will not load from is not one to sweep by
  end

  def live_for(target)
    runtime = Ze0::Zr.runtime(target)
    object = File.join(Ze0::Zr.cache, "rt-#{runtime.digest}.o")
    meta = File.join(Ze0::Zr.cache, "road-#{runtime.digest}.json")
    road = road_object(meta)
    [object, meta, road, prelink([object]), road && prelink([object, road])] +
      Dir[File.join(Ze0::Zr.cache, "*-#{runtime.digest}.*")]
  end

  # The road's object, which only its meta names.
  def road_object(meta)
    key = JSON.parse(File.read(meta)).fetch("key") if File.exist?(meta)
    key && File.join(Ze0::Zr.cache, "road-#{key}.o")
  end

  # The image `Native::Build.prelink` writes for those objects.
  def prelink(objects)
    key = Digest::SHA256.hexdigest([*objects.map { |o| File.basename(o) }, Ze0::Zr.link_digest].join("\n"))
    File.join(Ze0::Zr.cache, "prelink-#{key}.bin")
  end

  def megabytes(paths) = paths.sum { |path| File.size(path) } / (1 << 20)

  def kind(path) = File.basename(path).sub(/-[0-9a-f]{64}/, "").sub(/\A[^.]*\./, "")
end

namespace :cache do
  desc "What the runtime cache holds, by kind"
  task :size do
    files = Caches.files
    files.group_by { |path| Caches.kind(path) }.sort_by { |_, group| -Caches.megabytes(group) }.each do |kind, group|
      puts format("%6d MB  %4d  %s", Caches.megabytes(group), group.size, kind)
    end
    puts format("%6d MB  %4d  in all, of which %d MB is named by this checkout",
                Caches.megabytes(files), files.size, Caches.megabytes(Caches.live & files))
  end

  desc "Which files this checkout names, and whether they are built"
  task :live do
    Caches.live.each { |path| puts format("%-5s %s", File.exist?(path) ? "have" : "want", File.basename(path)) }
  end

  desc "Sweep the runtime cache: rake 'cache:prune[days]'"
  task :prune, [:days] do |_, args|
    days = Float(args[:days] || ENV.fetch("ZE0_CACHE_DAYS", 1))
    live = Caches.live
    young = Time.now - (days * 86_400)
    stale = Caches.files.reject { |path| live.include?(path) || File.mtime(path) > young }
    freed = Caches.megabytes(stale)
    stale.each { |path| File.delete(path) }
    puts format("swept %d file(s), %d MB; %d MB left", stale.size, freed, Caches.megabytes(Caches.files))
  end
end
