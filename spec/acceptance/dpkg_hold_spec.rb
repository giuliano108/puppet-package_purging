require 'spec_helper_acceptance'

if false  #TODO:
describe 'dpkg_hold' do
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

  before :all do

    @managed_packages = [
      'ubuntu-minimal',
      'puppetlabs-release-pc1',
      'puppet-agent',
      'openssh-server',
      'dict-jargon',
      'fortunes',
    ]
    @package_versions = {}

    hosts.each do |host|
      install_package host, 'dict-jargon'
      expect(check_for_package host, 'dictd').to be true
      install_package host, 'fortunes'
      expect(check_for_package host, 'fortunes-min').to be true
      # same as `include package_purging::config`, saves a Puppet run
      create_remote_file host, '/etc/apt/apt.conf.d/99always-purge', "APT::Get::Purge \"true\";\n";

      @managed_packages.each do |p|
        @package_versions[p] = get_installed_version(host, p) || get_candidate_version(host, p)
      end
    end
  end

  context 'manifest manages a few packages, all of them pin a specific version' do
    it 'should hold all the packages' do
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
      @managed_packages.each do | package |
        expect(packages_state[package]).to eq 'hold'
      end
      # everything else isn't
      expect(packages_state.values_at(*(packages_state.keys - @managed_packages))).not_to include('hold')
    end
  end

  context 'in the manifest, "fortunes" is changed to ensure => present' do
    it 'should stop holding "fortunes" as it\'s no longer pinned to a specific version' do
      m = (@managed_packages - ['fortunes']).map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        package { 'fortunes': ensure => present }
        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      #@managed_packages.each do | package |
      #  expect(packages_state[package]).to eq 'hold'
      #end
      expect(packages_state['fortunes']).not_to eq 'hold'
    end
  end

  context 'in the manifest, "fortunes" is changed to ensure => absent' do
    it 'should stop holding "fortunes" as it\'s no longer in the catalog' do
      m = (@managed_packages - ['fortunes']).map do |p|
        "package { '#{p}': ensure => '#{@package_versions[p]}' }"
      end.join("\n")
      m += <<-EOS

        package { 'fortunes': ensure => absent }
        aptly_purge {'packages':
          hold => true,
        }
      EOS
      apply_manifest m, :debug => true
      expect(@result.exit_code).to eq 0

      packages_state = get_packages_state default_node
      expect(packages_state['fortunes']).not_to eq 'hold'
    end

    #describe package('fortunes') do
    #  it { should_not be_installed }
    #end
  end

end
end
