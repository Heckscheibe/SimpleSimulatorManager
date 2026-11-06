# frozen_string_literal: true

# Run with: ruby fastlane/tests/release_tooling_test.rb
require "minitest/autorun"
require_relative "../release_notes"
require_relative "../appcast"

class ReleaseNotesHtmlTest < Minitest::Test
  NOTES = <<~MD
    ## What's Changed

    ### Features

    * Add updater by @someone in https://github.com/o/r/pull/12
      Updates itself with `Sparkle`. **Nothing** installs unasked.

    ### Bugfixes

    - Fix <thing> by @other in https://github.com/o/r/pull/13

    **Full Changelog**: https://github.com/o/r/compare/v1.4.0...v1.5.0
  MD

  def html
    @html ||= ReleaseNotes.to_html(NOTES, "1.5.0")
  end

  def test_closes_every_list_item_and_list
    assert_equal html.scan("<li>").size, html.scan("</li>").size
    assert_equal html.scan("<ul>").size, html.scan("</ul>").size
    assert_equal 2, html.scan("<ul>").size
  end

  def test_continuation_line_stays_in_its_item_with_inline_markup
    assert_includes html, "<br>Updates itself with <code>Sparkle</code>. <strong>Nothing</strong> installs unasked.</li>"
  end

  def test_escapes_markup_from_pr_titles
    assert_includes html, "Fix &lt;thing&gt; by @other"
    refute_includes html, "<thing>"
  end

  def test_links_bare_urls_and_renders_the_footer
    assert_includes html, '<a href="https://github.com/o/r/compare/v1.4.0...v1.5.0">'
    assert_includes html, "<p><strong>Full Changelog</strong>: "
  end
end

class AppcastTest < Minitest::Test
  PREFIX = "https://github.com/o/r/releases/download/"

  def rewrite(contents)
    Appcast.point_enclosures_at_release_tags(contents, url_prefix: PREFIX, zip_name: "SimulatorManager",
                                                       tag_for: ->(version) { "v#{version}" })
  end

  def test_each_archive_gets_its_own_tag
    out = rewrite(%(<enclosure url="#{PREFIX}SimulatorManager-1.4.0.zip"/><enclosure url="#{PREFIX}SimulatorManager-1.5.0-beta1.zip"/>))

    assert_includes out, %(url="#{PREFIX}v1.4.0/SimulatorManager-1.4.0.zip")
    assert_includes out, %(url="#{PREFIX}v1.5.0-beta1/SimulatorManager-1.5.0-beta1.zip")
  end

  def test_rewritten_urls_are_not_rewritten_again
    once = rewrite(%(<enclosure url="#{PREFIX}SimulatorManager-1.5.0.zip"/>))

    assert_equal once, rewrite(once)
  end

  def test_enclosure_url_matches_the_rewrite
    out = rewrite(%(<enclosure url="#{PREFIX}SimulatorManager-1.5.0.zip"/>))

    assert_includes out, Appcast.enclosure_url(url_prefix: PREFIX, tag: "v1.5.0", zip_file_name: "SimulatorManager-1.5.0.zip")
  end
end
