require "bundler/setup"
require "pathological"
require "script/script_environment"
require "scope"
require "remote_http_testing"
require "minitest/autorun"

# The Resque queue to enqueue new jobs into when running the tests. Jobs in this queue will not be picked up
# by our normal Resque workers.
TEST_QUEUE = "integration_testing"
TEST_APP = "integration_testing_app"
RESQUE_SERVER = "http://localhost:3103"

#
# Convenience methods for making requests for builds.
#
module BuildRequestHelpers
  def get_build(id)
    raise "#{id} is not a string or an int" unless (id.is_a?(String) || id.is_a?(Fixnum))
    get "/builds/#{id}"
    assert_status 200
    json_response
  end

  def delete_build(id)
    raise "#{id} is not a string or an int" unless (id.is_a?(String) || id.is_a?(Fixnum))
    delete "/builds/#{id}"
    assert_status 200
  end

  def create_build(app_name, options = {})
    options = {
      :current_region => "integration_test_sandbox1", :commit => "test_commit"
    }.merge(options)
    post "/applications/#{app_name}/builds", {}, options.to_json
    assert_status 200
    json_response
  end

  def create_application(properties)
    properties = { :name => TEST_APP }.merge(properties)
    put "/applications/#{properties[:name]}", {}, properties.to_json
    assert_status 200
  end
end