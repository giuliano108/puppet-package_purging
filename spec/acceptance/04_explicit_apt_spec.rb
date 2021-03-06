require 'spec_helper_acceptance'

describe 'provider => apt tests -' do
  def get_installed_version host, package_name
    line = on(host, "dpkg -s #{package_name} | grep ^Version").stdout
    version = line.gsub(/\s+/,'').split(':',2).last
    version.empty? ? nil : version
  end

  def get_candidate_version host, package_name
    line = on(host, "apt-cache policy #{package_name} | grep Candidate: | head -1").stdout
    version = line.gsub(/\s+/,'').split(':',2).last
    version.empty? ? nil : version
  end

  def get_packages_state host
    packages_state = on(host, 'dpkg-query -W --showformat \'${Status} ${Package}\n\'').stdout
    packages_state.lines.each_with_object({}) do |line, h|
      if match = line.match(/^(\S+) +(\S+) +(\S+) (\S+)$/)
        desired, error, status, name = match.captures
        h[name] = desired
      end
    end
  end

  def set_package_state host, package, state
    on(host, "echo #{package} #{state} | dpkg --set-selections")
  end

  before :all do
    @managed_packages = [
      'ubuntu-minimal',
      'puppetlabs-release-pc1',
      'puppet-agent',
      'openssh-server',
      'dummypkg',
    ]
    @package_versions = {}

    hosts.each do |host|
      localpath = File.dirname(__FILE__) + '/fixtures'
      remotepath = '/usr/local/localrepo'
      on host, "mkdir #{remotepath}", :accept_all_exit_codes => true
      1.upto 3 do |n|
        scp_to host, "#{localpath}/dummypkg_0.0.#{n}_all.deb", remotepath
      end
      scp_to host, "#{localpath}/Packages.gz", remotepath
      scp_to host, "#{localpath}/localrepo.list", '/etc/apt/sources.list.d'
      on host, "apt-get update -o Dir::Etc::sourcelist=sources.list.d/localrepo.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0"

      install_package host, 'dummypkg'
      # same as `include package_purging::config`, saves a Puppet run
      create_remote_file host, '/etc/apt/apt.conf.d/99always-purge', "APT::Get::Purge \"true\";\n";

      @managed_packages.each do |p|
        @package_versions[p] = get_installed_version(host, p) || get_candidate_version(host, p)
      end

      @managed_packages.each do |p|
        set_package_state default_node, p, 'install'
      end
      packages_state = get_packages_state default_node
      expect(packages_state.values_at(*@managed_packages)).to eq(['install'] * @managed_packages.length)
    end
  end

  context 'manifest manages a few packages, all of them pin a specific version' do
    it 'should hold all the packages' do
      managed_packages = @managed_packages
      m = @package_versions.map do |p, v|
        "package { '#{p}': ensure => '#{v}' }"
      end.join("\n")
      m += <<-EOS

        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      # our packages are held
      expect(packages_state.values_at(*managed_packages)).to eq(['hold'] * managed_packages.length)
      # everything else isn't
      expect(packages_state.values_at(*(packages_state.keys - managed_packages))).not_to include('hold')
    end
  end

  context 'dummypkg installed by specifying provider => apt' do
    it 'produces a noop puppet run' do
      managed_packages = @managed_packages
      m = (managed_packages - ['dummypkg']).map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      p = 'dummypkg'
      m += <<-EOS

        package{'#{p}':
          ensure => '#{@package_versions[p]}',
          provider => 'apt',
        }
        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :catch_changes => true, :debug => true
      expect(@result.exit_code).to eq 0
      expect(package('dummypkg')).to be_installed

      packages_state = get_packages_state default_node
      # our packages are held
      expect(packages_state.values_at(*managed_packages)).to eq(['hold'] * managed_packages.length)
      # everything else isn't
      expect(packages_state.values_at(*(packages_state.keys - managed_packages))).not_to include('hold')
    end
  end
end
