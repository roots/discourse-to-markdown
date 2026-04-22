# frozen_string_literal: true

module DiscourseToMarkdown
  module TagsControllerPatch
    extend ActiveSupport::Concern

    prepended do
      before_action :enforce_acceptable_representation
      before_action :render_tag_topics_as_markdown_if_md
      after_action :advertise_markdown_alternate_link
    end

    private

    def render_tag_topics_as_markdown_if_md
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless request.format.symbol == :md

      filter_name = resolve_tag_filter_name
      return if Discourse.filters.exclude?(filter_name)

      list_opts = build_topic_list_options
      query = TopicQuery.new(current_user, list_opts)
      list =
        if filter_name == :top
          period = params[:period] || SiteSetting.top_page_default_timeframe.to_sym
          TopTopic.validate_period(period)
          query.list_top_for(period)
        else
          query.public_send("list_#{filter_name}")
        end

      render_markdown(
        TopicListRenderer.render(
          topics: list.topics,
          title: tag_list_title(filter_name),
          request_path: request.path,
          page: params[:page],
        ),
      )
    end

    def resolve_tag_filter_name
      case action_name
      when "show"
        :latest
      when /\Ashow_(.+)\z/
        Regexp.last_match(1).to_sym
      else
        action_name.to_sym
      end
    end

    def tag_list_title(filter_name)
      tag_name = @tag&.name || params[:tag_id] || params[:tag_name] || "Tag"
      "##{tag_name} — #{filter_name.to_s.titleize}"
    end
  end
end
