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

  COMMENTS_QUERY = ENV.fetch "NOHUA_COMMENTS_QUERY", "comments_query"
  HIDDEN_STORIES_QUERY = ENV.fetch "NOHUA_HIDDEN_STORIES_QUERY", "hidden_stories_query"

  setup do 
    if NORIA_CONNECTION.nil? 
      dbcfg = Rails.configuration.database_configuration[Rails.env]
      Tempfile.create('test-db-dump.sql') do |tempfile|
        puts "dumping database to tmeporary file #{tempfile.path}"

        system "mariadb-dump", dbcfg[:database], "--host", dbcfg[:host], "--port", dbcfg[:port], 1=>tempfile.path
        puts "Dump filled the file with #{tempfile.size} bytes"
        NORIA_CONNECTION = NoriaInterface.setup_connection tempfile.path
        NoriaInterface.install_udf NORIA_CONNECTION, COMMENTS_QUERY
        NoriaInterface.install_udf NORIA_CONNECTION, HIDDEN_STORIES_QUERY
      end
    end
  end

  def make_chunked_fetcher(base_query, key, chunk_size)
    Enumerator.new do |y|
      offs = 0
      limit = chunk_size
      known_queries = {}
      loop do
        qname = Random.bytes(12)
        query = "#{base_query} LIMIT #{limit} OFFSET #{offset}"
        unless known_queries.include? query
          NoriaInterface.install_query NORIA_CONNECTION, "VIEW #{qname}: #{query}"
          known_queries[query] = qname
        else
          qname = known_queries[query]
        end
        res = NoriaInterface.run_query NORIA_CONNECTION, qname, key
        break if res.nil?
        y << res
        offset += chunk_size
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

  test "Nohua Comments Index" do 
    configure_logging
    
    


  end
end
