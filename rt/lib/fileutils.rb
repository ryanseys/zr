# frozen_string_literal: true

# The file commands, over File and Dir. Every one takes the `noop`,
# `verbose` and `force` options ruby's own takes, and answers what
# ruby's answers.
module FileUtils
  VERSION = "1.8.0"

  extend self

  def pwd = Dir.pwd

  alias getwd pwd

  def cd(dir, verbose: nil, &block)
    report("cd #{dir}", verbose)
    Dir.chdir(dir, &block)
  end

  alias chdir cd

  def mkdir(list, mode: nil, noop: nil, verbose: nil)
    list = paths(list)
    report("mkdir #{list.join(" ")}", verbose)
    return if noop

    list.each { |path| mode ? Dir.mkdir(path, mode) : Dir.mkdir(path) }
    nil
  end

  def mkdir_p(list, mode: nil, noop: nil, verbose: nil)
    list = paths(list)
    report("mkdir -p #{list.join(" ")}", verbose)
    return list if noop

    list.each { |path| make_parents(path.chomp("/"), mode) }
    list
  end

  alias mkpath mkdir_p
  alias makedirs mkdir_p

  def rmdir(list, parents: nil, noop: nil, verbose: nil)
    list = paths(list)
    report("rmdir #{list.join(" ")}", verbose)
    return if noop

    list.each do |path|
      Dir.rmdir(path)
      next unless parents

      up = File.dirname(path)
      while up != path
        begin
          Dir.rmdir(up)
        rescue SystemCallError
          break
        end
        path, up = up, File.dirname(up)
      end
    end
    nil
  end

  def rm(list, force: nil, noop: nil, verbose: nil)
    list = paths(list)
    report("rm#{force ? " -f" : ""} #{list.join(" ")}", verbose)
    return if noop

    list.each do |path|
      File.unlink(path)
    rescue StandardError
      raise unless force
    end
    nil
  end

  alias remove rm

  def rm_f(list, noop: nil, verbose: nil) = rm(list, force: true, noop: noop, verbose: verbose)

  alias safe_unlink rm_f

  def rm_r(list, force: nil, noop: nil, verbose: nil, secure: nil)
    list = paths(list)
    report("rm -r#{force ? "f" : ""} #{list.join(" ")}", verbose)
    return if noop

    list.each do |path|
      remove_entry(path, force)
    rescue StandardError
      raise unless force
    end
    nil
  end

  def rm_rf(list, noop: nil, verbose: nil, secure: nil)
    rm_r(list, force: true, noop: noop, verbose: verbose, secure: secure)
  end

  alias rmtree rm_rf

  # One path and everything under it. A missing path is an error unless
  # `force` says otherwise.
  def remove_entry(path, force = false)
    path = path.to_s
    if File.directory?(path) && !File.symlink?(path)
      Dir.children(path).each { |name| remove_entry(File.join(path, name), force) }
      Dir.rmdir(path)
    else
      File.unlink(path)
    end
    nil
  rescue StandardError
    raise unless force
  end

  def remove_entry_secure(path, force = false) = remove_entry(path, force)

  def remove_file(path, force = false)
    File.unlink(path)
    nil
  rescue StandardError
    raise unless force
  end

  def remove_dir(path, force = false) = remove_entry(path, force)

  def cp(src, dest, preserve: nil, noop: nil, verbose: nil)
    report("cp #{[*src, dest].join(" ")}", verbose)
    return if noop

    each_source(src, dest) { |from, to| copy_file(from, to, preserve) }
    nil
  end

  alias copy cp

  def cp_r(src, dest, preserve: nil, noop: nil, verbose: nil, dereference_root: true, remove_destination: nil)
    report("cp -r #{[*src, dest].join(" ")}", verbose)
    return if noop

    each_source(src, dest) { |from, to| copy_tree(from, to, preserve, remove_destination) }
    nil
  end

  def copy_file(src, dest, preserve = nil, _dereference = true)
    File.write(dest, File.binread(src), mode: "wb")
    File.chmod(File.stat(src).mode & 0o7777, dest)
    File.utime(File.atime(src), File.mtime(src), dest) if preserve
    nil
  end

  def copy_stream(src, dest)
    dest.write(src.read)
    nil
  end

  def mv(src, dest, force: nil, noop: nil, verbose: nil, secure: nil)
    report("mv #{[*src, dest].join(" ")}", verbose)
    return if noop

    each_source(src, dest) do |from, to|
      File.rename(from, to)
    rescue SystemCallError
      copy_tree(from, to, true, true)
      remove_entry(from, force)
    end
    nil
  end

  alias move mv

  def touch(list, noop: nil, verbose: nil, mtime: nil, nocreate: nil)
    list = paths(list)
    report("touch #{list.join(" ")}", verbose)
    return if noop

    now = mtime || Time.now
    list.each do |path|
      File.write(path, "", mode: "a") unless nocreate && !File.exist?(path)
      File.utime(now, now, path)
    end
    nil
  end

  def ln(src, dest, force: nil, noop: nil, verbose: nil)
    report("ln #{[*src, dest].join(" ")}", verbose)
    return if noop

    each_source(src, dest) do |from, to|
      remove_file(to, true) if force
      File.link(from, to)
    end
    nil
  end

  alias link ln

  def ln_s(src, dest, force: nil, noop: nil, verbose: nil, target_directory: true)
    report("ln -s #{[*src, dest].join(" ")}", verbose)
    return if noop

    each_source(src, dest) do |from, to|
      remove_file(to, true) if force
      File.symlink(from, to)
    end
    nil
  end

  alias symlink ln_s

  def ln_sf(src, dest, noop: nil, verbose: nil) = ln_s(src, dest, force: true, noop: noop, verbose: verbose)

  def install(src, dest, mode: nil, owner: nil, group: nil, preserve: nil, noop: nil, verbose: nil)
    report("install #{[*src, dest].join(" ")}", verbose)
    return if noop

    each_source(src, dest) do |from, to|
      copy_file(from, to, preserve)
      File.chmod(mode, to) if mode
      File.chown(owner, group, to) if owner || group
    end
    nil
  end

  def chmod(mode, list, noop: nil, verbose: nil)
    list = paths(list)
    report("chmod #{mode} #{list.join(" ")}", verbose)
    return list if noop

    list.each { |path| File.chmod(mode, path) }
    list
  end

  def chmod_R(mode, list, noop: nil, verbose: nil, force: nil)
    paths(list).each { |path| walk(path) { |entry| File.chmod(mode, entry) unless noop } }
    list
  end

  def chown(user, group, list, noop: nil, verbose: nil)
    list = paths(list)
    report("chown #{user}:#{group} #{list.join(" ")}", verbose)
    return list if noop

    list.each { |path| File.chown(user, group, path) }
    list
  end

  def chown_R(user, group, list, noop: nil, verbose: nil, force: nil)
    paths(list).each { |path| walk(path) { |entry| File.chown(user, group, entry) unless noop } }
    list
  end

  def compare_file(a, b) = File.binread(a) == File.binread(b)

  alias identical? compare_file
  alias cmp compare_file

  def compare_stream(a, b) = a.read == b.read

  def uptodate?(new, old_list)
    return false unless File.exist?(new)

    paths(old_list).all? { |old| !File.exist?(old) || File.mtime(new) >= File.mtime(old) }
  end

  # The names a `FileUtils.<kind>` module carries, which is how ruby
  # builds its own quiet and dry-run twins.
  def self.collect_method(option)
    public_instance_methods(false).select { |name| instance_method(name).parameters.any? { |kind, name2| kind == :key && name2 == option } }.map(&:to_s).sort
  end

  private

  def paths(list) = list.is_a?(Array) ? list.map(&:to_s) : [list.to_s]

  def report(line, verbose)
    $stderr.puts(line) if verbose
  end

  def make_parents(path, mode)
    return if path.empty? || File.directory?(path)

    up = File.dirname(path)
    make_parents(up, mode) unless up == path
    mode ? Dir.mkdir(path, mode) : Dir.mkdir(path)
  rescue Errno::EEXIST
    nil
  end

  # `cp a, b` and `cp [a, b], dir`: a directory destination takes each
  # source under its own basename.
  def each_source(src, dest)
    dest = dest.to_s
    list = src.is_a?(Array) ? src.map(&:to_s) : [src.to_s]
    into = File.directory?(dest)
    list.each { |from| yield(from, into ? File.join(dest, File.basename(from)) : dest) }
  end

  def copy_tree(from, to, preserve, remove_destination)
    remove_entry(to, true) if remove_destination
    if File.directory?(from) && !File.symlink?(from)
      Dir.mkdir(to) unless File.directory?(to)
      Dir.children(from).each { |name| copy_tree(File.join(from, name), File.join(to, name), preserve, false) }
      File.chmod(File.stat(from).mode & 0o7777, to)
    elsif File.symlink?(from)
      File.symlink(File.readlink(from), to)
    else
      copy_file(from, to, preserve)
    end
  end

  def walk(path, &block)
    block.call(path)
    return unless File.directory?(path) && !File.symlink?(path)

    Dir.children(path).each { |name| walk(File.join(path, name), &block) }
  end
end
