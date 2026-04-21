# frozen_string_literal: true

# name: discourse-to-markdown
# about: Serve Discourse content as Markdown via Accept negotiation and .md URLs
# version: 0.1.0
# authors: Ben Word
# url: https://github.com/roots/discourse-to-markdown
# required_version: 2026.3.0

enabled_site_setting :discourse_to_markdown_enabled

gem "reverse_markdown", "3.0.2", require_name: "reverse_markdown"

module ::DiscourseToMarkdown
  PLUGIN_NAME = "discourse-to-markdown"
end

require_relative "lib/discourse_to_markdown/engine"

after_initialize do
  Mime::Type.register "text/markdown", :md unless Mime::Type.lookup_by_extension(:md)

  advertised_controllers = %w[TopicsController ListController TagsController UsersController].freeze
  %w[server:before-head-close server:before-head-close-crawler].each do |hook|
    register_html_builder(hook) do |controller|
      next nil unless SiteSetting.discourse_to_markdown_enabled
      next nil if advertised_controllers.exclude?(controller.class.name)

      %(<link rel="alternate" type="text/markdown" href="#{controller.markdown_alternate_url_for}">)
    end
  end

  reloadable_patch do
    ApplicationController.include(::DiscourseToMarkdown::ApplicationControllerExtension)
    TopicsController.prepend(::DiscourseToMarkdown::TopicsControllerPatch)
    ListController.prepend(::DiscourseToMarkdown::ListControllerPatch)
    TagsController.prepend(::DiscourseToMarkdown::TagsControllerPatch)
    UsersController.prepend(::DiscourseToMarkdown::UsersControllerPatch)
  end
end
