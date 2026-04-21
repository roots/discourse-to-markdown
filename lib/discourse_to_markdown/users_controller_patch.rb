# frozen_string_literal: true

module DiscourseToMarkdown
  module UsersControllerPatch
    extend ActiveSupport::Concern

    prepended do
      before_action :enforce_acceptable_representation, only: :show
      before_action :render_user_activity_as_markdown_if_md, only: :show
      after_action :advertise_markdown_alternate_link, only: :show
    end

    private

    def render_user_activity_as_markdown_if_md
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless request.format.symbol == :md
      return if request.path.exclude?("/activity")

      user = fetch_user_from_params
      raise Discourse::NotFound unless user && guardian.can_see?(user)

      list = TopicQuery.new(current_user).list_topics_by(user)

      render plain:
               TopicListRenderer.render(
                 topics: list.topics,
                 title: "@#{user.username} — Activity",
                 request_path: request.path,
                 page: params[:page],
               ),
             content_type: "text/markdown"
    end
  end
end
