require 'test_helper'
ActiveRecord::Base.maintain_test_schema = Misc.to_bool(ENV.fetch("KEEP_TEST_DATABASE", true))
require 'rails/performance_test_help'

require 'tempfile'

class CommentsIndexTest < ActionDispatch::PerformanceTest
  self.profile_options = { runs: ENV.fetch("NUM_TEST_RUNS", 5).to_i, metrics: [:wall_time] }
  # Refer to the documentation for all available options
  # self.profile_options = { runs: 5, metrics: [:wall_time, :memory],
  #                          output: 'tmp/performance', formats: [:flat] }

  COMMENTS_QUERY = ENV.fetch "NOHUA_COMMENTS_QUERY", "comments_query"
  HIDDEN_STORIES_QUERY = ENV.fetch "NOHUA_HIDDEN_STORIES_QUERY", "hidden_stories_query"
  FETCH_HIDDEN_Q = "fetch_hidden"

  setup do 
    NoriaInterface.get_handle
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
          NoriaInterface.install_query NoriaInterface.get_handle, "VIEW #{qname}: #{query}"
          known_queries[query] = qname
        else
          qname = known_queries[query]
        end
        res = NoriaInterface.run_query NoriaInterface.get_handle, qname, key
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
    
    comments = []

    make_chunked_fetcher("SELECT * FROM #{COMMENTS_QUERY} WHERE id = ?", CommentsController.COMMENTS_PER_PAGE).each do |res|
      loop do
        row = NoriaInterface.next_row res
        break if row.nil?
        fetch = ->(convert) {
          ->(n) {
            dt = NoriaInterface.row_index(row, n)
            if NoriaInterface.datatype_is_null(dt) then nil else convert(dt) end
          }
        }
        int = fetch.call(NoriaInterface.datatype_to_int)
        string = fetch.call(NoriaInterface.datatype_to_string)
        float = fetch.call(NoriaInterface.datatype_to_float)
        bool = fetch.call(NoriaInterface.datatype_to_bool)
        comments.push Comment.new(
          id: int.call(row, "id"),
          #t.datetime "created_at", null: false
          #t.datetime "updated_at"
          short_id: string.call("short_id"),
          story: Story.new(
            id: int.call("story_id"),
            #"user_id", null: false, unsigned: true
            url: string.call("url"),
            title: string.call("title"),
            description: string.call("description"),
            #"short_id", limit: 6, default: "", null: false
            #is_deleted: bool.call("is_deleted"),
            #"score", default: 1, null: false
            #"flags", default: 0, null: false, unsigned: true
            is_moderated: bool.call("is_moderated"),
            hotness: float.call("hotness"),
            markeddown_description: string.call("markeddown_description"),
            story_cache: string.call("story_cache"),
            comments_count: int.call("comments_count"),
            merged_story_id: int.call("merged_story_id"),
            twitter_id: string.call("twitter_id"),
            user_is_author: bool.call("user_is_author"),
            user_is_following: bool.call("user_is_following"),
          ),
          user: User.new(
            id: int.call("user_id"),
            username: string.call("username"),
            email: string.call("email"),
            password_digest: string.call("password_digest"),
            is_admin: bool.call("is_admin"),
            password_reset_token: string.call("password_reset_token"),
            session_token: string.call("session_token"),
            about: string.call("about"),
            invited_by_user_id: int.call("invited_by_user_id"),
            is_moderator: bool.call("is_moderator"),
            pushover_mentions: bool.call("pushover_mentions"),
            rss_token: string.call("rss_token"),
            mailing_list_known: string.call.call("mailing_list_token"),
            mailiing_list_mode: int.call("mailing_list_mode"),
            karma: int.call("karma"),
            #t.datetime "banned_at"
            banned_by_user_id: int.call("banned_by_user_id"), 
            banned_reason: string.call("banned_reason"),
            #t.datetime "deleted_at"
            #t.datetime "disabled_invite_at"
            disabled_invite_by_user_id: int.call("disabled_invite_by_user_id"),
            disabled_invite_reason: string.call("disabled_invite_reason"),
            settings: string.call("settings")
          ),
          parent_comment_id: int.call("parent_comment_id"),
          thread_id: string.call("thread_id"),
          comment: string.call("comment"),
          score: int.call("score"),
          flags: int.call("flags"),
          confidence: float.call("confidence"),
          markeddown_comment: string.call("markeddown_comment"),
          is_deleted: bool.call("is_deleted"),
          is_moderated: bool.call("is_moderated"),
          is_from_email: bool.call("is_from_email"),
          hat: Hat.new(
            id: int.call("hat_id"),
            hat: string.call("hat"),
            link: string.call("link"),
            modlog_use: bool.call("modlog_use")
          )
        )
      end
    end

  end
end
