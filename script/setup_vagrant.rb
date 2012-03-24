#!/usr/bin/env ruby-local-exec
# Sets up vagrant for your developer machine. This will:
# 1. Modify .ssh/config file so you can log in to Vagrant using `ssh immunity_system_vagrant`
#    instead of `vagrant ssh` (which is required to deploy to Vagrant).
# 2. Add vagrant's public ssh key to root's .ssh/authorized_keys file, so you can login as root.

def hostname() "immunity_system_vagrant" end

def setup
  run_command("vagrant up")
  setup_ssh_config
  # Ensure no old packages are lingering around. This will avoid possible 404's when installing packages.
  `ssh #{hostname} aptitude update`
end

def setup_ssh_config
  ssh_config_path = File.expand_path("~/.ssh/config")

  unless File.read(ssh_config_path).include?(hostname)
    # Create an entry in our ~/.ssh/config which allows us to ssh into this vagrant box by hostname.
    original_ssh_config = File.read(ssh_config_path)
    vagrant_ssh_config = run_command("vagrant ssh-config --host #{hostname}")
    # The ssh config block generated by Vagrant looks like this if you're curious:
    # Host immunity_system_vagrant
    #   HostName 127.0.0.1
    #   User vagrant
    #   Port 2222
    #   StrictHostKeyChecking no
    #   PasswordAuthentication no
    #   IdentityFile /Users/philc/.vagrant.d/insecure_private_key
    #   IdentitiesOnly yes

    # Change your local .ssh/config to use root by default to login to vagrant.
    vagrant_ssh_config = vagrant_ssh_config.split("\n").
        reject { |line| line.match(/User vagrant|UserKnownHostsFile/) }.join("\n")
    vagrant_ssh_config += "\n  User root\n\n"
    File.open(ssh_config_path, "w") { |file| file.write(vagrant_ssh_config + original_ssh_config) }
  end

  # The vagrant user has the default "vagrant public key" in authorized_keys. Make it so for root as well.
  remote_commands = "sudo mkdir /root/.ssh; sudo cp .ssh/authorized_keys /root/.ssh/authorized_keys"
  run_command "ssh vagrant@#{hostname} '#{remote_commands}'"
end

# Runs the command and raises an exception if its status code is nonzero. Returns the stdout of the command.
def run_command(command)
  require "open3"
  puts command
  stdout, stderr, status = Open3.capture3(command)
  raise %Q(The command "#{command}" failed: #{stderr}) unless status == 0
  stdout
end

setup()