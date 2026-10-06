# `Dir.mkdir`/`rmdir` round-trip, and `File.rename`/`delete`.

dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zr_e2e_mut_#{Process.pid}")
Dir.mkdir(dir)
begin
  fresh = File.join(dir, "fresh")
  Dir.mkdir(fresh)
  p Dir.exist?(fresh)
  Dir.rmdir(fresh)
  p Dir.exist?(fresh)

  a = File.join(dir, "a.txt")
  b = File.join(dir, "b.txt")
  File.write(a, "x")
  File.rename(a, b)
  p [File.exist?(a), File.exist?(b)]
  p File.delete(b)
  p File.exist?(b)
ensure
  Dir.rmdir(dir)
end
