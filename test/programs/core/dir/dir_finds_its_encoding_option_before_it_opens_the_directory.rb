# Dir.new, Dir.open, Dir.entries, Dir.children, Dir.each_child and
# Dir.foreach find the `encoding:` option before they read the path or
# open the directory, so a bad name or type raises first.
def try(label)
  result = yield
  puts "#{label}: #{result.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

missing = "/no/such/directory/for/this/test"
%i[entries children].each do |name|
  try("#{name} unknown") { Dir.public_send(name, missing, encoding: "nope") }
  try("#{name} integer") { Dir.public_send(name, missing, encoding: 5) }
  try("#{name} integer path") { Dir.public_send(name, 5, encoding: "nope") }
  try("#{name} missing") { Dir.public_send(name, missing, encoding: "UTF-8") }
end
%i[each_child foreach].each do |name|
  try("#{name} unknown") { Dir.public_send(name, missing, encoding: "nope") { } }
  try("#{name} missing") { Dir.public_send(name, missing, encoding: Encoding::UTF_8) { } }
  try("#{name} enumerator") { Dir.public_send(name, missing, encoding: "nope").class }
end
try("new unknown") { Dir.new(missing, encoding: "nope") }
try("new integer path") { Dir.new(5, encoding: "nope") }
try("open integer") { Dir.open(missing, encoding: 5) }
try("open missing") { Dir.open(missing, encoding: "binary") }
try("open block") { Dir.open(missing, encoding: "nope") { :never } }

here = File.expand_path(__dir__)
try("entries binary") { Dir.entries(here, encoding: "BINARY").map(&:encoding).uniq }
try("children encoding object") { Dir.children(here, encoding: Encoding::UTF_8).map(&:encoding).uniq }
try("new nil") { Dir.new(here, encoding: nil).children.map(&:encoding).uniq }
try("new latin1") { Dir.new(here, encoding: "ISO-8859-1").read.encoding }
