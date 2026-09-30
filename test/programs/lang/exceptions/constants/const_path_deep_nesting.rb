# Stress test: a constant path 6 levels deep, more than typical Ruby
# code uses. Each level must resolve, with no level lost.

module L1
  module L2
    module L3
      module L4
        module L5
          class L6
            def self.tag
              "L1::L2::L3::L4::L5::L6"
            end

            def echo(s)
              s + " <- " + L1::L2::L3::L4::L5::L6.tag
            end
          end
        end
      end
    end
  end
end

puts L1::L2::L3::L4::L5::L6.tag
puts L1::L2::L3::L4::L5::L6.new.echo("hi")
