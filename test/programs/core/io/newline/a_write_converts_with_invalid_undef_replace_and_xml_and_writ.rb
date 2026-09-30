# A write's conversion takes invalid:, undef:, replace: and xml:, and a
# UTF-16 or UTF-32 stream writes its byte order mark once.
path = "/tmp/zr_spec_write_conv.txt"
def written(path, mode, text, **options)
  File.open(path, mode, **options) { |f| text.is_a?(Array) ? text.each { f.write(_1) } : f.write(text) }
  File.binread(path)
rescue => e
  e
end
p written(path, "w:us-ascii", "é", undef: :replace)
p written(path, "w:iso-8859-1", "\xff", invalid: :replace)
p written(path, "w", "<a>&", xml: :text)
p written(path, "w:us-ascii", "é\"", xml: :attr)
p written(path, "w:us-ascii", "éa", undef: :replace, replace: "*")
p written(path, "w:iso-8859-1", "あ")
p written(path, "w:utf-16", %w[a b])
p written(path, "w:utf-32le", %w[a b])
File.delete(path)
