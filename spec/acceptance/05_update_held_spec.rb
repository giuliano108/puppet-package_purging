require 'spec_helper_acceptance'

describe 'package_holding_with_apt' do
  def get_installed_version host, package_name
    line = on(host, "dpkg -s #{package_name} | grep ^Version").stdout
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
    end
  end

  context 'updating an held package between pinned versions' do
    it 'works' do
      # install dummypkg=0.0.1
      m = <<-EOS
        package {'dummypkg': ensure => '0.0.1'}
        aptly_purge {'packages':
          hold => true,
        }

        exec {'unhold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections > /tmp/unhold-1-`/bin/date +%s%N`.txt"'
        }
        exec {'hold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections > /tmp/hold-1-`/bin/date +%s%N`.txt"'
        }

        Exec['unhold'] ->
        Package <| |> ->
        Dpkg_hold <| |> ->
        Exec['hold']
      EOS
      apply_manifest m
      expect(@result.exit_code).to eq 0
      expect(package('dummypkg')).to be_installed

      # run the manifest again, so that the package gets held
      apply_manifest m
      expect(@result.exit_code).to eq 0
      packages_state = get_packages_state default_node
      expect(packages_state['dummypkg']).to eq('hold')
      expect(get_installed_version(default_node, 'dummypkg')).to eq('0.0.1')

      # install dummypkg=0.0.2
      m = <<-EOS
        package {'dummypkg': ensure => '0.0.2'}
        aptly_purge {'packages':
          hold => true,
        }

        exec {'unhold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections > /tmp/unhold-2-`/bin/date +%s%N`.txt"'
        }
        exec {'hold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections > /tmp/hold-2-`/bin/date +%s%N`.txt"'
        }

        Exec['unhold'] ->
        Package <| |> ->
        Dpkg_hold <| |> ->
        Exec['hold']
      EOS
      apply_manifest m
      expect(@result.exit_code).to eq 0
      expect(package('dummypkg')).to be_installed
      expect(get_installed_version(default_node, 'dummypkg')).to eq('0.0.2')

      # run the manifest again, so that the package gets held
      apply_manifest m
      expect(@result.exit_code).to eq 0
      packages_state = get_packages_state default_node
      expect(packages_state['dummypkg']).to eq('hold')
      expect(get_installed_version(default_node, 'dummypkg')).to eq('0.0.2')
    end
  end

  if false
  context 'updating an held package from a pinned version to ensure => latest' do
    it 'works' do
      # install dummypkg=0.0.1
      m = <<-EOS
        package {'dummypkg': ensure => '0.0.1'}
        aptly_purge {'packages':
          hold => true,
        }

        exec {'unhold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections > /bin/grep hold$ > /tmp/unhold-1-`/bin/date +%s%N`.txt"'
        }
        exec {'hold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections > /bin/grep hold$ > /tmp/hold-1-`/bin/date +%s%N`.txt"'
        }

        Exec['unhold'] ->
        Package <| |> ->
        Dpkg_hold <| |> ->
        Exec['hold']
      EOS
      apply_manifest m
      expect(@result.exit_code).to eq 0
      expect(package('dummypkg')).to be_installed

      # run the manifest again, so that the package gets held
      apply_manifest m
      expect(@result.exit_code).to eq 0
      packages_state = get_packages_state default_node
      expect(packages_state['dummypkg']).to eq('hold')
      expect(get_installed_version(default_node, 'dummypkg')).to eq('0.0.1')

      # install latest dummypkg
      m = <<-EOS
        package {'dummypkg': ensure => 'latest'}
        aptly_purge {'packages':
          hold => true,
        }

        exec {'unhold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections | /bin/grep hold$ > /tmp/unhold-2-`/bin/date +%s%N`.txt"'
        }
        exec {'hold':
          command => '/bin/bash -c "/usr/bin/dpkg --get-selections | /bin/grep hold$ > /tmp/hold-2-`/bin/date +%s%N`.txt"'
        }

        Exec['unhold'] ->
        Package <| |> ->
        Dpkg_hold <| |> ->
        Exec['hold']
      EOS
      apply_manifest m
      expect(@result.exit_code).to eq 0
      expect(package('dummypkg')).to be_installed
      expect(get_installed_version(default_node, 'dummypkg')).to eq('0.0.3')

      # run the manifest again, so that the package gets held
      apply_manifest m
      expect(@result.exit_code).to eq 0
      packages_state = get_packages_state default_node
      expect(packages_state['dummypkg']).to eq('hold')
      expect(get_installed_version(default_node, 'dummypkg')).to eq('0.0.3')
    end
  end
  end
end
