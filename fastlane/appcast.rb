# frozen_string_literal: true

# Pure helpers for the Sparkle appcast, free of fastlane so they can be tested outside a lane.
module Appcast
  module_function

  # `generate_appcast` applies one --download-url-prefix to every archive, but each release's asset
  # lives under its own tag (.../download/v1.5.0/SimulatorManager-1.5.0.zip). Rewrites the enclosure
  # URLs so each archive points at the tag `tag_for.call(version)` of the version in its file name.
  def point_enclosures_at_release_tags(contents, url_prefix:, zip_name:, tag_for:)
    pattern = %r{url="#{Regexp.escape(url_prefix)}(#{Regexp.escape(zip_name)}-([^"/]+)\.zip)"}
    contents.gsub(pattern) do
      %(url="#{url_prefix}#{tag_for.call(Regexp.last_match(2))}/#{Regexp.last_match(1)}")
    end
  end

  # The exact enclosure URL a release's entry must carry once rewritten.
  def enclosure_url(url_prefix:, tag:, zip_file_name:)
    %(url="#{url_prefix}#{tag}/#{zip_file_name}")
  end
end
