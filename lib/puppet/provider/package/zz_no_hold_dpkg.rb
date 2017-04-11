# Dummy provider whose purpose is to "force" Puppet to load the dpkg code before monkey patching it
Puppet::Type.type(:package).provide :zz_force_dpkg_load_for_monkeypatch, :parent => :dpkg, :source => :dpkg do
  class Puppet::Type::Package::ProviderDpkg
    def self.parse_line(line)
      hash = nil

      if match = self::FIELDS_REGEX.match(line)
        hash = {}

        self::FIELDS.zip(match.captures) do |field,value|
          hash[field] = value
        end

        hash[:provider] = self.name

        if hash[:status] == 'not-installed'
          hash[:ensure] = :purged
        elsif ['config-files', 'half-installed', 'unpacked', 'half-configured'].include?(hash[:status])
          hash[:ensure] = :absent
        end
      else
        Puppet.debug("Failed to match dpkg-query line #{line.inspect}")
      end

      return hash
    end
  end
end
