# frozen_string_literal: true

# Tasks that clean the runtime cache.
#
# `tmp/cache` gets a runtime object, a prelinked image, an eval support
# object and a symbol table for each digest that this checkout builds.
# The digest changes when any file under `lib` or `runtime` changes, so
# old entries collect (9.5 GB after one week of work).
#
# It also gets one `unit-<key>.marshal` for each file that a program
# is built from (lib/zr/unit_cache.rb). Each is small, but a tier run
# makes thousands. Each name contains the digest of the compiler that
# made it, so a prune removes them with that compiler's other files.
#
#   rake cache:size                what is there, by kind
#   rake cache:prune               all except the files this checkout uses
#   rake 'cache:prune[3]'          ... and keep files touched in 3 days
#   rake cache:clear               all files, also this checkout's files
#
# A prune keeps the files this checkout uses, whatever their age. Thus
# the next build does not rebuild the runtime, eval support or the
# images. `clear` removes those too; use it when the disk is full.
# All other files are content-addressed and are made again on demand.
# A wasm prelude and a gem prelude have names that come from more than
# the runtime digest (the program's pending symbols, the files the
# prelude loaded). Thus a prune keeps them by age only, and a prune
# with 0 days makes the next wasm build rebuild its prelude.
require_relative "../lib/zr/runtime"
require_relative "../lib/zr/native/build"

module Caches
  module_function

  # The cache files, the binaries that the spec tier keeps in the cache,
  # and the parsed trees (lib/zr/parse_cache.rb). There is one parsed
  # tree for each file ever parsed (about 70,000 after some months).
  # Their names come from the source only, so only age shows which are
  # not used.
  def files = Dir[File.join(Zr.cache, "{*,binaries/*,parse/*}")].select { |path| File.file?(path) }

  # wasmtime's cache of compiled modules. `rake bench` and `zr run`
  # under Cranelift fill it (the tiers run Winch with the cache off).
  # These tasks do not clean it, but `cache:size` reports it, because it
  # can become large (67 GB on one machine). `wasmtime config new` writes
  # the file that sets its limit.
  def wasmtime_cache = File.expand_path("~/Library/Caches/BytecodeAlliance.wasmtime")

  # The files that this checkout's compiler uses, for each target: the
  # runtime object, the eval support object and its meta file, and the
  # prelinked image of each. Only the meta file gives the key of the
  # eval support object.
  def live
    Zr::Target.all.flat_map { |target| live_for(target) }.compact.uniq
  rescue StandardError
    [] # if the compiler does not load, keep no file as live
  end

  def live_for(target)
    runtime = Zr.runtime(target)
    object = runtime.object_path
    metas = %w[jit walk].map { |kind| Zr::EvalSupport.meta_path(runtime, kind) }.select { |path| File.exist?(path) }
    evals = metas.filter_map { |meta| eval_object(meta) }
    sets = [[object], *evals.map { |eval| [object, eval] }]
    [object, *metas, *evals, *sets.map { |set| prelink(set) }, *sets.map { |set| Zr::Native::Build.skeleton_path(set) }] +
      Dir[File.join(Zr.cache, "*-#{runtime.digest}.*")]
  end

  # The eval support object. Only its meta file gives its path.
  def eval_object(meta)
    key = JSON.parse(File.read(meta)).fetch("key") if File.exist?(meta)
    key && Zr::EvalSupport.object_path(key)
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
