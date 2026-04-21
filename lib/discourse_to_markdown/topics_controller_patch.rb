# frozen_string_literal: true

module DiscourseToMarkdown
  module TopicsControllerPatch
    extend ActiveSupport::Concern

    prepended do
      before_action :enforce_acceptable_representation, only: :show
      after_action :advertise_markdown_alternate_link, only: :show
    end

    def show
      return super unless request.format.symbol == :md
      return super unless SiteSetting.discourse_to_markdown_enabled

      topic = Topic.find_by(id: params[:id] || params[:topic_id])
      raise Discourse::NotFound if topic.nil? || !guardian.can_see?(topic)

      renderer =
        if params[:post_number].present?
          TopicRenderer.new(topic, guardian: guardian, post_number: params[:post_number])
        else
          TopicRenderer.new(topic, guardian: guardian)
        end

      raise Discourse::NotFound if params[:post_number].present? && renderer.visible_posts.empty?

      render plain: renderer.render, content_type: "text/markdown"
    end
  end
end
