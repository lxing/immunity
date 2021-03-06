require "fileutils"
require "terraform"

# Run multiple commands in one big ssh invocation, for brevity and ssh efficiency.
def run_commands(*commands) run commands.join(" && ") end

namespace :fezzik do
  desc "stages the project for deployment in /tmp"
  task :stage do
    puts "staging project in /tmp/#{app}"
    staging_dir = "/tmp/#{app}/staged"
    FileUtils.rm_rf "/tmp/#{app}"
    FileUtils.mkdir_p staging_dir

    # Use rsync to preserve executability and follow symlinks.
    system("rsync -aqE #{local_path}/. #{staging_dir}")
    stage_sensitive_files
    Terraform.write_dsl_file("#{staging_dir}/script/")
  end

  desc "performs any necessary setup on the destination servers prior to deployment"
  remote_task :setup, :roles => [:root_user] do
    puts "setting up servers"
    has_user = Fezzik::Util.capture_output { run "getent passwd #{user} || true" }.size > 0
    unless has_user
      puts "Creating #{user} user."
      run_commands(
          "useradd --create-home --shell /bin/bash #{user}",
          "adduser #{user} --add_extra_groups admin",
          "mkdir -p /home/#{user}/.ssh/",
          "cp ~/.ssh/authorized_keys /home/#{user}/.ssh",
          "chown -R #{user} /home/#{user}/.ssh")
    end
    run "mkdir -p #{deploy_to}/releases && chown #{user} #{deploy_to} #{deploy_to}/releases"
  end

  desc "after the app code has been rsynced, sets up the app's dependencies, like gems"
  remote_task :setup_app, :roles => [:deploy_user] do
    puts "Setting up server dependencies. This will take 8 minutes to install Ruby the first time it's run."
    # This PATH addition is required for Vagrant, which has Ruby installed, but it's not in the default PATH.
    run "cd #{release_path} && PATH=$PATH:/opt/ruby/bin script/system_setup.rb"
    run "cd #{release_path} && script/initial_app_setup.rb production"
    Rake::Task["fezzik:generate_foreman_upstart_scripts"].invoke
  end

  remote_task :generate_foreman_upstart_scripts, :roles => [:deploy_user] do
    puts "Exporting foreman daemon scripts to /etc/init"
    foreman_command = "foreman export upstart /etc/init -a #{app} -l /var/log/#{app} -u #{user} > /dev/null"
    run "cd #{release_path} && sudo bundle exec #{foreman_command}"

    # Munge the Foreman-generated upstart conf files so that our app starts on system startup (right after
    # mysql). This is a bit hacky -- Foreman supports templates which you can use to modify the generated
    # upstart conf files. At the time of writing this was not worth the extra effort.
    run %Q(sudo bash -c 'echo "start on starting mysql" >> /etc/init/#{app}.conf')
  end

  desc "rsyncs the project from its staging location to each destination server"
  remote_task({ :push => [:stage, :setup] }, { :roles => [:deploy_user] }) do
    puts "pushing to #{target_host}:#{release_path}"
    # Copy on top of previous release to optimize rsync
    rsync "-q", "--copy-dest=#{current_path}", "/tmp/#{app}/staged/", "#{target_host}:#{release_path}"
  end

  desc "symlinks the latest deployment to /deploy_path/project/current"
  remote_task :symlink, :roles => [:deploy_user] do
    puts "symlinking current to #{release_path}"
    run "cd #{deploy_to} && ln -fns #{release_path} current"
    # Add a symlink to the current deploy in our user's home directory, for convenience.
    run "rm ~/current 2> /dev/null; ln -s #{current_path} ~/current"
  end

  desc "runs the executable in project/bin"
  remote_task :start, :roles => [:root_user] do
    puts "starting from #{Fezzik::Util.capture_output { run "readlink #{current_path}" }}"
    # Upstart will not let you start a started job. Check if it's started already prior to invoking start.
    run "(status #{app} | grep stop) && start #{app} || true"
    # Give the server some time to start before checking on its status.
    sleep 5
    server_is_up?
  end

  remote_task :check_healthz, :roles => [:deploy_user] do
    server_is_up?
  end

  desc "kills the application by searching for the specified process name"
  remote_task :stop, :roles => [:root_user] do
    # Upstart will not let you stop a stopped job. Check if it's stopped already prior to invoking stop.
    run "(status #{app} | grep start) && stop #{app} || true"
  end

  desc "restarts the application"
  remote_task :restart, :roles => [:deploy_user] do
    Rake::Task["fezzik:stop"].invoke
    Rake::Task["fezzik:start"].invoke
  end

  desc "full deployment pipeline"
  task :deploy do
    Rake::Task["fezzik:deploy_without_tests"].invoke
    Rake::Task["fezzik:run_integration_tests"].invoke
    puts "#{app} deployed!"
  end

  task :deploy_without_tests do
    Rake::Task["fezzik:push"].invoke
    Rake::Task["fezzik:symlink"].invoke
    Rake::Task["fezzik:setup_app"].invoke
    Rake::Task["fezzik:restart"].invoke
  end

  desc "Run the integration tests remotely on the server"
  remote_task :run_integration_tests, :roles => [:deploy_user] do
    puts "Running the integration tests."
    run "cd #{current_path} && bundle exec rake test:integrations"
  end

  # We have some sensitive files (like a private ssh key for git) which are checked into the git repo.
  # These get copied into the staged deploy prior to rsyncing the code to the remote server.
  def stage_sensitive_files
    key_file = "git_ssh_private_key"
    credentials_directory = ENV["IMMUNITY_CREDENTIALS"]
    unless credentials_directory && File.exist?("#{credentials_directory}/#{key_file}")
      raise "You must set the IMMUNITY_CREDENTIALS env variable and place the #{key_file} file there."
    end

    # Copy our private SSH key for git into the staged deploy.
    FileUtils.cp("#{credentials_directory}/#{key_file}", "/tmp/#{app}/staged/script/system_setup_files/")
  end

  # Makes a request to the server's /healthz route. Raises an exception if healthz is not a 200.
  def server_is_up?
    begin
      # -s: silent, -S: show error messages
      env_settings = Fezzik.environments[hostname]
      command = "curl -s -S --max-time 6 localhost:#{env_settings[:immunity_server_port]}/healthz"
      puts "checking: #{command}"
      healthz_output = Fezzik::Util.capture_output { run command }
      raise "/healthz responded with: #{healthz_output}" unless healthz_output.downcase.include?("healthy")
      true
    rescue Exception => error
      puts "The service is down. It may have had trouble starting."
      raise error
    end
  end
end
