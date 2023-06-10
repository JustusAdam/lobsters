class CommentsController < ApplicationController
  COMMENTS_PER_PAGE = ENV.fetch("COMMENTS_PER_PAGE", 20).to_i

  caches_page :index, :threads, if: CACHE_PAGE

  before_action :require_logged_in_user_or_400,
                :only => [:create, :preview, :upvote, :flag, :unvote]
  before_action :require_logged_in_user, :only => [:upvoted]
  before_action :flag_warning, only: [:threads]
  before_action :show_title_h1

  # for rss feeds, load the user's tag filters if a token is passed
  before_action :find_user_from_rss_token, :only => [:index]

  class StopIteration < Exception
  end

  COMMENTS_QUERY = ENV.fetch "NOHUA_COMMENTS_QUERY", "comments_query"
  HIDDEN_STORIES_QUERY = ENV.fetch "NOHUA_HIDDEN_STORIES_QUERY", "hidden_stories_query"
  FETCH_HIDDEN_Q = "fetch_hidden"

  def self.get_handle 
    unless const_defined?(:NORIA_CONNECTION)
      dbcfg = Rails.configuration.database_configuration[Rails.env]
      Tempfile.create('test-db-dump.sql') do |tempfile|
        puts "dumping database to temporary file #{tempfile.path}"
        dbargs = []
        add_arg = ->(name, arg) { dbargs.push(arg, dbcfg[name]) unless dbcfg[name].nil? }
        add_arg.call("host", "--host")
        add_arg.call("port", "--port")
        add_arg.call("socket", "--socket")
        puts "Using conf parameters #{dbargs}"

        system "mariadb-dump", "--skip-create-options", "--compact", dbcfg["database"], *dbargs, 1=>tempfile.path
        puts "Dump filled the file with #{tempfile.size} bytes"
        const_set :NORIA_CONNECTION, NoriaInterface.setup_connection(tempfile.path)
        NoriaInterface.install_udf NORIA_CONNECTION, COMMENTS_QUERY
        # NoriaInterface.install_udf NORIA_CONNECTION, HIDDEN_STORIES_QUERY
        # NoriaInterface.install_query NORIA_CONNECTION, "VIEW #{FETCH_HIDDEN_Q}: SELECT * FROM #{HIDDEN_STORIES_QUERY} WHERE uid = ?"
      end
    end
    NORIA_CONNECTION
  end

  CHUNKED_FETCHER_KNOWN_QUERIES = Hash.new

  def make_chunked_fetcher(base_query, key, chunk_size)
    Enumerator.new do |y|
      offset = 0
      limit = chunk_size
      loop do
        prior = CHUNKED_FETCHER_KNOWN_QUERIES[base_query]
        qname = nil
        qlim = limit + offset
        if !prior.nil? && prior[1] >= qlim
          qname = prior[0]
        else
          query = "#{base_query} LIMIT #{qlim}"
          qname = query.hash.abs
          puts "Creating fetcher for query #{qname} created"
          if prior.nil? 
            NoriaInterface.remove_view qname.to_s
          end
          NoriaInterface.install_query self.class.get_handle, "VIEW #{qname}: #{query}"
          CHUNKED_FETCHER_KNOWN_QUERIES[base_query] = [qname, qlim]
        end
        res = NoriaInterface.run_query self.class.get_handle, qname.to_s, key
        break if res.null?
        NoriaInterface.advance_result(res, offset)
        y << res
        offset += chunk_size
      end
    end
  end

  def create
    if !(story = Story.where(:short_id => params[:story_id]).first) ||
       story.is_gone?
      return render :plain => "can't find story", :status => 400
    end

    comment = story.comments.build
    comment.comment = params[:comment].to_s
    comment.user = @user

    if params[:hat_id] && @user.wearable_hats.where(:id => params[:hat_id])
      comment.hat_id = params[:hat_id]
    end

    if params[:parent_comment_short_id].present?
      if (pc = Comment.where(:story_id => story.id, :short_id => params[:parent_comment_short_id])
        .first)
        comment.parent_comment = pc
      else
        return render :json => { :error => "invalid parent comment", :status => 400 }
      end
    end

    # sometimes on slow connections people resubmit; silently accept it
    if (already = Comment.find_by(user: comment.user,
                                  story: comment.story,
                                  parent_comment_id: comment.parent_comment_id,
                                  comment: comment.comment))
      self.render_created_comment(already)
      return
    end

    # rate-limit users to one reply per 5m per parent comment
    if params[:preview].blank? &&
       (pc = Comment.where(:story_id => story.id,
                           :user_id => @user.id,
                           :parent_comment_id => comment.parent_comment_id).first)
      if (Time.current - pc.created_at) < 5.minutes && !@user.is_moderator?
        comment.errors.add(:comment, "^You have already posted a comment " <<
          "here recently.")

        return render :partial => "commentbox", :layout => false,
          :content_type => "text/html", :locals => { :comment => comment }
      end
    end

    if comment.valid? && params[:preview].blank? && ActiveRecord::Base.transaction { comment.save }
      comment.current_vote = { :vote => 1 }
      self.render_created_comment(comment)
    else
      comment.score = 1
      comment.current_vote = { :vote => 1 }

      preview comment
    end
  end

  def render_created_comment(comment)
    if request.xhr?
      render :partial => "comments/postedreply", :layout => false,
        :content_type => "text/html", :locals => { :comment => comment }
    else
      redirect_to comment.path
    end
  end

  def show
    if !((comment = find_comment) && comment.is_editable_by_user?(@user))
      return render :plain => "can't find comment", :status => 400
    end

    render :partial => "comment",
           :layout => false,
           :content_type => "text/html",
           :locals => {
             :comment => comment,
             :show_tree_lines => params[:show_tree_lines],
           }
  end

  def show_short_id
    if !(comment = find_comment)
      return render :plain => "can't find comment", :status => 400
    end

    render :json => comment.as_json
  end

  def redirect_from_short_id
    if (comment = find_comment)
      return redirect_to comment.path
    else
      return render :plain => "can't find comment", :status => 400
    end
  end

  def edit
    if !((comment = find_comment) && comment.is_editable_by_user?(@user))
      return render :plain => "can't find comment", :status => 400
    end

    render :partial => "commentbox", :layout => false,
      :content_type => "text/html", :locals => { :comment => comment }
  end

  def reply
    if !(parent_comment = find_comment)
      return render :plain => "can't find comment", :status => 400
    end

    comment = Comment.new
    comment.story = parent_comment.story
    comment.parent_comment = parent_comment

    render :partial => "commentbox", :layout => false,
      :content_type => "text/html", :locals => { :comment => comment }
  end

  def delete
    if !((comment = find_comment) && comment.is_deletable_by_user?(@user))
      return render :plain => "can't find comment", :status => 400
    end

    comment.delete_for_user(@user, params[:reason])

    render :partial => "comment", :layout => false,
      :content_type => "text/html", :locals => { :comment => comment }
  end

  def undelete
    if !((comment = find_comment) && comment.is_undeletable_by_user?(@user))
      return render :plain => "can't find comment", :status => 400
    end

    comment.undelete_for_user(@user)

    render :partial => "comment", :layout => false,
      :content_type => "text/html", :locals => { :comment => comment }
  end

  def disown
    if !((comment = find_comment) && comment.is_disownable_by_user?(@user))
      return render :plain => "can't find comment", :status => 400
    end

    InactiveUser.disown! comment
    comment = find_comment

    render :partial => "comment", :layout => false,
      :content_type => "text/html", :locals => { :comment => comment }
  end

  def update
    if !((comment = find_comment) && comment.is_editable_by_user?(@user))
      return render :plain => "can't find comment", :status => 400
    end

    comment.comment = params[:comment]
    comment.hat_id = nil
    if params[:hat_id] && @user.wearable_hats.where(:id => params[:hat_id])
      comment.hat_id = params[:hat_id]
    end

    if params[:preview].blank? && comment.save
      votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, [comment.id])
      comment.current_vote = votes[comment.id]

      render :partial => "comments/comment",
             :layout => false,
             :content_type => "text/html",
             :locals => { :comment => comment, :show_tree_lines => params[:show_tree_lines] }
    else
      comment.current_vote = { :vote => 1 }

      preview comment
    end
  end

  def unvote
    if !(comment = find_comment) || comment.is_gone?
      return render :plain => "can't find comment", :status => 400
    end

    Vote.vote_thusly_on_story_or_comment_for_user_because(
      0, comment.story_id, comment.id, @user.id, nil
    )

    render :plain => "ok"
  end

  def upvote
    if !(comment = find_comment) || comment.is_gone?
      return render :plain => "can't find comment", :status => 400
    end

    Vote.vote_thusly_on_story_or_comment_for_user_because(
      1, comment.story_id, comment.id, @user.id, params[:reason]
    )

    render :plain => "ok"
  end

  def flag
    if !(comment = find_comment) || comment.is_gone?
      return render :plain => "can't find comment", :status => 400
    end

    if !Vote::COMMENT_REASONS[params[:reason]]
      return render :plain => "invalid reason", :status => 400
    end

    if !@user.can_flag?(comment)
      return render :plain => "not permitted to flag", :status => 400
    end

    Vote.vote_thusly_on_story_or_comment_for_user_because(
      -1, comment.story_id, comment.id, @user.id, params[:reason]
    )

    render :plain => "ok"
  end

  def index
    @rss_link ||= {
      :title => "RSS 2.0 - Newest Comments",
      :href => "/comments.rss" + (@user ? "?token=#{@user.rss_token}" : ""),
    }

    @title = "Newest Comments"

    @page = params[:page].to_i
    if @page == 0
      @page = 1
    elsif @page < 0 || @page > (2 ** 32)
      raise ActionController::RoutingError.new("page out of bounds")
    end
    
    @comments = comments_for_index_base
      .includes(:user, :hat, :story => :user)
      .limit(COMMENTS_PER_PAGE)
      .offset((@page - 1) * COMMENTS_PER_PAGE)

    if @user
      @votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, @comments.map(&:id))

      @comments.each do |c|
        if @votes[c.id]
          c.current_vote = @votes[c.id]
        end
      end
    end

    benchmark("Rendering") do
      respond_to do |format|
        format.html { render :action => "index" }
        format.rss {
          if @user && params[:token].present?
            @title = "Private comments feed for #{@user.username}"
          end

          render :action => "index.rss", :layout => false
        }
      end
    end
  end

  def index_without_prefetching
    @rss_link ||= {
      :title => "RSS 2.0 - Newest Comments",
      :href => "/comments.rss" + (@user ? "?token=#{@user.rss_token}" : ""),
    }

    @title = "Newest Comments"

    @page = params[:page].to_i
    if @page == 0
      @page = 1
    elsif @page < 0 || @page > (2 ** 32)
      raise ActionController::RoutingError.new("page out of bounds")
    end

    @comments = comments_for_index_base
      .limit(COMMENTS_PER_PAGE)
      .offset((@page - 1) * COMMENTS_PER_PAGE)

    if @user
      @votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, @comments.map(&:id))

      @comments.each do |c|
        if @votes[c.id]
          c.current_vote = @votes[c.id]
        end
      end
    end

    benchmark("Rendering") do
      respond_to do |format|
        format.html { render :action => "index" }
        format.rss {
          if @user && params[:token].present?
            @title = "Private comments feed for #{@user.username}"
          end

          render :action => "index.rss", :layout => false
        }
      end
    end
  end
  
  def nohua_index
    @rss_link ||= {
      :title => "RSS 2.0 - Newest Comments",
      :href => "/comments.rss" + (@user ? "?token=#{@user.rss_token}" : ""),
    }

    @title = "Newest Comments"

    @page = params[:page].to_i
    if @page == 0
      @page = 1
    elsif @page < 0 || @page > (2 ** 32)
      raise ActionController::RoutingError.new("page out of bounds")
    end

    @comments = []
    f = make_chunked_fetcher("SELECT * FROM #{COMMENTS_QUERY}", 0, COMMENTS_PER_PAGE)
    f.each do |res|
      loop do
        row = NoriaInterface.next_row res
        break if !row || COMMENTS_PER_PAGE <= @comments.size
        @comments.push Comment.new(
          id: row.int("id"),
          #t.datetime "updated_at"
          short_id: row.string("short_id"),
          story: Story.new(
            id: row.int("story_id"),
            #"user_id", null: false, unsigned: true
            url: row.string("url"),
            title: row.string("title"),
            description: row.string("description"),
            #"short_id", limit: 6, default: "", null: false
            #is_deleted: row.bool("is_deleted"),
            #"score", default: 1, null: false
            #"flags", default: 0, null: false, unsigned: true
            is_moderated: row.bool("is_moderated"),
            hotness: row.float("hotness"),
            markeddown_description: row.string("markeddown_description"),
            story_cache: row.string("story_cache"),
            comments_count: row.int("comments_count"),
            merged_story_id: row.int("merged_story_id"),
            twitter_id: row.string("twitter_id"),
            user_is_author: row.bool("user_is_author"),
            user_is_following: row.bool("user_is_following"),
          ),
          user: User.new(
            id: row.int("user_id"),
            username: row.string("username"),
            email: row.string("email"),
            password_digest: row.string("password_digest"),
            is_admin: row.bool("is_admin"),
            password_reset_token: row.string("password_reset_token"),
            session_token: row.string("session_token"),
            about: row.string("about"),
            invited_by_user_id: row.int("invited_by_user_id"),
            is_moderator: row.bool("is_moderator"),
            pushover_mentions: row.bool("pushover_mentions"),
            rss_token: row.string("rss_token"),
            mailing_list_token: row.string("mailing_list_token"),
            mailing_list_mode: row.int("mailing_list_mode"),
            karma: row.int("karma"),
            #t.datetime "banned_at"
            banned_by_user_id: row.int("banned_by_user_id"), 
            banned_reason: row.string("banned_reason"),
            #t.datetime "deleted_at"
            #t.datetime "disabled_invite_at"
            disabled_invite_by_user_id: row.int("disabled_invite_by_user_id"),
            disabled_invite_reason: row.string("disabled_invite_reason"),
            settings: row.string("settings")
          ),
          parent_comment_id: row.int("parent_comment_id"),
          thread_id: row.string("thread_id"),
          comment: row.string("comment"),
          score: row.int("score"),
          flags: row.int("flags"),
          confidence: row.float("confidence"),
          markeddown_comment: row.string("markeddown_comment"),
          is_deleted: row.bool("is_deleted"),
          is_moderated: row.bool("is_moderated"),
          is_from_email: row.bool("is_from_email"),
          hat: Hat.new(
            id: row.int("hat_id"),
            hat: row.string("hat"),
            link: row.string("link"),
            modlog_use: row.bool("modlog_use"),
            created_at: row.time("created_at")
          )
        )
      end
      break if COMMENTS_PER_PAGE <= @comments.size
      # Needed, because otherwise inner break does not cascade
    end
    
    if @user
      @votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, @comments.map(&:id))

      @comments.each do |c|
        if @votes[c.id]
          c.current_vote = @votes[c.id]
        end
      end
    end

    benchmark("Rendering") do
      respond_to do |format|
        format.html { render :action => "index" }
        format.rss {
          if @user && params[:token].present?
            @title = "Private comments feed for #{@user.username}"
          end

          render :action => "index.rss", :layout => false
        }
      end
    end
  end


  def naive_index
    @rss_link ||= {
      :title => "RSS 2.0 - Newest Comments",
      :href => "/comments.rss" + (@user ? "?token=#{@user.rss_token}" : ""),
    }

    @title = "Newest Comments"

    @page = params[:page].to_i
    if @page == 0
      @page = 1
    elsif @page < 0 || @page > (2 ** 32)
      raise ActionController::RoutingError.new("page out of bounds")
    end

    @comments = []
    begin
      Comment
        .order("id DESC")
        # I'm leaving the first two methods since they don't really do anything so long as we do not set @user
        .accessible_to_user(@user)
        .not_on_story_hidden_by(@user)
        .find_each(batch_size: (COMMENTS_PER_PAGE * 1.3).to_i) do |comment|
          if !comment.story.is_deleted
            @comments.push comment
          end
          if @comments.size >= COMMENTS_PER_PAGE
            raise StopIteration.new
          end
        end
    rescue StopIteration
    end
    
    if @user
      @votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, @comments.map(&:id))

      @comments.each do |c|
        if @votes[c.id]
          c.current_vote = @votes[c.id]
        end
      end
    end

    benchmark("Rendering") do
      respond_to do |format|
        format.html { render :action => "index" }
        format.rss {
          if @user && params[:token].present?
            @title = "Private comments feed for #{@user.username}"
          end

          render :action => "index.rss", :layout => false
        }
      end
    end
  end

  def upvoted
    @rss_link ||= {
      :title => "RSS 2.0 - Newest Comments",
      :href => upvoted_comments_path(format: :rss) + (@user ? "?token=#{@user.rss_token}" : ""),
    }

    @title = "Upvoted Comments"
    @saved_subnav = true

    @page = params[:page].to_i
    if @page == 0
      @page = 1
    elsif @page < 0 || @page > (2 ** 32)
      raise ActionController::RoutingError.new("page out of bounds")
    end

    @comments = Comment.accessible_to_user(@user)
      .where.not(user_id: @user.id)
      .order("id DESC")
      .includes(:user, :hat, :story => :user)
      .joins(:votes).where(votes: { user_id: @user.id, vote: 1 })
      .joins(:story).where.not(stories: { is_deleted: true })
      .limit(COMMENTS_PER_PAGE)
      .offset((@page - 1) * COMMENTS_PER_PAGE)

    # TODO: respect hidden stories

    @votes = Vote.comment_votes_by_user_for_comment_ids_hash(@user.id, @comments.map(&:id))
    @comments.each do |c|
      c.current_vote = @votes[c.id]
    end

    respond_to do |format|
      format.html { render action: :index }
      format.rss {
        if @user && params[:token].present?
          @title = "Upvoted comments feed for #{@user.username}"
        end

        render :action => "index.rss", :layout => false
      }
    end
  end

  def threads
    if params[:user]
      @showing_user = User.find_by!(username: params[:user])
      @title = "Threads for #{@showing_user.username}"
    elsif !@user
      return redirect_to active_path
    else
      @showing_user = @user
      @title = "Your Threads"
    end

    thread_ids = @showing_user.recent_threads(
      20,
      include_submitted_stories: !!(@user && @user.id == @showing_user.id),
      for_user: @user
    )

    comments = Comment.accessible_to_user(@user)
      .where(:thread_id => thread_ids)
      .includes(:user, :hat, :story => :user, :votes => :user)
      .joins(:story).where.not(stories: { is_deleted: true })
      .arrange_for_user(@user)

    comments_by_thread_id = comments.group_by(&:thread_id)
    @threads = comments_by_thread_id.values_at(*thread_ids).compact

    if @user
      @votes = Vote.comment_votes_by_user_for_story_hash(@user.id, comments.map(&:story_id).uniq)

      comments.each do |c|
        if @votes[c.id]
          c.current_vote = @votes[c.id]
        end
      end
    end
  end

private

  def comments_for_index_base
    Comment.accessible_to_user(@user)
      .not_on_story_hidden_by(@user)
      .order("id DESC")
      .joins("STRAIGHT_JOIN stories ON stories.id = comments.story_id")
      .where.not(stories: { is_deleted: true })
  end

  def preview(comment)
    comment.previewing = true
    comment.is_deleted = false # show normal preview for deleted comments

    render :partial => "comments/commentbox",
           :layout => false,
           :content_type => "text/html",
           :locals => {
             :comment => comment,
             :show_comment => comment,
             :show_tree_lines => params[:show_tree_lines],
           }
  end

  def find_comment
    comment = Comment.where(short_id: params[:id]).first
    if @user && comment
      comment.current_vote = Vote.where(:user_id => @user.id,
        :story_id => comment.story_id, :comment_id => comment.id).first
    end

    comment
  end
end
