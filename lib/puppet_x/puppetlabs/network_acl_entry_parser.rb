module PuppetX
  module Puppetlabs
    class NetworkAclEntryParser


        def initialize(entries)
          @entries = []
          @entries << entries.reject(&:nil?).collect do |entry|
            # expand port to to_port and from_port
            new_entry = Marshal.load(Marshal.dump(entry))
            if entry.key? 'port_range'
              value = entry['port_range']
              entry.delete 'port_range'
              entry['from_port'] = value.from.to_i
              entry['to_port'] = value.to.to_i
            end
            entry
          end
          @entries = @entries.flatten
        end

        def entries_to_create(entries)
          stringify_values(@entries) - stringify_values(entries)
        end

        def entries_to_delete(entries)
          stringify_values(entries) - stringify_values(@entries)
        end

        private
        def stringify_values(entries)
          entries.collect do |obj|
            obj.each { |k,v| obj[k] = v.to_s }
          end
        end

    end
  end
end
