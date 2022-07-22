ActiveRecord::Base.maintain_test_schema = ENV.fetch("KEEP_TEST_DATABASE", true).to_b
require 'test_helper'
require 'rails/performance_test_help'

class CommentsIndexTest < ActionDispatch::PerformanceTest
  self.profile_options = { runs: 5, metrics: [:wall_time] }
  # Refer to the documentation for all available options
  # self.profile_options = { runs: 5, metrics: [:wall_time, :memory],
  #                          output: 'tmp/performance', formats: [:flat] }

  test "Original Comments Index" do
    #Rails.logger.level = ActiveSupport::Logger::DEBUG
    get '/comments'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end

  test "No-prefetch Comments Index" do
    #Rails.logger.level = ActiveSupport::Logger::DEBUG
    get '/comments/extra/index_without_prefetching'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end
  
  test "Naive Comments Index" do
    #Rails.logger.level = ActiveSupport::Logger::DEBUG
    get '/comments/extra/naive_index'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end
end
