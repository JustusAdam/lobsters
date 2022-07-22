ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'


class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...

  module FixturesHelper

    NUM_USERS = ENV.fetch('NUM_USERS', 100).to_i
    NUM_STORIES = ENV.fetch('NUM_STORIES', ENV.fetch('STORIES_PER_USER', 5).to_i * NUM_USERS).to_i
    NUM_HIDDEN_STORIES = ENV.fetch('NUM_HIDDEN_STORIES', NUM_USERS * ENV.fetch('HIDDEN_STORIES_PER_USER', 3).to_i).to_i
    NUM_HATS = ENV.fetch('NUM_HATS', (NUM_USERS / 10).floor).to_i
    NUM_COMMENTS = ENV.fetch('NUM_COMMENTS', NUM_STORIES * ENV.fetch('COMMENTS_PER_STORY', 4).to_i).to_i
    CHANCE_STORY_IS_DELETED = ENV.fetch('CHANCE_STORY_IS_DELETED', 0.0).to_f

    def chance_story_is_deleted
      CHANCE_STORY_IS_DELETED
    end

    def num_stories
      NUM_STORIES
    end

    def num_users
      NUM_USERS
    end

    def num_hidden_stories
      NUM_HIDDEN_STORIES
    end

    def num_hats
      NUM_HATS
    end

    def num_comments
      NUM_COMMENTS
    end

    def user_id(n)
      "user_#{n}"
    end

    def rand_user
      user_id(sample(NUM_USERS))
    end

    def story_id(n)
      "story_#{n}"
    end

    def rand_story
      story_id(sample(NUM_STORIES))
    end

    def comment_id(n)
      "comment_#{n}"
    end

    def rand_comment
      comment_id(sample(NUM_COMMENTS))
    end

  private 
    def sample(n)
      rand(Range::new(0, n, true))
    end
  end
  ActiveRecord::FixtureSet.context_class.include FixturesHelper
end
