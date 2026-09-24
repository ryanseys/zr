# frozen_string_literal: true

# The runtime caches, swept.
#
# `tmp/rt` gains a runtime object, a prelinked image, an eval road and a
# symbol table for every digest this checkout has ever built, and a
# digest moves whenever anything under `lib` or `rt` does. Nothing
# removed the old ones, so a week of work left 9.5 GB of caches for
# compilers that no longer exist.
#
# It also gains one `unit-<key>.marshal` per file any program was built
# from (lib/zr/unit_cache.rb): small each, thousands after a tier run,
# and every one of them named after the compiler that made it, so a
# prune takes them with everything else that compiler left.
#
#   rake cache:size                what is there, by kind
#   rake cache:prune               all but what this checkout names
#   rake 'cache:prune[3]'          ... keeping anything touched in 3 days
#   rake cache:clear               all of it, this checkout's included
#
# What this checkout names is kept whatever its age, so a prune never
# costs the next build the runtime, the road or either image. `clear`
# takes those too, which is what a disk with no room left wants, and
# what to reach for when the next build is a cold one anyway. Everything
# else is content-addressed and comes back on demand, which is what the
# day's grace is for: a wasm prelude and a gem prelude are named after
# more than the runtime's digest -- the program's own pending symbols,
# the files the prelude loaded -- so those two kinds are kept by age
# alone, and a hard prune costs the next wasm build its prelude.
require_relative "../lib/zr/zr"
require_relative "../lib/zr/native/build"

module Caches
  module_function

  # The cache's files, the binaries the spec tier keeps under it, and
  # the parsed trees (lib/zr/parse_cache.rb): one a file ever parsed,
  # seventy thousand after a season, and named by their source alone,
  # so only age says which are done with.
  def files = Dir[File.join(Zr::Zr.cache, "{*,binaries/*,parse/*}")].select { |path| File.file?(path) }

  # wasmtime's own cache of compiled modules, which `rake bench` and a
  # `zr run` under Cranelift fill (the tiers run Winch with the cache
  # off): not this cache's to sweep, but worth naming, since it grew to
  # 67 GB on one machine. `wasmtime config new` writes the file that
  # bounds it.
  def wasmtime_cache = File.expand_path("~/Library/Caches/BytecodeAlliance.wasmtime")

  # The names this checkout's compiler asks for, over every target it
  # builds: the runtime object, the eval road and its meta, and the
  # prelinked image of each -- the road's own key comes out of its meta,
  # which is the one file that says it.
  def live
    Zr::Target.all.flat_map { |target| live_for(target) }.compact.uniq
  rescue StandardError
    [] # a checkout the compiler will not load from is not one to sweep by
  end

  def live_for(target)
    runtime = Zr::Zr.runtime(target)
    object = File.join(Zr::Zr.cache, "rt-#{runtime.digest}.o")
    meta = File.join(Zr::Zr.cache, "road-#{runtime.digest}.json")
    road = road_object(meta)
    images = [prelink([object]), road && prelink([object, road])].compact
    [object, meta, road, *images, *images.map { |image| image.sub("prelink-", "skeleton-") }] +
      Dir[File.join(Zr::Zr.cache, "*-#{runtime.digest}.*")]
  end

  # The road's object, which only its meta names.
  def road_object(meta)
    key = JSON.parse(File.read(meta)).fetch("key") if File.exist?(meta)
    key && File.join(Zr::Zr.cache, "road-#{key}.o")
  end

  # The image `Native::Build.prelink` writes for those objects.
  def prelink(objects) = Zr::Native::Build.prelink_path(objects)

  def megabytes(paths) = paths.sum { |path| File.size(path) } / (1 << 20)

  def kind(path)
    return "binary" if File.basename(File.dirname(path)) == "binaries"
    return "parse" if File.basename(File.dirname(path)) == "parse"

    File.basename(path).sub(/-[0-9a-f]{64}/, "").sub(/\A[^.]*\./, "")
  end
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
    if Dir.exist?(Caches.wasmtime_cache)
      held = Dir[File.join(Caches.wasmtime_cache, "**/*")].select { |path| File.file?(path) }
      puts format("%6d MB  %4d  wasmtime's own cache at %s; rm -r it, or bound it with `wasmtime config new`",
                  Caches.megabytes(held), held.size, Caches.wasmtime_cache)
    end
  end

  desc "Which files this checkout names, and whether they are built"
  task :live do
    Caches.live.each { |path| puts format("%-5s %s", File.exist?(path) ? "have" : "want", File.basename(path)) }
  end

  desc "Empty the runtime cache, whatever this checkout names"
  task :clear do
    files = Caches.files
    freed = Caches.megabytes(files)
    files.each { |path| File.delete(path) }
    puts format("cleared %d file(s), %d MB", files.size, freed)
  end

  desc "Sweep the runtime cache: rake 'cache:prune[days]'"
  task :prune, [:days] do |_, args|
    days = Float(args[:days] || ENV.fetch("ZR_CACHE_DAYS", 1))
    live = Caches.live
    young = Time.now - (days * 86_400)
    stale = Caches.files.reject { |path| live.include?(path) || File.mtime(path) > young }
    freed = Caches.megabytes(stale)
    stale.each { |path| File.delete(path) }
    puts format("swept %d file(s), %d MB; %d MB left", stale.size, freed, Caches.megabytes(Caches.files))
  end
end
