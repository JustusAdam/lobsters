require 'test_helper'
ActiveRecord::Base.maintain_test_schema = Misc.to_bool(ENV.fetch("KEEP_TEST_DATABASE", true))
require 'rails/performance_test_help'

require 'tempfile'

class CommentsIndexTest < ActionDispatch::PerformanceTest
  self.profile_options = { runs: ENV.fetch("NUM_TEST_RUNS", 5).to_i, metrics: [:wall_time] }
  # Refer to the documentation for all available options
  # self.profile_options = { runs: 5, metrics: [:wall_time, :memory],
  #                          output: 'tmp/performance', formats: [:flat] }

  setup do 
    CommentsController::get_handle
  end

  test "Original Comments Index" do
    configure_logging
    get '/comments'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end

  test "No-prefetch Comments Index" do
    configure_logging
    get '/comments/extra/index_without_prefetching'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end
  
  test "Naive Comments Index" do
    configure_logging
    get '/comments/extra/naive_index'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end

  test "Nohua Comments Index" do 
    configure_logging
    
    get '/comments/extra/nohua_index'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end
end
