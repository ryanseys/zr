# File's path functions read a path by its bytes, as ruby's file.c does,
# so a byte that is no character in the path's encoding is no error.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}#{" (#{r.encoding})" if r.is_a?(String)}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

["\xff", "a\xff/b\xfe.r\xffb", "/\xff/", "\xff.", ".\xff", "a/\xff\xfe/", "\xff//\xfe", "\xe9t\xe9.txt".b].each do |path|
  try("basename #{path.inspect}") { File.basename(path) }
  try("basename .* #{path.inspect}") { File.basename(path, ".*") }
  try("basename .rb #{path.inspect}") { File.basename(path, ".rb") }
  try("extname #{path.inspect}") { File.extname(path) }
  try("dirname #{path.inspect}") { File.dirname(path) }
  try("dirname 2 #{path.inspect}") { File.dirname(path, 2) }
  try("split #{path.inspect}") { File.split(path) }
  try("join #{path.inspect}") { File.join("d", path, "e") }
  try("expand_path #{path.inspect}") { File.expand_path(path, "/r") }
  try("absolute_path #{path.inspect}") { File.absolute_path(path, "/r") }
  try("absolute_path? #{path.inspect}") { File.absolute_path?(path) }
  try("exist? #{path.inspect}") { File.exist?(path) }
  try("fnmatch #{path.inspect}") { File.fnmatch("*", path) }
end

try("basename suffix with a bad byte") { File.basename("a/\xff.r\xfe", ".r\xfe") }
try("basename UTF-16 suffix") { File.basename("a.rb", ".rb".encode("UTF-16LE")) }
