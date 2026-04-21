# frozen_string_literal: true

module DiscourseToMarkdown
  module ListControllerPatch
    extend ActiveSupport::Concern

    prepended do
      before_action :enforce_acceptable_representation
      before_action :render_topic_list_as_markdown_if_md
      after_action :advertise_markdown_alternate_link
      after_action :advertise_markdown_in_rss_feed
    end

    private

    # Inject a `<atom:link rel="alternate" type="text/markdown">` element
    # into RSS feeds so feed readers and LLMs can discover the Markdown
    # version alongside the RSS one. Matches the WP plugin's `rss2_head`
    # hook.
    def advertise_markdown_in_rss_feed
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless response.media_type == "application/rss+xml"
      return unless response.body.is_a?(String)

      md_url = markdown_alternate_url_for(request.path.sub(/\.rss\z/, ""))
      inject = %(<atom:link href="#{md_url}" rel="alternate" type="text/markdown" />)

      new_body =
        response
          .body
          .sub(%r{<atom:link[^>]*rel="self"[^>]*/?>}) { |match| "#{match}\n    #{inject}" }
      response.body = new_body if new_body != response.body
    end

    def render_topic_list_as_markdown_if_md
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless request.format.symbol == :md

      filter_name = resolve_filter_name
      return if Discourse.filters.exclude?(filter_name)

      list_opts = build_topic_list_options
      list_opts[:category] = @category.id if @category && list_opts[:category].blank?

      query = TopicQuery.new(current_user, list_opts)
      list =
        if filter_name == :top
          period =
            params[:period].presence ||
              ListController.best_period_for(current_user&.previous_visit_at, list_opts[:category])
          TopTopic.validate_period(period)
          query.list_top_for(period)
        else
          query.public_send("list_#{filter_name}")
        end

      render plain:
               TopicListRenderer.render(
                 topics: list.topics,
                 title: topic_list_title(filter_name, list_opts),
                 request_path: request.path,
                 page: params[:page],
               ),
             content_type: "text/markdown"
    end

    # `/c/:slug/:id` routes to `category_default`, which dispatches to the
    # category's configured default view (latest/hot/top). Translate that to
    # a concrete filter we can query directly. Other category_* actions
    # share the bare filter suffix after stripping the prefix.
    def resolve_filter_name
      case action_name
      when "category_default"
        view = @category&.default_view.to_s
        %w[hot latest top].include?(view) ? view.to_sym : :latest
      when /\Acategory_(?:none_)?(.+)\z/
        Regexp.last_match(1).to_sym
      else
        action_name.to_sym
      end
    end

    def topic_list_title(filter_name, list_opts)
      base = filter_name.to_s.titleize
      category = @category || (list_opts[:category] && Category.find_by(id: list_opts[:category]))
      category ? "#{category.name} — #{base}" : base
    end
  end
end
