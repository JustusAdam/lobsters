require 'test_helper'
require 'rails/performance_test_help'

class CommentsIndexTest < ActionDispatch::PerformanceTest
  # Refer to the documentation for all available options
  # self.profile_options = { runs: 5, metrics: [:wall_time, :memory],
  #                          output: 'tmp/performance', formats: [:flat] }

  test "Original Comments Index" do
    get '/comments'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end

  test "No-prefetch Comments Index" do
    get '/comments/extra/index2'
    assert @controller.instance_of?(CommentsController)
    assert_response :success
  end
end
