Puppet::Type.type(:logical_volume).provide :lvm do
    desc "Manages LVM logical volumes"

    commands :lvcreate => 'lvcreate',
             :lvremove => 'lvremove',
             :lvextend => 'lvextend',
             :lvs      => 'lvs',
             :umount   => 'umount',
             :mount    => 'mount'

    def create
        args = ['-n', @resource[:name]]
        if @resource[:size]
            args.push('--size', @resource[:size])
        end
        args << @resource[:volume_group]
        lvcreate(*args)
    end

    def destroy
        lvremove('-f', path)
    end

    def exists?
        lvs(@resource[:volume_group]) =~ lvs_pattern
    end

    def size
        canonical = Size.parse(@resource[:size])
        if canonical
            raw = lvs('--noheading', '--unit', canonical.unit.downcase, path)
            Size.parse(raw)
        end
    end

    def size=(raw)
        new_size = Size.parse(raw)
        current_size = size
        vg_extent = extent

        if new_size >= current_size
            if new_size.fits?(vg_extent)
                return lvextend( '-L', size, path)
            else
                fail "Cannot extend to size #{new_size} because volume group extent size is #{vg_extent} KB"
            end
        else
            fail "Decreasing the size requires manual intervention (#{new_size} < #{current_size})"
        end
    end

    private

    def extent
        raw = lvs('--noheading', '-o', 'vg_extent_size', '--units', 'k', path)
        raw[/\s+(\d+)\.\d+k/, 1].to_i
    end

    def lvs_pattern
        /\s+#{Regexp.quote @resource[:name]}\s+/
    end

    def path
        "/dev/#{@resource[:volume_group]}/#{@resource[:name]}"
    end

    class Size
        include Comparable

        UNITS = {
            "K" => 1,
            "M" => 1024,
            "G" => 1048576,
            "T" => 1073741824,
            "P" => 1099511627776,
            "E" => 1125899906842624 }

        UNIT_PATTERN = UNITS.keys.join('|')

        PATTERN = /(\d+(?:\.?\d+)?)(#{UNIT_PATTERN})/i

        def self.parse(text)
            new(text) if text.match(PATTERN)
        end

        attr_reader :unit
        def initialize(raw)
            @raw = raw
            parse_value!
        end

        def <=>(other)
            kilobytes <=> other.kilobytes
        end

        def kilobytes
            UNITS[@unit] * @value
        end

        def fits?(extent)
            @value % extent == 0
        end

        def to_s
            @raw
        end

        private

        def parse_value!
            match = @raw.match(PATTERN)
            @value = Float(match[1])
            @unit = match[2].upcase
        end

    end

end
