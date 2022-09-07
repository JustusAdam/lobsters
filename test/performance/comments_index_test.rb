require 'test_helper'
ActiveRecord::Base.maintain_test_schema = Misc.to_bool(ENV.fetch("KEEP_TEST_DATABASE", true))
require 'rails/performance_test_help'

require 'tempfile'

class CommentsIndexTest < ActionDispatch::PerformanceTest
  NORIA_CONNECTION = nil
  self.profile_options = { runs: ENV.fetch("NUM_TEST_RUNS", 5).to_i, metrics: [:wall_time] }
  # Refer to the documentation for all available options
  # self.profile_options = { runs: 5, metrics: [:wall_time, :memory],
  #                          output: 'tmp/performance', formats: [:flat] }

  setup do 
    if NORIA_CONNECTION.nil? 
      dbcfg = Rails.configuration.database_configuration[Rails.env]
      Tempfile.create('test-db-dump.sql') do |tempfile|
        puts "dumping database to tmeporary file #{tempfile.path}"

        system "mariadb-dump", dbcfg[:database], "--host", dbcfg[:host], "--port", dbcfg[:port], 1=>tempfile.path
        puts "Dump filles the file with #{tempfile.size} bytes"
        NORIA_CONNECTION = NoriaInterface.setup_connection tempfile.path
      end
    end
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
end
