# native only: the json gem's ruby half over the runtime's own parser and generator
require "json"

p JSON.generate({ "a" => 1, "b" => [1, 2.5, nil, true, false], "c" => { "d" => "e" } })
p JSON.generate([])
p JSON.generate({})
p JSON.pretty_generate({ "a" => 1, "b" => [1, 2] })
p JSON.generate("a\"b\\c\neé")
p JSON.generate("é", ascii_only: true)
p({ "a" => 1 }.to_json, [1, nil].to_json, 1.to_json, "x".to_json, nil.to_json, true.to_json, 2.5.to_json)
p JSON.dump({ "k" => "v" })

p JSON.parse('{"a":[1,2.5,null,true,false,"xé😀"],"b":{"c":{}}}')
p JSON.parse('{"a":1}', symbolize_names: true)
p JSON.parse('"é😀\t"')
p JSON.parse("[1e3,-2.5e-2,0,-0]")
p JSON.load('{"a":1}')
p JSON.load("")
p JSON.parse("  [ 1 , 2 ]  ")

["", "{", "[1,]", '{"a":}', "nul", "1 2", '"a', "{1:2}", '{"a" 1}', "[", '{"a":1,}', "[01]", "[1.]", '["\q"]', "[é]"].each do |s|
  begin
    JSON.parse(s)
  rescue JSON::ParserError => e
    puts "#{s.inspect} -> #{e.class}: #{e.message}"
  end
end

begin
  JSON.generate(0.0 / 0.0)
rescue JSON::GeneratorError => e
  p [e.class, e.message]
end
p JSON.generate(0.0 / 0.0, allow_nan: true)
p JSON.parse("[NaN,Infinity,-Infinity]", allow_nan: true).map(&:to_s)
p JSON.generate([[1]], max_nesting: 1) rescue p [$!.class, $!.message]
p JSON.parse("[[1]]", max_nesting: 1) rescue p [$!.class, $!.message]
