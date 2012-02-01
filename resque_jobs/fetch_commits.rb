# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "bundler/setup"
require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "open3"

class FetchCommits
  include JobsHelper
  @queue = :fetch_commits

  REPO_DIRS = File.expand_path("~/immunity_repos/")

  def self.perform
    setup_logger("fetch_commits.log")
    begin
      fetch_commits()
    rescue => exception
      logger.info("Failed to complete job: #{exception}")
      raise exception
    end

    # Reconnect to the database if our connection has timed out.
    Build.select(1).first rescue nil
  end

  def self.fetch_commits()
    # TODO(philc): This repo name shouldn't be hardcoded here.
    repos = ["html5player"]

    repos.each do |repo_name|
      logger.info "Fetching new commits from #{repo_name}."
      project_repo = File.join(REPO_DIRS, repo_name)
      run_command("cd #{project_repo} && git pull")
      # TODO(philc): We must also pull this repo, because html5player has symlinks into it. This will soon
      # change.
      run_command("cd #{File.join(REPO_DIRS, 'playertools')} && git pull")
      latest_commit = run_command("cd #{project_repo} && git rev-list --max-count=1 head").strip
      if Build.first(:commit => latest_commit, :repo => repo_name).nil?
        logger.info "#{repo_name} has new commits. The latest is now #{latest_commit}."
        build = Build.create(:commit => latest_commit, :repo => repo_name)
        build.fire_events(:begin_deploy)
      end
    end
  end

  def self.run_command(command)
    stdout, stderr, status = Open3.capture3(command)
    Open3.popen3(command) { |stdin, stdout, stderr| stdout_stream = stdout }
    raise %Q(The command "#{command}" failed: #{stderr}) unless status == 0
    stdout
  end
end

if $0 == __FILE__
  FetchCommits.perform
end
