require "test_helper"

class ORMTest < ActiveSupport::TestCase

  test 'naive ORM replying comments' do
    count = 0
    user = users(:reader)
    ReadRibbon.where(is_following: true, user_id: user.id).each do |ribbon|
      story = ribbon.story
      story.comments.where('user_id <> ? AND NOT is_deleted AND NOT is_moderated AND ? < created_at', ribbon.user_id, ribbon.updated_at).each do |comment|
        parent = comment.parent_comment
        saldo = comment.upvotes - comment.downvotes
        if saldo < 1
          next
        end
        if parent.nil? and story.user_id == ribbon.user_id
          count += 1
        elsif not parent.nil? and parent.user_id == ribbon.user_id and parent.upvotes - parent.downvotes
          count += 1
        end
      end
    end
    assert(1, count)
  end

  test 'optimized ORM replying comments' do
    count = 0
    user = users(:reader)
    ReadRibbon
      .where(is_following: true, user_id: user.id)
      .joins(story: :comments)
      .where(story: {comments: { is_deleted: false, is_moderated: false } })
      .where('comments.user_id <> read_ribbons.user_id', 'read_ribbons.updated_at < comments.created_at')
      .includes(story: {comments: :parent_comment}).each do |ribbon|
      ribbon.story.comments.each do |comment|
        parent = comment.parent_comment
        saldo = comment.upvotes - comment.downvotes
        if saldo < 1
          next
        end
        if parent.nil? and story.user_id == ribbon.user_id
          count += 1
        elsif not parent.nil? and parent.user_id == ribbon.user_id and parent.upvotes - parent.downvotes
          count += 1
        end
      end
    end
    assert(1, count)
  end
end
