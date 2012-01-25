#!/usr/bin/env ruby-local-exec
require "bundler/setup"
require "pathological"
require "clockwork"
require "resque_jobs/fetch_commits"

def clear_resque_queue(queue_name) Resque.redis.del("queue:#{queue_name}") end

# We're enqueing Resque jobs to be performed instead of trying to actually perform the work here from within
# the Clockwork process. This is recommended by the Clockwork maintainer. Since Clockwork is a
# non-parallelized loop, you don't want to perform long-running blocking work here.
# We're clearing out the queue for a job before pushing another item onto its queue, in case the job is
# taking a very long time to run. We don't want to build up a backlog on the queue because clockwork is
# moving faster than the job is.
Clockwork.handler do |job_name|
  case job_name
  when "fetch_commits"
    clear_resque_queue("fetch_commits")
    Resque.enqueue(FetchCommits)
  end
  STDOUT.flush
end

# NOTE(philc): This is set to 3 seconds for testing purposes. Ideally we would only pull 
Clockwork.every(3.seconds, "fetch_commits")

Clockwork.run # This is a blocking call.
