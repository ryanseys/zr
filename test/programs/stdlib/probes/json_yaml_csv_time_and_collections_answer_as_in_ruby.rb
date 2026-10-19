# A probe of many methods, each line one call and its answer or its error,
# compared with ruby's.
def t(label)
  r = begin
    yield.inspect
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  puts "#{label}: #{r}"
end

require "json"; require "yaml"; require "csv"; require "time"; require "date"; require "pp"; require "set"
t("json gen") { JSON.generate({ "a" => [1, 2.5, nil, true], b: "é " }) }
t("json pretty") { JSON.pretty_generate({ a: [], b: {}, c: [1, { d: 2 }] }) }
t("json parse") { JSON.parse('{"a":[1,2.0,"x",null],"b":{"c":true}}', symbolize_names: true) }
t("json err") { JSON.parse("{a:1}") }
t("json nan") { JSON.generate(Float::NAN) }
t("json big") { JSON.parse("123456789012345678901234567890.5e3", decimal_class: Rational) rescue JSON.parse("1e400") }
t("json obj") { JSON.parse('{"json_class":"String","raw":[97]}', create_additions: false) }
t("json dump") { JSON.dump("a" => 1) + JSON.dump([1], nil) }
t("json load") { JSON.load("[1, 2]") }
t("to_json") { [1.0.to_json, :sym.to_json, nil.to_json, "\u0000".to_json, Time.at(0).utc.to_json] }
t("yaml dump") { { "a" => [1, "two", 3.0, nil, true], "b" => { "c" => :d }, "e" => "multi\nline" }.to_yaml }
t("yaml load") { YAML.load("a: 1\nb: [x, y]\nc: !!str 3\nd: 2001-02-03\n", permitted_classes: [Date]) }
t("yaml safe") { YAML.safe_load("--- :sym\n") }
t("yaml anchors") { YAML.load("a: &x [1]\nb: *x\n", aliases: true) }
t("yaml dump obj") { Struct.new(:a).new(1).to_yaml rescue $!.class }
t("csv parse") { CSV.parse("a,b\n1,\"x,y\"\n\"q\"\"\",\n") }
t("csv headers") { CSV.parse("a,b\n1,2\n", headers: true).map(&:to_h) }
t("csv gen") { CSV.generate { |c| c << [1, "a,b", nil, "q\""] } }
t("csv line") { ["x", nil, 3].to_csv + "a;b".parse_csv(col_sep: ";").inspect }
t("time parse") { Time.parse("2001-02-03 04:05:06 +0700").utc.to_a.first(6) }
t("time iso") { [Time.iso8601("2001-02-03T04:05:06Z").to_i, Time.at(981173106).utc.iso8601(3), Time.utc(2001, 2, 3).httpdate, Time.utc(2001, 2, 3).rfc2822] }
t("strptime") { Time.strptime("03/02/2001 13:00", "%d/%m/%Y %H:%M").strftime("%F %T %j %U %a %b %e %-m %^a %3N") }
t("time math") { t0 = Time.utc(2000, 1, 31); [(t0 + 86_400).day, (Time.utc(2000, 3, 1) - t0) / 86_400, t0.round(0).usec] }
t("date") { d = Date.new(2001, 2, 3); [d >> 1, d.next_day(30).to_s, d.cwday, d.yday, d.leap?, (Date.new(2001, 12, 25) - d).to_i, d.strftime("%A %-d %B")] }
t("date parse") { [Date.parse("Feb 3 2001").to_s, Date.iso8601("2001-W05-6").to_s, Date.strptime("2001-034", "%Y-%j").to_s, Date.valid_date?(2001, 2, 29)] }
t("datetime") { DateTime.new(2001, 2, 3, 4, 5, 6, "+7").iso8601 }
t("pp") { PP.pp({ a: (1..30).to_a, b: { c: "x" * 50, d: [nil, :sym] } }, +"", 40) }
t("pp obj") { o = Object.new; o.instance_variable_set(:@a, [1] * 3); PP.pp(o, +"").sub(/0x\h+/, "X") }
t("set") { s = Set[3, 1, 2]; [s.include?(2), (s | [5]).size, s.to_a.sort, s.subset?(Set[1, 2, 3, 4]), s.inspect, Set[[1, 2]].to_h] }
t("set2") { [Set[1, 2] <=> Set[1], Set[1].disjoint?([2]), Set.new([1, 2]) { _1 * 2 }, Set[1, 2].group_by(&:odd?)] }
t("struct") { s = Struct.new(:a, :b, keyword_init: true); x = s.new(a: 1, b: 2); [x.to_h, x.inspect, x == s.new(a: 1, b: 2), s.members] }
t("data") { d = Data.define(:x, :y) { def sum = x + y }; v = d.new(x: 1, y: 2); [v.sum, v.with(y: 5).inspect, v.to_h, (d.new(1) rescue $!.message)] }
t("hash") { h = { b: 2, a: 1 }; [h.sort.to_h, h.min_by { _2 }, h.sum { _2 }, h.to_a.transpose, h.filter_map { _1 if _2 > 1 }, h.each_with_object([]) { |(k, v), a| a << k }] }
t("array") { a = [3, 1, 2, 2]; [a.tally, a.each_slice(3).to_a, a.each_cons(2).count, a.combination(2).count, a.minmax, a.sort.bsearch { _1 >= 2 }, a.cycle.first(6), a.product([0]).size, a.flat_map { [_1] * 2 }.size, a.chunk_while { _2 == _1 }.to_a] }
t("enum lazy") { (1..Float::INFINITY).lazy.map { _1 * 2 }.select { _1 % 3 == 0 }.first(3) }
t("enum zip") { [1, 2].zip([3, 4], [5]) + [[1, 2].sum(0.0)] + [(1..4).each_entry.to_a] }
t("compare") { [[1, "a"] <=> [1, "b"], 1 <=> "a", nil.to_a, [1, [2, [3]]].flatten(1)] }
