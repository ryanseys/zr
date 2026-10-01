# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"
require_relative "config"

module Zr
  # The digests that name the cache's entries and that do not belong to
  # one target's sources (`RuntimeSources` has those).
  module Digests
    module_function

    # One digest of the LINK_ONLY files. A cache that the link writes
    # includes this digest in its name, with its other inputs.
    def link
      require_relative "runtime_sources"
      Session.current.memo(:link_digest) do
        Digest::SHA256.new.tap { |d| RuntimeSources::LINK_ONLY.each { |path| d << path << "\0" << File.binread(path) } }.hexdigest
      end
    end

    # The digest that names a runtime's cache files: the target, the path
    # root, and each of `files` with its bytes (`bytes` has the ones that a
    # build already read, so it hashes what it lowered).
    def sources(target, files, bytes = {})
      Digest::SHA256.new.tap do |d|
        d << target.triple << "\0"
        d << "root\0" << Paths.root << "\0" if Paths.root
        d << "checked\0" if Config.current.kernel_checked?
        files.each { |path| d << path << "\0" << (bytes[path] || File.binread(path)) }
      end.hexdigest
    end

    # The key of what eval support reads: the eval digest and the bytes of
    # each file (`EvalSupport#files_key`). `bytes` has the ones that a build
    # already read. `absent` lists the paths that must still not exist.
    def eval_files_key(eval_digest, files, bytes = {}, absent = [])
      Digest::SHA256.new.tap do |d|
        d << eval_digest
        files.each do |path|
          d << path << "\0" << (bytes[path] || (File.exist?(path) ? File.binread(path) : ""))
        end
        # The paths where a feature that the lowering stopped on would be:
        # each one that exists now changes the key. `absent` names the form
        # of the key, so a key from before the paths counted is stale.
        d << "\0absent"
        absent.each { |path| d << "\0" << path if File.exist?(path) }
      end.hexdigest
    end

    # The key of an eval support object and of its symbol table: the key of
    # its files, and the names and site count that numbered its data. Two
    # tables number the same data to other words, so they must never share
    # a key.
    def eval_key(files_key, names, sites)
      Digest::SHA256.new.tap do |d|
        d << files_key << "\0" << sites.to_s
        # Each name with its length, so no name can look like two; a pad
        # (nil) has no length.
        names.each { |name| d << (name.nil? ? "\0-" : "\0#{name.bytesize}:#{name}") }
      end.hexdigest
    end
  end
end
